import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import 'work_editions.dart';

/// Public metadata mirror, not an official Hitomi API. Provider outages
/// affect online search only; local library search must remain independent.
class OnlineSearchWork {
  final String workId;
  final String title;
  /// Publicly supplied translated titles (never machine-fabricated).
  final List<String> titleAliases;
  final List<String> artists;
  final List<String> groups;
  final List<String> series;
  final List<String> tags;
  final String language;
  final String type;
  final String date;

  const OnlineSearchWork({
    required this.workId,
    required this.title,
    this.titleAliases = const [],
    this.artists = const [],
    this.groups = const [],
    this.series = const [],
    this.tags = const [],
    this.language = '',
    this.type = '',
    this.date = '',
  });

  factory OnlineSearchWork.fromJson(Map<String, dynamic> data) {
    List<String> names(String key) => data[key] is List
        ? (data[key] as List).whereType<String>().take(60).toList() : const [];
    String string(String key) => data[key] is String ? data[key] as String : '';
    final aliases = <String>{};
    for (final key in ['aliases', 'titles', 'alternative_titles']) {
      final value = data[key];
      if (value is List) {
        aliases.addAll(value.whereType<String>().take(20));
      } else if (value is Map) {
        aliases.addAll(value.values.whereType<String>().take(20));
      }
    }
    for (final field in [
      'title_english', 'title_japanese', 'title_korean',
      'title_romanized', 'original_title',
    ]) {
      if (data[field] is String) aliases.add(data[field] as String);
    }
    aliases.removeWhere((value) => value.trim().length < 2 ||
        value.length > 180);
    final id = data['id'];
    final code = id is int ? id.toString() :
        id is String ? id : '';
    if (!RegExp(r'^\d{1,12}$').hasMatch(code)) {
      throw const FormatException('작품 번호가 올바르지 않아.');
    }
    return OnlineSearchWork(
      workId: code,
      title: string('title').isEmpty ? '작품 ' + code : string('title'),
      titleAliases: aliases.take(24).toList(),
      artists: names('artists'), groups: names('groups'),
      series: names('series'), tags: names('tags'),
      language: string('language'),
      type: string('type'), date: string('date'),
    );
  }
}

class OnlineSearchResult {
  final List<OnlineSearchWork> works;
  final int total;
  final int page;
  final Map<String, int> fieldTotals;
  final Map<String, List<String>> matchedFields;
  final List<String> warnings;
  final bool hasNextPage;
  const OnlineSearchResult(this.works, this.total, this.page,
      {this.fieldTotals = const {}, this.matchedFields = const {},
       this.warnings = const [], this.hasNextPage = false});
}

class OnlineWorkSearch {
  final http.Client client;
  /// Two independently hosted community mirrors; no user history is sent.
  final List<Uri> providers;

  OnlineWorkSearch(this.client, {List<Uri>? providers})
      : providers = providers ?? [
          Uri.https('heliotrope.saebasol.org', '/api/hitomi/search'),
          Uri.https('inst.psec.dev', '/api/hitomi/search'),
        ];

  static List<String> tokens(String raw, {String language = ''}) {
    final term = raw.trim();
    if (term.isEmpty || term.length > 150) {
      throw const FormatException('검색어는 1~150자로 입력해줘.');
    }
    final queries = <String>[];
    // Preserve the query as one string for title phrases. Advanced terms,
    // e.g. artist:name, group:name, female:tag and language:korean, are
    // directly supported by Heliotrope's query parser.
    queries.add(term);
    if (language.isNotEmpty) queries.add('language:' + language);
    return queries;
  }

  /// Search a plain term across general, creator, circle, and supported
  /// tag fields. Source count totals can overlap; only fetched unique IDs
  /// are displayed as a true unique count.
  /// Expand one plain phrase across every supported metadata field.
  /// Explicit field:value expressions bypass expansion. Search counts from
  /// different fields overlap; only fetched gallery IDs are deduplicated.
  static List<(String, String)> planQueries(String raw) {
    final input = raw.trim();
    if (input.isEmpty || input.length > 150) {
      throw const FormatException('검색어는 1~150자로 입력해줘.');
    }
    if (RegExp(r'^[a-z][a-z_]*:', caseSensitive: false).hasMatch(input)) {
      return [('advanced', input)];
    }
    // Independently query each user-provided original/translated title.
    final alternatives = <String>[];
    for (final part in input.split('|')) {
      final term = part.trim();
      if (term.isNotEmpty && !alternatives.any(
          (existing) => existing.toLowerCase() == term.toLowerCase())) {
        alternatives.add(term);
      }
      if (alternatives.length >= 5) break;
    }
    final planned = <(String, String)>[];
    void add(String field, String value) {
      if (value.isNotEmpty && value.length <= 150 &&
          !planned.any((existing) =>
              existing.$2.toLowerCase() == value.toLowerCase())) {
        planned.add((field, value));
      }
    }
    for (final term in alternatives) {
      add('general', term);
    }
    for (var i = 0; i < alternatives.length && i < 2; i++) {
      final term = alternatives[i];
      if (term.length < 2) continue;
      final fields = i == 0
          ? const ['artist', 'group', 'series', 'tag', 'female', 'male']
          : const ['artist', 'group', 'series', 'tag'];
      for (final field in fields) {
        add(field, '$field:$term');
      }
    }
    return planned.take(16).toList();
  }

  /// Prefer a genuinely all-language index for multi-language searches.
  /// Language-specific Korean mirrors must not silently replace an
  /// international search with a Korea-only result set.
  List<Uri> _orderedProviders(String language) {
    final all = providers.where((p) => p.host == 'inst.psec.dev').toList();
    final korea = providers.where((p) => p.host == 'heliotrope.saebasol.org')
        .toList();
    if (language.toLowerCase() == 'korean') {
      return [...korea, ...all];
    }
    // If the general index is unreachable, allow a clearly identified
    // partial fallback rather than making every international search fail.
    return [...all, ...korea];
  }

  Future<OnlineSearchResult> searchUnified(String raw, {
    int page = 1,
    String language = '',
    void Function(int completed, int total)? onProgress,
    void Function(OnlineSearchResult snapshot)? onPartial,
  }) async {
    final queries = planQueries(raw);
    final unique = <String, OnlineSearchWork>{};
    final matched = <String, Set<String>>{};
    final counts = <String, int>{};
    final warnings = <String>{};
    final normalizedTerms = raw.toLowerCase().split('|')
        .map((value) => value.trim())
        .where((value) => value.length >= 2 && !value.contains(':'))
        .toList();
    var successes = 0;
    var hasMore = false;
    var completed = 0;
    const weights = {
      'general': 12, 'advanced': 12, 'artist': 10, 'series': 8,
      'group': 7, 'tag': 4, 'female': 4, 'male': 4,
    };

    OnlineSearchWork combine(OnlineSearchWork old, OnlineSearchWork next) {
      List<String> merge(List<String> first, List<String> second) =>
          {...first, ...second}.where((item) => item.trim().isNotEmpty).toList();
      final oldPlaceholder = old.title.startsWith('작품 ');
      final title = oldPlaceholder && !next.title.startsWith('작품 ')
          ? next.title : old.title;
      return OnlineSearchWork(
        workId: old.workId,
        title: title,
        titleAliases: merge(old.titleAliases, [
          ...next.titleAliases,
          if (next.title != title) next.title,
          if (old.title != title && !oldPlaceholder) old.title,
        ]),
        artists: merge(old.artists, next.artists),
        groups: merge(old.groups, next.groups),
        series: merge(old.series, next.series),
        tags: merge(old.tags, next.tags),
        language: old.language.isEmpty ? next.language : old.language,
        type: old.type.isEmpty ? next.type : old.type,
        date: old.date.isEmpty ? next.date : old.date,
      );
    }

    OnlineSearchResult snapshot() {
      final ordered = unique.values.toList();
      int score(OnlineSearchWork work) {
        var result = (matched[work.workId] ?? const <String>{})
            .fold<int>(0, (sum, field) => sum + (weights[field] ?? 1));
        final titles = [work.title, ...work.titleAliases]
            .map((title) => title.toLowerCase()).toList();
        for (final term in normalizedTerms) {
          if (titles.any((title) => title == term)) {
            result += 50;
          } else if (titles.any((title) => title.contains(term))) {
            result += 20;
          }
          if (work.artists.any((artist) =>
              artist.toLowerCase() == term)) result += 35;
        }
        return result;
      }
      ordered.sort((a, b) {
        final relevance = score(b).compareTo(score(a));
        return relevance != 0 ? relevance : a.workId.compareTo(b.workId);
      });
      return OnlineSearchResult(ordered, unique.length, page,
          fieldTotals: Map<String, int>.of(counts),
          matchedFields: matched.map((id, fields) =>
              MapEntry(id, fields.toList())),
          warnings: warnings.toList(),
          hasNextPage: hasMore);
    }

    // Keep at most three requests running; broadcast immutable snapshots as
    // each field completes without holding UI rendering for slower fields.
    for (var i = 0; i < queries.length; i += 3) {
      await Future.wait(queries.skip(i).take(3).map((entry) async {
        try {
          final result = await search(entry.$2,
              page: page, language: language);
          successes++;
          for (final warning in result.warnings) {
            warnings.add(entry.$1 + ': ' + warning);
          }
          counts.update(entry.$1, (count) => count + result.total,
              ifAbsent: () => result.total);
          hasMore = hasMore || result.works.isNotEmpty &&
              (result.total > page * 25 || result.works.length >= 25);
          for (final work in result.works) {
            final old = unique[work.workId];
            unique[work.workId] = old == null ? work : combine(old, work);
            matched.putIfAbsent(work.workId, () => <String>{})
                .add(entry.$1);
          }
        } catch (error) {
          warnings.add(entry.$1 + ': ' + error.toString());
        } finally {
          completed++;
          onProgress?.call(completed, queries.length);
          if (successes > 0) onPartial?.call(snapshot());
        }
      }));
    }
    if (successes == 0) {
      throw StateError('모든 검색 서버 요청이 실패했어: ' +
          warnings.take(2).join(' / '));
    }
    return snapshot();
  }

  Future<OnlineSearchResult> search(String raw, {
    int page = 1,
    String language = '',
  }) async {
    if (page < 1 || page > 100) {
      throw const FormatException('검색 결과 페이지 범위가 올바르지 않아.');
    }
    final searchTokens = tokens(raw, language: language);
    Object? lastError;
    for (final provider in _orderedProviders(language)) {
      if (provider.scheme != 'https' ||
          !{'heliotrope.saebasol.org', 'inst.psec.dev'}
              .contains(provider.host)) continue;
      try {
        final response = await client.post(
          provider.replace(queryParameters: {'offset': page.toString()}),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': 'HYP-Viewer/0.x',
          },
          body: jsonEncode({'query': searchTokens}),
        ).timeout(const Duration(seconds: 12));
        if (response.statusCode != 200) {
          throw HttpException('검색 서버 HTTP ' + response.statusCode.toString());
        }
        if (response.bodyBytes.length > 1024 * 1024) {
          throw const FormatException('검색 응답이 너무 커.');
        }
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is! Map<String, dynamic> || data['results'] is! List) {
          throw const FormatException('검색 결과 형식이 올바르지 않아.');
        }
        final entries = <OnlineSearchWork>[];
        final seen = <String>{};
        for (final item in (data['results'] as List).take(30)) {
          if (item is! Map<String, dynamic>) continue;
          try {
            final work = OnlineSearchWork.fromJson(item);
            // The metadata server is a community mirror. A source may
            // ignore a language filter, so reject only *known* conflicting
            // languages while retaining records whose language is unknown.
            final requested = WorkEditions.canonicalLanguage(language);
            final actual = WorkEditions.canonicalLanguage(work.language);
            if (requested.isNotEmpty && actual.isNotEmpty &&
                requested != actual) continue;
            if (seen.add(work.workId)) entries.add(work);
          } on FormatException { /* Skip a malformed item. */ }
        }
        final count = data['count'] is num
            ? (data['count'] as num).toInt().clamp(0, 100000000).toInt()
            : entries.length;
        final partial = provider.host == 'heliotrope.saebasol.org' &&
            language.toLowerCase() != 'korean';
        return OnlineSearchResult(entries, count, page,
            warnings: partial ? const [
              '전체 언어 서버에 연결할 수 없어 제한된 검색 서버를 이용했어. '
              '일부 언어의 결과가 누락될 수 있어.'
            ] : const []);
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError('온라인 검색 서버에 연결하지 못했어: ' +
        (lastError?.toString() ?? '사용할 수 있는 공급자가 없어.'));
  }
}
