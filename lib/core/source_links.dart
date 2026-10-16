import 'dart:convert';

import 'package:http/http.dart' as http;

import 'social_share_text.dart';

/// Parsing is entirely local and never requires an account or API key.
/// A recognized link does not imply that its comments can be read.
enum SourceKind {
  youtubeVideo, youtubePost, youtubeCollection,
  instagramPost, instagramReel, instagramStory, hitomiWork, external,
}

class SourceLink {
  final Uri uri;
  final SourceKind kind;
  final String videoId;
  final String workId;

  const SourceLink(this.uri, this.kind, {this.videoId = '', this.workId = ''});
  String get url => uri.toString();
  bool get canPreview => kind == SourceKind.instagramPost ||
      kind == SourceKind.instagramReel || kind == SourceKind.youtubePost;

  static SourceLink? parse(String raw) {
    final candidate = Uri.tryParse(raw.trim());
    if (candidate == null || candidate.host.isEmpty ||
        candidate.userInfo.isNotEmpty) return null;
    final host = candidate.host.toLowerCase();
    const trusted = <String>{
      'youtube.com', 'www.youtube.com', 'm.youtube.com',
      'music.youtube.com', 'youtu.be',
      'instagram.com', 'www.instagram.com', 'm.instagram.com',
      'hitomi.la', 'www.hitomi.la',
    };
    // Upgrade only explicitly approved public sites; never silently send an
    // unrelated HTTP link through a different origin or port.
    final httpAllowed = candidate.scheme == 'http' &&
        trusted.contains(host) && !candidate.hasPort;
    if (candidate.scheme != 'https' && !httpAllowed ||
        candidate.hasPort && candidate.port != 443) return null;
    final uri = httpAllowed ? candidate.replace(scheme: 'https') : candidate;
    if (<String>{'youtube.com', 'www.youtube.com', 'm.youtube.com',
          'music.youtube.com', 'youtu.be'}.contains(host)) {
      var id = '';
      final segments = uri.pathSegments;
      if (host == 'youtu.be') {
        id = segments.isNotEmpty ? segments.first : '';
      } else if (segments.length >= 2 &&
          <String>{'shorts', 'live', 'embed', 'v'}.contains(segments.first)) {
        id = segments[1];
      } else if (uri.path == '/watch') {
        id = uri.queryParameters['v'] ?? '';
      }
      if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id)) {
        return SourceLink(uri, SourceKind.youtubeVideo, videoId: id);
      }
      if (segments.isNotEmpty && segments.first == 'post' &&
          segments.length >= 2 && RegExp(r'^[a-zA-Z0-9_-]{5,120}$')
              .hasMatch(segments[1])) {
        return SourceLink(uri, SourceKind.youtubePost);
      }
      if (uri.path == '/playlist' ||
          segments.isNotEmpty &&
              <String>{'channel', 'c', 'user', '@'}.contains(segments.first) ||
          segments.isNotEmpty && segments.first.startsWith('@')) {
        return SourceLink(uri, SourceKind.youtubeCollection);
      }
      return SourceLink(uri, SourceKind.external);
    }
    if (<String>{'instagram.com', 'www.instagram.com',
          'm.instagram.com'}.contains(host)) {
      final segments = uri.pathSegments;
      if (segments.length >= 2 &&
          RegExp(r'^[a-zA-Z0-9_-]{4,80}$').hasMatch(segments[1])) {
        if (segments.first == 'p') {
          return SourceLink(uri, SourceKind.instagramPost);
        }
        if (segments.first == 'reel' || segments.first == 'tv') {
          return SourceLink(uri, SourceKind.instagramReel);
        }
        if (segments.first == 'stories') {
          return SourceLink(uri, SourceKind.instagramStory);
        }
      }
      return SourceLink(uri, SourceKind.external);
    }
    if (<String>{'hitomi.la', 'www.hitomi.la'}.contains(host)) {
      final match = RegExp(r'^/(?:reader|galleries)/(\d{6,12})(?:\.html)?/?$')
          .firstMatch(uri.path);
      if (match != null) {
        return SourceLink(uri, SourceKind.hitomiWork, workId: match.group(1)!);
      }
    }
    return SourceLink(uri, SourceKind.external);
  }

  static List<SourceLink> extract(String text, {int limit = 12}) {
    final found = <SourceLink>[];
    final seen = <String>{};
    final normalized = SocialShareText.normalize(text);
    final regex = RegExp(r'https?://[^\s<>"\x27]+', caseSensitive: false);
    for (final match in regex.allMatches(normalized)) {
      final trimmed = match.group(0)!.replaceFirst(
          RegExp(r'[)\].,!?;:。]+$'), '');
      final link = parse(trimmed);
      if (link != null && seen.add(link.url)) found.add(link);
      if (found.length >= limit) break;
    }
    return found;
  }
}

/// Whether a public post's full original body was available, or only its
/// social-preview excerpt could be read. Never report a preview as complete.
class PublicPreviewResult {
  final String text;
  final bool fullBody;
  const PublicPreviewResult(this.text, {required this.fullBody});
}

/// Public metadata preview for YouTube community and Instagram post/reel.
/// No cookie, login, API token, private posts or unrestricted URL fetching.
/// Network blocks return an actionable error; user can paste text instead.
class PublicSourcePreview {
  final http.Client client;
  const PublicSourcePreview(this.client);

  Future<String> fetch(SourceLink link) async =>
      (await fetchDetailed(link)).text;

  Future<PublicPreviewResult> fetchDetailed(SourceLink link) async {
    if (!link.canPreview ||
        !<String>{'www.youtube.com', 'youtube.com', 'm.youtube.com',
              'www.instagram.com', 'instagram.com', 'm.instagram.com'}
            .contains(link.uri.host.toLowerCase())) {
      throw const FormatException('공개 미리보기 지원 대상 링크가 아니야.');
    }
    final response = await client.get(link.uri, headers: const {
      'Accept': 'text/html',
      'User-Agent': 'Mozilla/5.0 (compatible; HYPViewer/0.4)',
    }).timeout(const Duration(seconds: 14));
    if (response.statusCode != 200 || response.bodyBytes.length > (link.kind == SourceKind.youtubePost
        ? 8 * 1024 * 1024 : 2 * 1024 * 1024)) {
      throw FormatException('공개 게시물 내용을 읽지 못했어 (HTTP ' +
          response.statusCode.toString() + '). 본문을 직접 붙여넣어줘.');
    }
    final html = utf8.decode(response.bodyBytes, allowMalformed: true);
    String? meta(String field) {
      // Only metadata is parsed; never execute scripts or scrape comments.
      for (final tag in RegExp(r'<meta\b[^>]*>', caseSensitive: false)
          .allMatches(html)) {
        final raw = tag.group(0)!;
        final attrs = <String,String>{};
        for (final attr in RegExp(
            r"""([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')""")
            .allMatches(raw)) {
          attrs[attr.group(1)!.toLowerCase()] =
              attr.group(2) ?? attr.group(3) ?? '';
        }
        if (attrs['property'] == field || attrs['name'] == field) {
          return attrs['content'];
        }
      }
      return null;
    }
    final title = meta('og:title') ?? meta('twitter:title') ?? '';
    final description = meta('og:description') ??
        meta('description') ?? meta('twitter:description') ?? '';
    String decode(String input) => SocialShareText.decode(input);
    if (link.kind == SourceKind.youtubePost) {
      final postId = link.uri.pathSegments.length > 1
          ? link.uri.pathSegments[1] : '';
      final body = _youtubePostBody(html, postId);
      if (body.isNotEmpty) {
        // Do not use an OG preview alongside the full post: duplicates can
        // introduce unrelated snippets or clipped gallery-number sequences.
        return PublicPreviewResult(body, fullBody: true);
      }
    }
    final text = [decode(title), decode(description)]
        .where((part) => part.trim().isNotEmpty).join('\n');
    if (text.isEmpty) {
      throw const FormatException('게시물의 공개 본문을 확인할 수 없어. '
          '비공개 또는 로그인 제한일 수 있으니 직접 복사해줘.');
    }
    return PublicPreviewResult(text, fullBody: false);
  }

  /// Read the target post from the serialized initial page data without
  /// executing scripts, loading credentials, or collecting unrelated posts.
  static String _youtubePostBody(String html, String postId) {
    if (postId.isEmpty) return '';
    final index = html.indexOf('ytInitialData');
    if (index < 0) return '';
    final start = html.indexOf('{', index);
    if (start < 0 || start - index > 160) return '';
    var level = 0;
    var quoted = false;
    var escaped = false;
    dynamic payload;
    for (var i = start; i < html.length && i < start + 6 * 1024 * 1024; i++) {
      final current = html[i];
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (current.codeUnitAt(0) == 92) {
          escaped = true;
        } else if (current == '"') {
          quoted = false;
        }
        continue;
      }
      if (current == '"') {
        quoted = true;
      } else if (current == '{') {
        level++;
      } else if (current == '}' && --level == 0) {
        try {
          payload = jsonDecode(html.substring(start, i + 1));
        } on FormatException {
          return '';
        }
        break;
      }
    }
    if (payload == null) return '';
    final found = <Map<String, dynamic>>[];
    void visit(dynamic node, int depth) {
      if (depth > 50 || found.length > 120) return;
      if (node is List) {
        for (final item in node) { visit(item, depth + 1); }
      } else if (node is Map<String, dynamic>) {
        for (final key in ['backstagePostRenderer', 'postRenderer']) {
          final data = node[key];
          if (data is Map<String, dynamic> && data['postId'] == postId) {
            found.add(data);
          }
        }
        for (final entry in node.values) { visit(entry, depth + 1); }
      }
    }
    visit(payload, 0);
    for (final post in found) {
      final text = _richText(post['contentText']);
      if (text.trim().isNotEmpty) return text;
    }
    return '';
  }

  static String _richText(dynamic node) {
    if (node is String) return node;
    if (node is! Map<String, dynamic>) return '';
    if (node['simpleText'] is String) return node['simpleText'] as String;
    final runs = node['runs'];
    if (runs is List) {
      return runs.map((run) => run is Map<String, dynamic>
          ? run['text'] is String ? run['text'] as String : ''
          : '').join();
    }
    return '';
  }
}
