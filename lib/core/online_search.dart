import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Public metadata mirror, not an official Hitomi API. Provider outages
/// affect online search only; local library search must remain independent.
class OnlineSearchWork {
  final String workId;
  final String title;
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
    final id = data['id'];
    final code = id is int ? id.toString() :
        id is String ? id : '';
    if (!RegExp(r'^\d{1,12}$').hasMatch(code)) {
      throw const FormatException('작품 번호가 올바르지 않아.');
    }
    return OnlineSearchWork(
      workId: code,
      title: string('title').isEmpty ? '작품 ' + code : string('title'),
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
    final advanced = RegExp(r'^[a-z][a-z_]*:', caseSensitive: false)
        .hasMatch(input);
    if (advanced) return [('advanced', input)];
    final alternatives = input.split('|')
        .map((part) => part.trim()).where((part) => part.isNotEmpty)
        .take(3).toList();
    final planned = <(String, String)>[];
    void add(String field, String value) {
      if (value.isNotEmpty && value.length <= 150 &&
          !planned.any((existing) => existing.$2 == value)) {
        planned.add((field, value));
      }
    }
    for (final term in alternatives) {
      add('general', term);
    }
    // These field operators match the upstream Hitomi query syntax.
    // Providers may still reject individual operators: failure is isolated.
    final base = alternatives.first;
    if (base.length > 1) {
      for (final field in ['artist', 'group', 'series', 'tag',
                           'female', 'male']) {
        add(field, '$field:$base');
      }
    }
    return planned;
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
  }) async {
    final queries = planQueries(raw);
    final unique = <String, OnlineSearchWork>{};
    final matched = <String, Set<String>>{};
    final counts = <String, int>{};
    final warnings = <String>[];
    var successes = 0;
    var hasMore = false;
    // Keep concurrent requests bounded so a partially down mirror never
    // floods either server when the user types a short common word.
    for (var i = 0; i < queries.length; i += 3) {
      final batch = queries.skip(i).take(3);
      await Future.wait(batch.map((entry) async {
        try {
          final r = await search(entry.$2, page: page, language: language);
          successes++;
          for (final warning in r.warnings) {
            warnings.add(entry.$1 + ': ' + warning);
          }
          counts.update(entry.$1, (n) => n + r.total,
              ifAbsent: () => r.total);
          hasMore = hasMore || r.works.isNotEmpty &&
              (r.total > page * 25 || r.works.length >= 25);
          for (final work in r.works) {
            unique.putIfAbsent(work.workId, () => work);
            matched.putIfAbsent(work.workId, () => <String>{})
                .add(entry.$1);
          }
        } catch (e) {
          warnings.add(entry.$1 + ': ' + e.toString());
        }
      }));
    }
    if (successes == 0) {
      throw StateError('모든 검색 서버 요청이 실패했어: ' +
          warnings.take(2).join(' / '));
    }
    return OnlineSearchResult(unique.values.toList(), unique.length, page,
        fieldTotals: counts,
        matchedFields: matched.map((id, fields) =>
            MapEntry(id, fields.toList())),
        warnings: warnings, hasNextPage: hasMore);
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
