import 'dart:convert';

import 'package:http/http.dart' as http;

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
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.port != 443 && uri.hasPort) return null;
    final host = uri.host.toLowerCase();
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
    final regex = RegExp(r'https://[^\s<>"\x27]+', caseSensitive: false);
    for (final match in regex.allMatches(text)) {
      final trimmed = match.group(0)!.replaceFirst(
          RegExp(r'[)\].,!?;:。]+$'), '');
      final link = parse(trimmed);
      if (link != null && seen.add(link.url)) found.add(link);
      if (found.length >= limit) break;
    }
    return found;
  }
}

/// Public metadata preview for YouTube community and Instagram post/reel.
/// No cookie, login, API token, private posts or unrestricted URL fetching.
/// Network blocks return an actionable error; user can paste text instead.
class PublicSourcePreview {
  final http.Client client;
  const PublicSourcePreview(this.client);

  Future<String> fetch(SourceLink link) async {
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
    if (response.statusCode != 200 || response.bodyBytes.length > 2 * 1024 * 1024) {
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
    String decode(String input) => input
        .replaceAll('&amp;', '&').replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'").replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
    final text = [decode(title), decode(description)]
        .where((part) => part.trim().isNotEmpty).join('\n');
    if (text.isEmpty) {
      throw const FormatException('게시물의 공개 본문을 확인할 수 없어. '
          '비공개 또는 로그인 제한일 수 있으니 직접 복사해줘.');
    }
    return text;
  }
}
