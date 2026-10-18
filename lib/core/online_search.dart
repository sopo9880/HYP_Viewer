import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import 'work_editions.dart';
import 'hitomi_gallery.dart';

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
  /// Page count is evidence only when a provider actually supplies it.
  final int pageCount;

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
    this.pageCount = 0,
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
      pageCount: (data['page_count'] is num
          ? (data['page_count'] as num).toInt()
          : data['num_pages'] is num
              ? (data['num_pages'] as num).toInt()
              : data['files'] is List ? (data['files'] as List).length : 0)
          .clamp(0, 100000).toInt(),
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

  /// Plan a generous fallback field set; searchUnified executes the
  /// secondary queries only when the primary title round is sparse.
  /// Explicit field:value expressions bypass expansion.
  static List<(String, String)> planQueries(String raw) {
    final input = raw.trim();
    if (input.isEmpty) {
      throw const FormatException('검색어는 1~150자로 입력해줘.');
    }
    // An advanced filter is one atomic query, never a field expansion.
    if (RegExp(r'^[a-z][a-z_]*:', caseSensitive: false).hasMatch(input)) {
      if (input.length > 150) {
        throw const FormatException('검색어는 1~150자로 입력해줘.');
      }
      return [('advanced', input)];
    }
    // A library can provide several verified translations. The 150-character
    // cap belongs to EACH term, not the combined "name | name" string.
    final alternatives = <String>[];
    for (final part in input.split('|')) {
      final term = part.trim();
      if (term.isEmpty) continue;
      if (alternatives.isEmpty && term.length > 150) {
        throw const FormatException('검색어는 1~150자로 입력해줘.');
      }
      if (term.length <= 150 && !alternatives.any(
          (other) => other.toLowerCase() == term.toLowerCase())) {
        alternatives.add(term);
      }
      if (alternatives.length >= 5) break;
    }
    if (alternatives.isEmpty) {
      throw const FormatException('검색어는 1~150자로 입력해줘.');
    }
    final planned = <(String, String)>[];
    void add(String field, String term) {
      if (term.length <= 150 && !planned.any((other) =>
          other.$2.toLowerCase() == term.toLowerCase())) {
        planned.add((field, term));
      }
    }
    for (final term in alternatives) {
      add('general', term);
    }
    // An exact gallery number has no reason to spawn creator/tag queries.
    if (RegExp(r'^\d{6,9}$').hasMatch(alternatives.first) &&
        alternatives.length == 1) return planned;
    // Search title phrases first, then broaden only if results are sparse.
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

  /// Infer facets from actual returned metadata, not only which provider
  /// query found the gallery. A gallery returned for a general query may
  /// match its artist while having no keyword in the title.
  static Set<String> metadataFields(OnlineSearchWork work, String raw) {
    final terms = raw.split('|')
        .map((part) => part.trim().toLowerCase())
        .where((part) => part.isNotEmpty)
        .take(5)
        .map((part) => RegExp(r'^[a-z_]+:', caseSensitive: false)
                .hasMatch(part)
            ? part.substring(part.indexOf(':') + 1).trim() : part)
        .where((part) => part.length >= 2).toList();
    bool contains(Iterable<String> items) => terms.any((term) =>
        items.any((item) => item.toLowerCase().contains(term)));
    final fields = <String>{};
    if (contains([work.title, ...work.titleAliases, work.workId])) {
      fields.add('general');
    }
    if (contains(work.artists)) fields.add('artist');
    if (contains(work.groups)) fields.add('group');
    if (contains(work.series)) fields.add('series');
    if (contains(work.tags)) fields.add('tag');
    if (contains(work.tags.where((t) => t.toLowerCase().startsWith('female:')))) {
      fields.add('female');
    }
    if (contains(work.tags.where((t) => t.toLowerCase().startsWith('male:')))) {
      fields.add('male');
    }
    return fields;
  }

  /// Unique, already-fetched gallery IDs in each displayed facet.
  /// Provider "count" is an overlapping, unverified index estimate, not
  /// the number of works actually visible in a facet.
  static Map<String, int> facetCounts(Iterable<OnlineSearchWork> works,
      Map<String, List<String>> matchedFields) {
    final available = works.map((work) => work.workId).toSet();
    final byField = <String, Set<String>>{};
    for (final entry in matchedFields.entries) {
      if (!available.contains(entry.key)) continue;
      for (final field in entry.value.toSet()) {
        byField.putIfAbsent(field, () => <String>{}).add(entry.key);
      }
    }
    const order = ['general', 'artist', 'group', 'series', 'tag',
                   'female', 'male', 'advanced'];
    return {
      for (final field in order)
        if (byField.containsKey(field)) field: byField[field]!.length,
    };
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
    final exactId = raw.trim();
    if (page == 1 && RegExp(r'^\d{6,9}$').hasMatch(exactId)) {
      try {
        final info = await HitomiGalleryProvider(client).fetchInfo(exactId);
        final requested = WorkEditions.canonicalLanguage(language);
        final actual = WorkEditions.canonicalLanguage(info.language);
        final matchesLanguage = requested.isEmpty || actual.isEmpty ||
            requested == actual;
        final work = OnlineSearchWork(
          workId: info.workId, title: info.title,
          titleAliases: info.titleAliases,
          artists: info.author.split(',').map((e) => e.trim())
              .where((e) => e.isNotEmpty).toList(),
          groups: info.group.split(',').map((e) => e.trim())
              .where((e) => e.isNotEmpty).toList(),
          series: info.series.split(',').map((e) => e.trim())
              .where((e) => e.isNotEmpty).toList(),
          tags: info.tags, language: info.language, type: info.type,
          date: info.date, pageCount: info.pageCount,
        );
        final works = matchesLanguage ? [work] : <OnlineSearchWork>[];
        onProgress?.call(1, 1);
        final result = OnlineSearchResult(works, works.length, page,
            fieldTotals: {'general': works.length},
            matchedFields: {if (matchesLanguage) work.workId: ['general']});
        onPartial?.call(result);
        return result;
      } catch (_) {
        // Missing/unreachable metadata is not proof the gallery is absent.
        // Fall back to the community search with its normal error handling.
      }
    }
    final unique = <String, OnlineSearchWork>{};
    final matched = <String, Set<String>>{};
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
        pageCount: old.pageCount > 0 ? old.pageCount : next.pageCount,
      );
    }

    OnlineSearchResult snapshot() {
      final ordered = unique.values.toList();
      final displayMatches = <String, List<String>>{
        for (final work in ordered)
          work.workId: <String>{
            ...?matched[work.workId], ...metadataFields(work, raw),
          }.toList(),
      };
      int score(OnlineSearchWork work) {
        var result = (displayMatches[work.workId] ?? const <String>[])
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
          fieldTotals: facetCounts(ordered, displayMatches),
          matchedFields: displayMatches,
          warnings: warnings.toList(),
          hasNextPage: hasMore);
    }

    // Publish the title / translation round immediately, then expand fields
    // only for sparse searches. Each round keeps at most 3 in-flight queries.
    final primary = queries.where((q) =>
        q.$1 == 'general' || q.$1 == 'advanced').toList();
    final secondary = queries.where((q) =>
        q.$1 != 'general' && q.$1 != 'advanced').toList();
    var plannedTotal = primary.length;
    Future<void> runRound(List<(String, String)> entries) async {
      for (var i = 0; i < entries.length; i += 3) {
        await Future.wait(entries.skip(i).take(3).map((entry) async {
          try {
            final result = await search(entry.$2,
                page: page, language: language);
            successes++;
            for (final warning in result.warnings) {
              warnings.add(entry.$1 + ': ' + warning);
            }
            hasMore = hasMore || result.works.isNotEmpty &&
                (result.total > page * 25 || result.works.length >= 25);
            for (final work in result.works) {
              final old = unique[work.workId];
              unique[work.workId] = old == null ? work : combine(old, work);
              // General searches are broad and may match a creator but
              // not the title. Only explicit field-query evidence is tagged.
              if (entry.$1 != 'general') {
                matched.putIfAbsent(work.workId, () => <String>{})
                    .add(entry.$1);
              }
            }
          } catch (error) {
            warnings.add(entry.$1 + ': ' + error.toString());
          } finally {
            completed++;
            onProgress?.call(completed, plannedTotal);
            if (successes > 0) onPartial?.call(snapshot());
          }
        }));
      }
    }
    await runRound(primary);
    // Always finish previously selected fields on later pages. On page 1,
    // a sufficiently populated title search skips unrelated field traffic.
    if (secondary.isNotEmpty && (page > 1 || unique.length < 8)) {
      plannedTotal += secondary.length;
      await runRound(secondary);
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
    OnlineSearchResult? emptyResult;
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
        final result = OnlineSearchResult(entries, count, page,
            warnings: partial ? const [
              '전체 언어 서버에 연결할 수 없어 제한된 검색 서버를 이용했어. '
              '일부 언어의 결과가 누락될 수 있어.'
            ] : const []);
        // HTTP 200 with zero usable entries is not a definitive miss:
        // the second mirror may have another index or filter semantics.
        if (entries.isEmpty) {
          emptyResult ??= result;
          continue;
        }
        return result;
      } catch (error) {
        lastError = error;
      }
    }
    if (emptyResult != null) return emptyResult;
    throw StateError('온라인 검색 서버에 연결하지 못했어: ' +
        (lastError?.toString() ?? '사용할 수 있는 공급자가 없어.'));
  }
}
