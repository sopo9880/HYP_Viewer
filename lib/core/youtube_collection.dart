import 'dart:convert';

import 'package:http/http.dart' as http;

import 'source_links.dart';

class YoutubeCollectionItem {
  final String videoId;
  final String title;
  const YoutubeCollectionItem(this.videoId, this.title);
  String get url => 'https://www.youtube.com/watch?v=' + videoId;
}

/// Bounded public continuation cursors. Never persist page tokens or keys.
class YoutubeCollectionPage {
  final List<YoutubeCollectionItem> videos;
  final String? continuation;
  final String? publicWebKey;
  final Map<String, dynamic>? webContext;

  const YoutubeCollectionPage(this.videos, {
    this.continuation, this.publicWebKey, this.webContext,
  });

  bool get hasMore => continuation != null &&
      publicWebKey != null && webContext != null;
}

/// Best-effort PUBLIC playlist/channel video selector. No login, private
/// endpoint, arbitrary URL fetching or automatic background traversal.
class YoutubeCollectionReader {
  final http.Client client;
  const YoutubeCollectionReader(this.client);

  Future<List<YoutubeCollectionItem>> list(SourceLink link) async =>
      (await listFirst(link)).videos;

  Future<YoutubeCollectionPage> listFirst(SourceLink link) async {
    if (link.kind != SourceKind.youtubeCollection ||
        !const {'youtube.com', 'www.youtube.com', 'm.youtube.com'}
            .contains(link.uri.host.toLowerCase())) {
      throw const FormatException('지원되지 않는 YouTube 목록 링크야.');
    }
    final response = await client.get(link.uri, headers: const {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 Chrome/124.0.0.0 Safari/537.36',
      'Accept': 'text/html',
    }).timeout(const Duration(seconds: 16));
    if (response.statusCode != 200 ||
        response.bodyBytes.length > 8 * 1024 * 1024) {
      throw FormatException('YouTube 목록을 불러오지 못했어 (HTTP ' +
          response.statusCode.toString() + ').');
    }
    final html = utf8.decode(response.bodyBytes, allowMalformed: true);
    final first = extractFromHtml(html, playlist: link.uri.path == '/playlist');
    final token = _continuation(html);
    final key = RegExp(r'"INNERTUBE_API_KEY"\s*:\s*"([^"]+)"')
        .firstMatch(html)?.group(1);
    final context = _webContext(html);
    return YoutubeCollectionPage(first,
      continuation: token, publicWebKey: key, webContext: context);
  }

  Future<YoutubeCollectionPage> listNext(YoutubeCollectionPage previous,
      {bool playlist = false}) async {
    if (!previous.hasMore) {
      throw const StateError('공개 목록의 다음 페이지 정보가 없어.');
    }
    final token = previous.continuation!;
    if (token.length > 4096 || token.isEmpty) {
      throw const FormatException('목록 페이지 토큰이 올바르지 않아.');
    }
    final response = await client.post(
      Uri.https('www.youtube.com', '/youtubei/v1/browse',
          {'key': previous.publicWebKey!}),
      headers: const {
        'Content-Type': 'application/json',
        'Origin': 'https://www.youtube.com',
        'Referer': 'https://www.youtube.com/',
      },
      body: jsonEncode({
        'context': previous.webContext,
        'continuation': token,
      }),
    ).timeout(const Duration(seconds: 16));
    if (response.statusCode != 200 ||
        response.bodyBytes.length > 5 * 1024 * 1024) {
      throw FormatException('공개 YouTube 추가 목록 조회 실패 (HTTP ' +
          response.statusCode.toString() + ').');
    }
    final payload = jsonDecode(utf8.decode(response.bodyBytes));
    if (payload is! Map<String, dynamic>) {
      throw const FormatException('추가 영상 목록 형식이 올바르지 않아.');
    }
    final serial = jsonEncode(payload);
    final items = extractFromHtml('ytInitialData=' + serial,
        playlist: playlist);
    final nextToken = _continuation(serial);
    if (nextToken == token) {
      return YoutubeCollectionPage(items);
    }
    return YoutubeCollectionPage(items,
      continuation: nextToken,
      publicWebKey: previous.publicWebKey,
      webContext: previous.webContext);
  }

  static String? _continuation(String html) {
    final match = RegExp(
      r'"continuationCommand"\s*:\s*\{[^{}]*"token"\s*:\s*"([^"]+)"',
      dotAll: true).allMatches(html).lastOrNull;
    if (match == null) return null;
    final token = match.group(1);
    return token == null || token.isEmpty || token.length > 4096
        ? null : token;
  }

  static Map<String, dynamic>? _webContext(String html) {
    final label = RegExp(r'"INNERTUBE_CONTEXT"\s*:\s*\{')
        .firstMatch(html);
    if (label == null) return null;
    final start = html.indexOf('{', label.start);
    var depth = 0, quoted = false, escaped = false;
    for (var i = start; i < html.length && i < start + 50000; i++) {
      final ch = html[i];
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (ch.codeUnitAt(0) == 92) {
          escaped = true;
        } else if (ch == '"') {
          quoted = false;
        }
      } else if (ch == '"') {
        quoted = true;
      } else if (ch == '{') {
        depth++;
      } else if (ch == '}' && --depth == 0) {
        try {
          final decoded = jsonDecode(html.substring(start, i + 1));
          return decoded is Map<String, dynamic> ? decoded : null;
        } on FormatException {
          return null;
        }
      }
    }
    return null;
  }

  static List<YoutubeCollectionItem> extractFromHtml(String html,
      {bool playlist = false}) {
    final initial = html.indexOf('ytInitialData');
    if (initial < 0) return const [];
    final start = html.indexOf('{', initial);
    if (start < 0 || start - initial > 160) return const [];
    dynamic decoded;
    var depth = 0, inString = false, escaped = false;
    for (var i = start; i < html.length && i < start + 6 * 1024 * 1024; i++) {
      final ch = html[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch.codeUnitAt(0) == 92) {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
      } else if (ch == '{') {
        depth++;
      } else if (ch == '}' && --depth == 0) {
        try {
          decoded = jsonDecode(html.substring(start, i + 1));
        } on FormatException {
          return const [];
        }
        break;
      }
    }
    if (decoded == null) return const [];
    final results = <YoutubeCollectionItem>[];
    final seen = <String>{};
    void scan(dynamic node, int level) {
      if (level > 60 || results.length >= 50) return;
      if (node is List) {
        for (final value in node) { scan(value, level + 1); }
      } else if (node is Map<String, dynamic>) {
        for (final kind in ['playlistVideoRenderer',
                            'videoRenderer', 'gridVideoRenderer']) {
          if (playlist && kind != 'playlistVideoRenderer') continue;
          final video = node[kind];
          if (video is! Map<String, dynamic>) continue;
          final id = video['videoId'];
          if (id is! String ||
              !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id) ||
              !seen.add(id)) continue;
          final title = video['title'];
          String display = '';
          if (title is Map<String, dynamic>) {
            display = title['simpleText'] is String
                ? title['simpleText'] as String : '';
            final runs = title['runs'];
            if (display.isEmpty && runs is List) {
              display = runs.whereType<Map>().map((run) =>
                  run['text'] is String ? run['text'] as String : '').join();
            }
          }
          results.add(YoutubeCollectionItem(id,
              display.isEmpty ? id : display));
        }
        for (final value in node.values) { scan(value, level + 1); }
      }
    }
    scan(decoded, 0);
    return results;
  }
}
