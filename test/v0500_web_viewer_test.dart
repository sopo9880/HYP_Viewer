import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/web_page_capture.dart';
import 'package:hyp_viewer/core/web_viewer_store.dart';

void main() {
  test('Kone-like DOM snapshot retains 47 ordered CDN images', () {
    final pages = List.generate(47, (i) => {
      'url': 'https://gimel.mittere.io/file-' + (47 - i).toString() +
          '?v=1793968046-signed',
      'order': 47 - i,
      'width': i == 0 ? 2000 : 1438,
      'height': i == 0 ? 1500 : 2000,
    });
    pages.add({
      'url': 'http://localhost/admin',
      'order': 48,
    });
    pages.add({
      'url': 'https://gimel.mittere.io/file-47?v=1793968046-signed',
      'order': 49,
    });
    final result = WebPageCapture.parse(jsonEncode({
      'url': 'https://kone.gg/s/somisoft/post-id',
      'title': 'A sample work',
      'author': 'example',
      'publishedAt': '2026-11-06T21:02:46+09:00',
      'images': pages,
    }));
    expect(result, isNotNull);
    expect(result!.images, hasLength(47));
    expect(result.images.first.order, 1);
    expect(result.images.last.order, 47);
    expect(result.images.first.url.host, 'gimel.mittere.io');
    expect(result.title, 'A sample work');
    expect(result.author, 'example');
  });

  test('image detection reads post-article wrappers, not site chrome', () {
    expect(WebPageCapture.captureJavaScript, contains('#post-article'));
    expect(WebPageCapture.captureJavaScript, contains('.article-prose'));
    expect(WebPageCapture.captureJavaScript, contains('.image-view-wrapper img'));
    expect(WebPageCapture.captureJavaScript, contains("node.closest('[id^=\"image-\"]')"));
    expect(WebPageCapture.captureJavaScript, contains("meta('article:author')"));
    expect(WebPageCapture.captureJavaScript, contains("link[rel=\"canonical\"]"));
  });

  test('rejects internal and unsafe URLs', () {
    for (final url in [
      'http://kone.gg/a',
      'https://127.0.0.1/a',
      'https://localhost/a',
      'file:///etc/passwd',
      'https://user:pass@kone.gg/a',
    ]) {
      expect(WebViewerStore.safeUrl(url), isNull);
    }
    expect(WebViewerStore.safeUrl('https://kone.gg/s/somisoft'),
        isNotNull);
  });

  test('double encoded snapshots and bad JSON are handled', () {
    final snapshot = jsonEncode({
      'url': 'https://kone.gg/post',
      'title': '안전한 제목',
      'images': [
        {'url': 'https://gimel.mittere.io/a', 'order': 1},
      ],
    });
    expect(WebPageCapture.parse(jsonEncode(snapshot))?.images.length, 1);
    expect(WebPageCapture.parse('not json'), isNull);
  });

  test('image signatures determine file extension, not CDN path', () {
    expect(WebViewerStore.imageExtension(Uint8List.fromList(
        [255, 216, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0])), 'jpg');
    expect(WebViewerStore.imageExtension(Uint8List.fromList(
        [137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0])), 'png');
    expect(WebViewerStore.imageExtension(Uint8List.fromList(
        [82, 73, 70, 70, 0, 0, 0, 0, 87, 69, 66, 80])), 'webp');
    expect(WebViewerStore.imageExtension(Uint8List(20)), isNull);
  });

  test('WEB site bookmarks persist outside original HYP library', () async {
    final temp = await Directory.systemTemp.createTemp('web-viewer-test-');
    try {
      final store = WebViewerStore(baseDirectory: temp);
      await store.addSite('Kone', 'https://kone.gg/s/somisoft');
      final path = await store.root;
      expect(path.path, contains('web_viewer'));
      expect(File(temp.path + Platform.pathSeparator + 'hyp_library.json')
          .existsSync(), isFalse);
      store.dispose();
      final restored = WebViewerStore(baseDirectory: temp);
      await restored.load();
      expect(restored.sites.single.name, 'Kone');
      expect(restored.sites.single.url, 'https://kone.gg/s/somisoft');
      restored.dispose();
    } finally {
      await temp.delete(recursive: true);
    }
  });
}
