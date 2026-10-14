import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyp_viewer/core/hitomi_gallery.dart';

void main() {
  const id = '2711759';
  final hash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaabc';
  // Last three hex digits are "abc" => swapped hex "cab".
  const expectedGroup = 0xcab;

  test('gallery metadata and gg.js resolve in-app WebP pages', () async {
    final requested = <String>[];
    final client = MockClient((request) async {
      requested.add(request.url.toString());
      if (request.url.path == '/galleries/2711759.js') {
        return http.Response(
          'var galleryinfo = ' + jsonEncode({
            'id': 2711759,
            'title': 'Test gallery',
            'files': [
              {'hash': hash, 'name': 'first.jpg', 'haswebp': 1},
              {'hash': hash, 'name': 'second.jpg', 'haswebp': 0},
            ],
          }) + ';',
          200, headers: {'content-type': 'application/javascript'},
        );
      }
      if (request.url.path == '/gg.js') {
        return http.Response('var o = 0; case $expectedGroup: o = 2; break; '
            "var x = {b: '2026/'};", 200);
      }
      expect(request.headers['referer'], 'https://hitomi.la/');
      return http.Response.bytes([1, 2, 3, 4], 200,
          headers: {'content-type': 'image/webp'});
    });

    final gallery = await HitomiGalleryProvider(client).load(id);
    expect(gallery.title, 'Test gallery');
    expect(gallery.pageCount, 2);
    expect(gallery.pageUrls[0].host, 'w3.gold-usergeneratedcontent.net');
    expect(gallery.pageUrls[0].path,
        '/2026/$expectedGroup/$hash.webp');
    expect(gallery.pageUrls[1].host, '3.gold-usergeneratedcontent.net');
    expect(gallery.pageUrls[1].path,
        '/2026/$expectedGroup/$hash.jpg');
    expect(await gallery.loadPage(0), [1, 2, 3, 4]);
    expect(requested.length, 3);
    client.close();
  });

  test('falls back to a supported original image when WebP fails', () async {
    final attempts = <Uri>[];
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/galleries/2711759.js')) {
        return http.Response('var galleryinfo = ' + jsonEncode({
          'id': 2711759, 'title': 'Fallback test',
          'files': [{'hash': hash, 'name': 'page.jpg', 'haswebp': 1}],
        }) + ';', 200);
      }
      if (request.url.path == '/gg.js') {
        return http.Response('var o = 0; case $expectedGroup: o = 2; break; '
            "var x = {b: '2026/'};", 200);
      }
      attempts.add(request.url);
      expect(request.headers['referer'], 'https://hitomi.la/');
      if (request.url.path.endsWith('.webp')) {
        return http.Response('Not Found', 404);
      }
      return http.Response.bytes([0xff, 0xd8, 0xff, 0xd9], 200,
          headers: {'content-type': 'image/jpeg'});
    });
    final gallery = await HitomiGalleryProvider(client).load(id);
    expect(gallery.pageUrls.single.host, 'w3.gold-usergeneratedcontent.net');
    expect(gallery.pageUrls.single.path, '/2026/$expectedGroup/$hash.webp');
    expect(gallery.fallbackPageUrls?.single?.host,
        '3.gold-usergeneratedcontent.net');
    expect(await gallery.loadPage(0), [0xff, 0xd8, 0xff, 0xd9]);
    expect(attempts.map((u) => u.path).toList(), [
      '/2026/$expectedGroup/$hash.webp',
      '/2026/$expectedGroup/$hash.jpg',
    ]);
    client.close();
  });

  test('refuses arbitrary image hosts and invalid work IDs', () async {
    final client = MockClient((request) async =>
        http.Response('not needed', 500));
    expect(
      () => HitomiGalleryProvider(client).load('../private'),
      throwsFormatException,
    );
    final bad = HitomiGallery(
      workId: '123', title: 'Invalid',
      pageUrls: [Uri.parse('https://other.example.org/image.webp')],
      client: client,
    );
    expect(() => bad.loadPage(0), throwsFormatException);
    client.close();
  });

  test('invalid image hashes are rejected before download', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/gg.js')) {
        return http.Response("var o = 0; var x={b: '2026/'};", 200);
      }
      return http.Response(
        'var galleryinfo = ' + jsonEncode({
          'id': 2711759,
          'title': 'Bad data',
          'files': [{'hash': '../traversal', 'name': 'test.jpg', 'haswebp': 1}],
        }) + ';', 200,
      );
    });
    expect(() => HitomiGalleryProvider(client).load(id),
        throwsFormatException);
    client.close();
  });
}
