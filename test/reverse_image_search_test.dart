import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyp_viewer/core/reverse_image_search.dart';

void main() {
  test('external URL evidence does not turn Pixiv ID into gallery number', () {
    final body = jsonEncode({'header': {'status': 0}, 'results': [
      {'header': {'similarity': '92.4',
        'thumbnail': 'https://saucenao.com/thumb/1.jpg'},
       'data': {'title': 'Example title', 'member_name': 'Example artist',
        'ext_urls': ['https://www.pixiv.net/artworks/3172801']}},
      {'header': {'similarity': '81.2'},
       'data': {'title': 'Numbered gallery', 'ext_urls': [
         'https://hitomi.la/galleries/3172801.html']}},
      {'header': {'similarity': '99'}, 'data': {
        'ext_urls': ['https://127.0.0.1/secret']}},
    ]});
    final matches = ReverseImageSearch.parseSauceNao(body);
    expect(matches, hasLength(2));
    expect(matches.first.title, 'Example title');
    expect(matches.first.author, 'Example artist');
    expect(matches.first.similarity, 92.4);
    expect(matches.first.workId, isEmpty);
    expect(matches[1].workId, '3172801');
    expect(ReverseImageSearch.galleryNumber(
        'https://hitomi.la.evil.test/galleries/3172801.html'), isEmpty);
  });

  test('ascii2d parser deduplicates and shows origin without false score', () {
    const html = '''
    <div class="item-box"><div class="image-box">
      <img src="/thumb/example.png"></div><div class="detail-box">
      <h6><a href="https://www.pixiv.net/artworks/84035784">Example art</a></h6>
      <small>Example creator</small>
    </div></div>
    <div class="item-box"><div class="detail-box">
      <h6><a href="https://www.pixiv.net/artworks/84035784">Duplicate</a></h6>
    </div></div>
    ''';
    final hits = ReverseImageSearch.parseAscii2d(html);
    expect(hits, hasLength(1));
    expect(hits.single.title, 'Example art');
    expect(hits.single.similarity, isNull);
    expect(hits.single.workId, isEmpty);
    expect(hits.single.thumbnailUrl, 'https://ascii2d.net/thumb/example.png');
  });

  test('keyless provider follows only bounded HTTPS search redirects', () async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/') {
        return http.Response('''<form action="/search/file">
          <input name="authenticity_token" value="safe-token" /></form>''',
          200, headers: {'set-cookie': '_ascii2d_session=abc; Path=/'});
      }
      if (request.method == 'POST') {
        expect(request.url.path, '/search/file');
        expect(request.headers['Cookie'], contains('_ascii2d_session'));
        return http.Response('', 302, headers: {
          'location': '/search/color/example',
        });
      }
      expect(request.url.path, '/search/color/example');
      return http.Response('''<div class="item-box">
        <div class="detail-box"><h6>
          <a href="https://www.pixiv.net/artworks/84035784">Source</a>
        </h6></div></div>''', 200);
    });
    final result = await ReverseImageSearch(client)
        .search(Uint8List.fromList([0xff, 0xd8, 0xff]));
    expect(result.hits, hasLength(1));
    expect(result.warnings, isEmpty);
    client.close();
  });

  test('rate limits and missing results never fabricate matches', () {
    expect(() => ReverseImageSearch.parseSauceNao(
        jsonEncode({'header': {'status': -6}, 'results': []})),
        throwsFormatException);
    expect(ReverseImageSearch.safePublicUrl('https://localhost/test'), false);
    expect(ReverseImageSearch.safePublicUrl('http://external.test/img'), false);
  });
}
