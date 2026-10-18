import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyp_viewer/core/hitomi_gallery.dart';
import 'package:hyp_viewer/core/online_reader_failure.dart';

void main() {
  const id = '2711759';
  final hash = List.filled(61, 'a').join() + 'abc';
  final otherHash = List.filled(61, 'b').join() + 'def';
  const selectedGroup = 0xcab;
  const defaultGroup = 0xfde;

  String metadata(List<Map<String, dynamic>> files) {
    return 'var galleryinfo = ' + jsonEncode({
      'id': 2711759,
      'title': 'Test gallery',
      'files': files,
    }) + ';';
  }

  test('current gg.js chooses WebP w1/w2, never numeric JPG hosts', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      if (request.url.path == '/galleries/2711759.js') {
        return http.Response(metadata([
          {'hash': hash, 'name': 'first.jpg', 'haswebp': 1},
          {'hash': otherHash, 'name': 'second.jpg', 'haswebp': 0},
        ]), 200);
      }
      if (request.url.path == '/gg.js') {
        return http.Response(
          "var o = 0; case $selectedGroup: o = 1; break; "
          "var x = {b: '2026/'};", 200);
      }
      expect(request.headers['referer'], 'https://hitomi.la/');
      return http.Response.bytes([1, 2, 3, 4], 200,
          headers: {'content-type': 'image/webp'});
    });
    final gallery = await HitomiGalleryProvider(client).load(id);
    expect(gallery.title, 'Test gallery');
    expect(gallery.pageCount, 2);
    expect(gallery.pageUrls[0].host, 'w2.gold-usergeneratedcontent.net');
    expect(gallery.pageUrls[0].path, '/2026/$selectedGroup/$hash.webp');
    expect(gallery.pageUrls[1].host, 'w1.gold-usergeneratedcontent.net');
    expect(gallery.pageUrls[1].path, '/2026/$defaultGroup/$otherHash.webp');
    expect(gallery.pageUrls.every((u) => u.path.endsWith('.webp')), isTrue);
    expect(await gallery.loadPage(0), [1, 2, 3, 4]);
    expect(await gallery.loadPage(1), [1, 2, 3, 4]);
    expect(requests.length, 4);
    client.close();
  });

  test('legacy JPEG host is not attempted if WebP image request fails', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      if (request.url.path == '/galleries/2711759.js') {
        return http.Response(metadata([
          {'hash': hash, 'name': 'first.jpg', 'haswebp': 0},
        ]), 200);
      }
      if (request.url.path == '/gg.js') {
        return http.Response("var o = 0; case $selectedGroup: o = 1; break;"
            " var x = {b: '2026/'};", 200);
      }
      requests.add(request.url);
      return http.Response('Not found', 404);
    });
    final gallery = await HitomiGalleryProvider(client).load(id);
    await expectLater(gallery.loadPage(0), throwsFormatException);
    expect(requests, hasLength(1));
    expect(requests.single.host, 'w2.gold-usergeneratedcontent.net');
    client.close();
  });

  test('DNS errors identify the exact active WebP host', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/galleries/2711759.js') {
        return http.Response(metadata([
          {'hash': hash, 'name': 'first.jpg', 'haswebp': 1},
        ]), 200);
      }
      if (request.url.path == '/gg.js') {
        return http.Response("var o = 0; case $selectedGroup: o = 1; break;"
            " var x = {b: '2026/'};", 200);
      }
      throw http.ClientException(
        "SocketException: Failed host lookup: 'w2.gold-usergeneratedcontent.net'",
        request.url,
      );
    });
    final gallery = await HitomiGalleryProvider(client).load(id);
    await expectLater(
      gallery.loadPage(0),
      throwsA(isA<OnlineReaderFailure>()
          .having((e) => e.code, 'code', 'IMAGE_DNS_FAILURE')
          .having((e) => e.stage, 'stage', OnlineReaderStage.image)
          .having((e) => e.host, 'diagnostic host',
              'w2.gold-usergeneratedcontent.net')
          .having((e) => e.message, 'safe message',
              contains('DNS 조회 실패'))),
    );
    client.close();
  });

  test('does not allow hosts outside current image server names', () async {
    final client = MockClient((request) async => http.Response('No', 500));
    final bad = HitomiGallery(
      workId: '123', title: 'Invalid',
      pageUrls: [Uri.parse('https://2.gold-usergeneratedcontent.net/1/a.jpg')],
      client: client,
    );
    await expectLater(bad.loadPage(0), throwsFormatException);
    final unknown = HitomiGallery(
      workId: '123', title: 'Invalid',
      pageUrls: [Uri.parse('https://host.other.example.org/1/a.webp')],
      client: client,
    );
    await expectLater(unknown.loadPage(0), throwsFormatException);
    await expectLater(
      HitomiGalleryProvider(client).load('../private'),
      throwsFormatException,
    );
    client.close();
  });

  test('out-of-range routing and image hashes fail rather than invent hosts', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/gg.js') {
        return http.Response("var o = 2; var x={b: '2026/'};", 200);
      }
      return http.Response(metadata([
        {'hash': hash, 'name': 'page.jpg'},
      ]), 200);
    });
    await expectLater(HitomiGalleryProvider(client).load(id), throwsFormatException);
    client.close();

    final clientWithBadHash = MockClient((request) async {
      if (request.url.path == '/gg.js') {
        return http.Response("var o = 0; var x={b: '2026/'};", 200);
      }
      return http.Response(metadata([
        {'hash': '../traversal', 'name': 'page.jpg'},
      ]), 200);
    });
    await expectLater(HitomiGalleryProvider(clientWithBadHash).load(id), throwsFormatException);
    clientWithBadHash.close();
  });
  test('data saver uses small WebP thumbnail and falls back when missing', () async {
    final requests = <Uri>[];
    var thumbnailStatus = 200;
    final client = MockClient((request) async {
      if (request.url.path == '/galleries/2711759.js') {
        return http.Response(metadata([
          {'hash': hash, 'name': 'first.jpg', 'haswebp': 1},
        ]), 200);
      }
      if (request.url.path == '/gg.js') {
        return http.Response("var o = 0; var x={b: '2026/'};", 200);
      }
      requests.add(request.url);
      if (request.url.host.endsWith('tn.gold-usergeneratedcontent.net')) {
        return http.Response.bytes([9, 8, 7], thumbnailStatus,
            headers: {'content-type': 'image/webp'});
      }
      return http.Response.bytes([1, 2, 3], 200,
          headers: {'content-type': 'image/webp'});
    });
    final gallery = await HitomiGalleryProvider(client)
        .load(id, dataSaver: true);
    expect(gallery.thumbnailUrls.single.host,
        matches(RegExp(r'^[ab]tn\.gold-usergeneratedcontent\.net$')));
    expect(await gallery.loadPage(0), [9, 8, 7]);
    expect(requests.single.path, contains('/webpsmalltn/'));
    requests.clear();
    thumbnailStatus = 404;
    expect(await gallery.loadPage(0), [1, 2, 3]);
    expect(requests.map((url) => url.host).toList(), hasLength(2));
    expect(requests.last.host, startsWith('w'));
    client.close();
  });
  test('metadata failures identify the exact field and safe response type',
      () async {
    final samples = <Map<String, Object?>>[
      {'id': 2711759},
      {'id': 2711759, 'files': 'unexpected'},
      {'id': 2711759, 'files': []},
      {'id': 999999, 'files': []},
      {'files': []},
    ];
    const expected = [
      'META_FILES_MISSING', 'META_FILES_TYPE', 'META_FILES_EMPTY',
      'META_ID_MISMATCH', 'META_ID_MISSING',
    ];
    for (var i = 0; i < samples.length; i++) {
      final client = MockClient((request) async =>
          http.Response('var galleryinfo = ' + jsonEncode(samples[i]) + ';', 200));
      try {
        await HitomiGalleryProvider(client).load(id);
        fail('Expected ' + expected[i]);
      } on OnlineReaderFailure catch (error) {
        expect(error.code, expected[i]);
        expect(error.stage, OnlineReaderStage.metadata);
        expect(error.workId, id);
        expect(error.httpStatus, 200);
        if (error.code == 'META_FILES_TYPE') {
          expect(error.actualType, 'string');
        }
      } finally {
        client.close();
      }
    }
  });

  test('invalid JSON and invalid image entry have distinct codes', () async {
    final badJson = MockClient((request) async =>
        http.Response('var galleryinfo = {"id":broken};', 200));
    await expectLater(
      HitomiGalleryProvider(badJson).load(id),
      throwsA(isA<OnlineReaderFailure>().having(
          (e) => e.code, 'code', 'META_JSON_INVALID')),
    );
    badJson.close();

    final badEntry = MockClient((request) async {
      if (request.url.path == '/gg.js') {
        return http.Response("var o = 0; var x = {b: '2026/'};", 200);
      }
      return http.Response(metadata([
        {'hash': hash},
      ]).replaceFirst('"hash":"'+hash+'"', '"hash":42'), 200);
    });
    await expectLater(HitomiGalleryProvider(badEntry).load(id),
        throwsA(isA<OnlineReaderFailure>().having(
            (e) => e.code, 'code', 'ROUTING_HASH_INVALID')));
    badEntry.close();
  });

  test('metadata HTTP status is recorded without response contents', () async {
    final client = MockClient((request) async =>
        http.Response('PRIVATE_RESPONSE_BODY', 503));
    try {
      await HitomiGalleryProvider(client).load(id);
      fail('Expected metadata error');
    } on OnlineReaderFailure catch (error) {
      expect(error.code, 'META_HTTP_ERROR');
      expect(error.httpStatus, 503);
      expect(error.toString(), isNot(contains('PRIVATE_RESPONSE_BODY')));
    } finally {
      client.close();
    }
  });

  test('image HTTP status includes the page and keeps retryable 503 text',
      () async {
    final client = MockClient((request) async {
      if (request.url.path == '/galleries/2711759.js') {
        return http.Response(metadata([{'hash': hash}]), 200);
      }
      if (request.url.path == '/gg.js') {
        return http.Response("var o = 0; var x = {b: '2026/'};", 200);
      }
      return http.Response('PRIVATE_IMAGE_BODY', 503);
    });
    try {
      final source = await HitomiGalleryProvider(client).load(id);
      await source.loadPage(0);
      fail('Expected image status error');
    } on OnlineReaderFailure catch (error) {
      expect(error.code, 'IMAGE_HTTP_ERROR');
      expect(error.httpStatus, 503);
      expect(error.stage, OnlineReaderStage.image);
      expect(error.page, 1);
      expect(error.toString(), contains('HTTP 503'));
      expect(error.toString(), isNot(contains('PRIVATE_IMAGE_BODY')));
    } finally {
      client.close();
    }
  });

  test('DNS and timeout classification do not leak query strings', () {
    final dns = OnlineReaderFailure.classify(
      http.ClientException('Failed host lookup: host, token=PRIVATE'),
      workId: id, stage: OnlineReaderStage.image,
      host: 'w1.gold-usergeneratedcontent.net', page: 2,
    );
    expect(dns.code, 'IMAGE_DNS_FAILURE');
    expect(dns.page, 2);
    expect(dns.toString(), isNot(contains('PRIVATE')));
    final timeout = OnlineReaderFailure.classify(
      TimeoutException('PRIVATE_LINK'),
      workId: id, stage: OnlineReaderStage.metadata,
    );
    expect(timeout.code, 'META_TIMEOUT');
    expect(timeout.toString(), isNot(contains('PRIVATE_LINK')));
  });

  test('unexpected gg.js format surfaces image-routing stage', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/gg.js') {
        return http.Response('not current routing javascript', 200);
      }
      return http.Response(metadata([{'hash': hash}]), 200);
    });
    try {
      await HitomiGalleryProvider(client).load(id);
      fail('Expected routing error');
    } on OnlineReaderFailure catch (error) {
      expect(error.code, 'ROUTING_FORMAT_CHANGED');
      expect(error.stage, OnlineReaderStage.routing);
    } finally {
      client.close();
    }
  });

}
