import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyp_viewer/core/gallery.dart';
import 'package:hyp_viewer/core/online_gallery.dart';

void main() {
  const template = 'https://gallery.example.org/galleries/{workId}.json';
  const workId = '2711759';

  Future<OnlineGallery> gallery(http.Client client, {bool allow = true}) async {
    return OnlineGalleryProvider(client).load(template, workId);
  }

  MockClient createClient({bool allow = true}) {
    return MockClient((request) async {
      if (request.url.path.endsWith('.json')) {
        return http.Response(
          jsonEncode({
            'schemaVersion': 1,
            'workId': workId,
            'title': 'Example',
            'allowDownload': allow,
            'pages': ['/images/001.png', '/images/002.png'],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response.bytes(
        [137, 80, 78, 71, 1, 2, 3, 4],
        200,
        headers: {'content-type': 'image/png'},
      );
    });
  }

  test('manual download builds a persistent, readable CBZ', () async {
    final tmp = await Directory.systemTemp.createTemp('hyp-download-test');
    final client = createClient();
    try {
      final online = await gallery(client);
      final store = GalleryStore(baseDirectory: tmp);
      final events = <int>[];
      final saved = await OnlineGalleryDownloader(
        store, temporaryDirectory: tmp,
      ).download(online,
        cancellation: CancelDownload(),
        onProgress: (done, total, bytes) => events.add(done),
      );
      expect(saved.pageCount, 2);
      expect(events, [1, 2]);
      expect(await store.exists(workId), true);
      final reopened = await store.read(workId);
      expect(reopened.pageCount, 2);
      expect(reopened.filename(0), 'page_00001.png');
      expect(reopened.pageBytes(1).length, 8);
    } finally {
      client.close();
      await tmp.delete(recursive: true);
    }
  });

  test('no-download manifest is enforced before writing any files', () async {
    final tmp = await Directory.systemTemp.createTemp('hyp-no-download-test');
    final client = createClient(allow: false);
    try {
      final online = await gallery(client);
      final store = GalleryStore(baseDirectory: tmp);
      await expectLater(
        OnlineGalleryDownloader(store, temporaryDirectory: tmp).download(
          online, cancellation: CancelDownload(),
        ),
        throwsFormatException,
      );
      expect(await store.exists(workId), false);
    } finally {
      client.close();
      await tmp.delete(recursive: true);
    }
  });

  test('cancel mid-download leaves previous CBZ untouched', () async {
    final tmp = await Directory.systemTemp.createTemp('hyp-cancel-download');
    final client = createClient();
    try {
      final online = await gallery(client);
      final store = GalleryStore(baseDirectory: tmp);
      final downloader = OnlineGalleryDownloader(store, temporaryDirectory: tmp);
      await downloader.download(online, cancellation: CancelDownload());
      final old = await store.read(workId);
      final token = CancelDownload();
      await expectLater(
        downloader.download(
          online,
          cancellation: token,
          onProgress: (done, total, bytes) {
            if (done == 1) token.cancel();
          },
        ),
        throwsA(isA<DownloadCancelled>()),
      );
      expect((await store.read(workId)).pageCount, old.pageCount);
    } finally {
      client.close();
      await tmp.delete(recursive: true);
    }
  });
}
