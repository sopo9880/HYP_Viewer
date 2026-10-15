import 'dart:convert';

import 'package:http/http.dart' as http;

import 'source_links.dart';

class YoutubeCollectionItem {
  final String videoId;
  final String title;
  const YoutubeCollectionItem(this.videoId, this.title);
  String get url => 'https://www.youtube.com/watch?v=' + videoId;
}

/// Best-effort PUBLIC playlist/channel video selector. No login, private
/// endpoint, arbitrary URL fetching or automatic background traversal.
class YoutubeCollectionReader {
  final http.Client client;
  const YoutubeCollectionReader(this.client);

  Future<List<YoutubeCollectionItem>> list(SourceLink link) async {
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
    return extractFromHtml(
        utf8.decode(response.bodyBytes, allowMalformed: true),
        playlist: link.uri.path == '/playlist');
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
