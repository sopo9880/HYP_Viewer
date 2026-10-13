import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyp_viewer/core/online_gallery.dart';

void main() {
  const base = 'https://gallery.example.org/gallery/{workId}.json';
  const workId = '2711759';

  test('maps work ID to HTTPS gallery manifest', () {
    final actual = OnlineSourcePolicy.manifestUri(base, workId);
    expect(actual.toString(), 'https://gallery.example.org/gallery/2711759.json');
  });

  test('rejects local IP, plain HTTP and ambiguous template', () {
    expect(
      () => OnlineSourcePolicy.manifestUri(
          'http://gallery.example.org/gallery/{workId}.json', workId),
      throwsFormatException,
    );
    expect(
      () => OnlineSourcePolicy.manifestUri(
          'https://127.0.0.1/gallery/{workId}.json', workId),
      throwsFormatException,
    );
    expect(
      () => OnlineSourcePolicy.manifestUri(
          'https://gallery.example.org/gallery/123.json', workId),
      throwsFormatException,
    );
    expect(
      () => OnlineSourcePolicy.manifestUri(
          'https://gallery.example.org/{workId}/{workId}', workId),
      throwsFormatException,
    );
  });

  test('rejects pages on third-party origins', () {
    final baseUri = OnlineSourcePolicy.manifestUri(base, workId);
    expect(() => OnlineSourcePolicy.pageUrl(
        baseUri, 'https://other.example.org/001.jpg'), throwsFormatException);
    expect(() => OnlineSourcePolicy.pageUrl(
        baseUri, 'http://gallery.example.org/001.jpg'), throwsFormatException);
  });

  test('loads online manifest and a bounded image page', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('.json')) {
        return http.Response(jsonEncode({
          'schemaVersion': 1,
          'workId': workId,
          'title': 'Example work',
          'allowDownload': true,
          'pages': ['/images/01.png', '/images/02.png'],
        }), 200, headers: {'content-type': 'application/json'});
      }
      return http.Response.bytes([137, 80, 78, 71], 200,
          headers: {'content-type': 'image/png'});
    });
    final online = await OnlineGalleryProvider(client).load(base, workId);
    expect(online.pageCount, 2);
    expect(online.downloadAllowed, true);
    expect(online.filename(0), 'page_00001.png');
    expect((await online.loadPage(0)).length, 4);
    client.close();
  });

  test('rejects manifest that lies about the work number', () async {
    final client = MockClient((request) async => http.Response(
      jsonEncode({
        'schemaVersion': 1,
        'workId': '9999999',
        'allowDownload': false,
        'pages': ['/images/01.jpg'],
      }), 200,
      headers: {'content-type': 'application/json'},
    ));
    expect(
      () => OnlineGalleryProvider(client).load(base, workId),
      throwsFormatException,
    );
    client.close();
  });

  test('rejects redirect to another host even over HTTPS', () async {
    final client = MockClient((request) async => http.Response(
      '', 302, headers: {'location': 'https://unsafe.example.net/image.jpg'},
    ));
    expect(
      () => OnlineGalleryProvider(client).load(base, workId),
      throwsA(isA<HttpException>()),
    );
    client.close();
  });

  test('refuses image content with an HTML content type', () async {
    final client = MockClient((request) async => http.Response(
      '<html></html>', 200, headers: {'content-type': 'text/html'},
    ));
    expect(
      () => BoundedWebImages.load(client,
          Uri.parse('https://gallery.example.org/1.jpg'), maxBytes: 64),
      throwsFormatException,
    );
    client.close();
  });

  test('user can cancel image transfer without writing to disk', () async {
    final token = CancelDownload()..cancel();
    final client = MockClient((request) async => http.Response.bytes(
      [1, 2, 3], 200, headers: {'content-type': 'image/png'},
    ));
    expect(
      () => BoundedWebImages.load(client,
          Uri.parse('https://gallery.example.org/1.png'),
          maxBytes: 64, cancellation: token),
      throwsA(isA<DownloadCancelled>()),
    );
    client.close();
  });
}
