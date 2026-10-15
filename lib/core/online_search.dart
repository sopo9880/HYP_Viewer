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
  const OnlineSearchResult(this.works, this.total, this.page);
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
    queries.add(term.split('|').first.trim());
    if (language.isNotEmpty) queries.add('language:' + language);
    return queries;
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
    for (final provider in providers) {
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
        return OnlineSearchResult(entries, count, page);
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError('온라인 검색 서버에 연결하지 못했어: ' +
        (lastError?.toString() ?? '사용할 수 있는 공급자가 없어.'));
  }
}
