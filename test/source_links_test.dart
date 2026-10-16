import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyp_viewer/core/source_links.dart';

void main() {
  test('HTML numeric entities in public Instagram metadata are decoded',
      () async {
    final client = MockClient((request) async => http.Response.bytes(
        utf8.encode('<html><meta property="og:title" '
            'content="&#xc624;&#xb298;&#xb3c4; &amp; &#064;artist" />'
            '<meta property="og:description" '
            'content="&#xc624;&#xb298;&#xb3c4; &amp; &#064;artist" /></html>'),
        200));
    final result = await PublicSourcePreview(client).fetchDetailed(
        SourceLink.parse('https://www.instagram.com/p/DeLL6F5n1LS/')!);
    expect(result.text, '오늘도 & @artist');
    expect(result.fullBody, false);
    client.close();
  });

  test('HTML escaped Instagram URL keeps all query parameters', () {
    final links = SourceLink.extract(
      'https://www.instagram.com/p/DeLL6F5n1LS/?img_index=2&amp;srtk=abc');
    expect(links.single.kind, SourceKind.instagramPost);
    expect(links.single.uri.queryParameters['img_index'], '2');
    expect(links.single.uri.queryParameters['srtk'], 'abc');
  });

  test('video, post, reel and direct gallery links all parse', () {
    final cases = <String, SourceKind>{
      'https://www.youtube.com/shorts/abcD123xyZ0': SourceKind.youtubeVideo,
      'https://youtu.be/abcD123xyZ0?t=42': SourceKind.youtubeVideo,
      'https://www.youtube.com/watch?v=abcD123xyZ0': SourceKind.youtubeVideo,
      'https://www.youtube.com/live/abcD123xyZ0': SourceKind.youtubeVideo,
      'https://www.youtube.com/post/Ugkx1234567890': SourceKind.youtubePost,
      'https://www.youtube.com/playlist?list=PL123': SourceKind.youtubeCollection,
      'https://www.instagram.com/p/ABC12345/': SourceKind.instagramPost,
      'https://www.instagram.com/reel/ABC12345/': SourceKind.instagramReel,
      'https://www.instagram.com/stories/someone/123456789/': SourceKind.instagramStory,
      'https://hitomi.la/reader/3172801.html': SourceKind.hitomiWork,
      'https://example.org/story': SourceKind.external,
    };
    for (final entry in cases.entries) {
      expect(SourceLink.parse(entry.key)?.kind, entry.value, reason: entry.key);
    }
  });
  test('multiple links and share text retain original links', () {
    final links = SourceLink.extract(
      '공유: https://youtu.be/abcD123xyZ0?t=2.\n'
      'https://www.instagram.com/reel/ABC12345/)\n'
      'https://hitomi.la/galleries/3172801.html');
    expect(links.length, 3);
    expect(links.first.videoId, 'abcD123xyZ0');
    expect(links.last.workId, '3172801');
  });
  test('trusted HTTP is normalized, untrusted HTTP and userinfo blocked', () {
    expect(SourceLink.parse('http://www.instagram.com/reel/ABC12345')?.url,
        'https://www.instagram.com/reel/ABC12345');
    expect(SourceLink.parse('http://example.org/story'), isNull);
    expect(SourceLink.parse('http://youtube.com.evil.test/post/Ugkx1234567890'), isNull);
    expect(SourceLink.parse('https://user:pwd@www.youtube.com/watch?v=abcD123xyZ0'), isNull);
    expect(SourceLink.parse('https://youtube.com.evil.test/watch?v=abcD123xyZ0')?.kind, SourceKind.external);
  });
  test('Android HTTP YouTube post share survives HTTPS normalization', () {
    final links = SourceLink.extract(
      'http://youtube.com/post/Ugkxlt1Ces0kwMJyLR-sN8iBws3CSAVjbgmv?si=Cs94o7HHsCaLJ45p');
    expect(links.length, 1);
    expect(links.single.kind, SourceKind.youtubePost);
    expect(links.single.url,
      'https://youtube.com/post/Ugkxlt1Ces0kwMJyLR-sN8iBws3CSAVjbgmv?si=Cs94o7HHsCaLJ45p');
  });

  test('full community post body is used instead of truncated og preview', () async {
    final client = MockClient((request) async {
      final html = '<html><meta property="og:description" content="번호 123">'
          '<script>var ytInitialData = ' + jsonEncode({'contents': {
        'itemSectionRenderer': {'contents': [
          {'backstagePostRenderer': {
            'postId': 'Ugkxlt1Ces0kwMJyLR-sN8iBws3CSAVjbgmv',
            'contentText': {'runs': [
              {'text': '긴 본문 첫 줄\n'},
              {'text': '두 번째 줄 작품 번호 3172801\n'},
              {'text': '마지막 줄 번호 3999999'}
            ]}
          }}
        ]}
      }}) + ';</script></html>';
      return http.Response.bytes(utf8.encode(html), 200);
    });
    final r = await PublicSourcePreview(client).fetchDetailed(
      SourceLink.parse(
        'https://youtube.com/post/Ugkxlt1Ces0kwMJyLR-sN8iBws3CSAVjbgmv')!);
    expect(r.fullBody, true);
    expect(r.text, contains('3999999'));
    expect(r.text, contains('첫 줄\n두 번째'));
    expect(r.text, isNot(contains('번호 123')));
    client.close();
  });

  test('Instagram metadata never claims complete captions or comments',
      () async {
    final client = MockClient((request) async => http.Response.bytes(
      utf8.encode('<html><meta property="og:title" content="Public work" />'
          '<meta property="og:description" content="Work 3172801"></html>'),
      200,
    ));
    final result = await PublicSourcePreview(client).fetchDetailed(
      SourceLink.parse('https://www.instagram.com/reel/ABC12345/')!);
    expect(result.text, contains('3172801'));
    expect(result.fullBody, false);
    client.close();
  });

  test('public metadata preview reads descriptions without a developer key', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'www.instagram.com');
      // Response(String) defaults to Latin-1; real HTML bodies are UTF-8.
      return http.Response.bytes(
          utf8.encode('<html><meta property="og:description" content="번호 3172801 &amp; extras"></html>'),
          200);
    });
    final text = await PublicSourcePreview(client).fetch(
        SourceLink.parse('https://www.instagram.com/p/ABC12345/')!);
    expect(text, contains('3172801 & extras'));
    client.close();
  });
}
