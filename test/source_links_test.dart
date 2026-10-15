import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyp_viewer/core/source_links.dart';

void main() {
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
  test('rejects unexpected hosts, HTTP and userinfo for automatic fetch', () {
    expect(SourceLink.parse('http://www.instagram.com/reel/ABC12345'), isNull);
    expect(SourceLink.parse('https://user:pwd@www.youtube.com/watch?v=abcD123xyZ0'), isNull);
    expect(SourceLink.parse('https://youtube.com.evil.test/watch?v=abcD123xyZ0')?.kind, SourceKind.external);
  });
  test('public metadata preview reads descriptions without a developer key', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'www.instagram.com');
      return http.Response(
          '<html><meta property="og:description" content="번호 3172801 &amp; extras"></html>',
          200);
    });
    final text = await PublicSourcePreview(client).fetch(
        SourceLink.parse('https://www.instagram.com/p/ABC12345/')!);
    expect(text, contains('3172801 & extras'));
    client.close();
  });
}
