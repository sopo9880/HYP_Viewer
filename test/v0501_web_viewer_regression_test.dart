import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/web_page_capture.dart';
import 'package:hyp_viewer/core/web_viewer_store.dart';

void main() {
  test('a site bookmark can be edited, then deleted without affecting works',
      () async {
    final dir = await Directory.systemTemp.createTemp('web051-sites-');
    try {
      final store = WebViewerStore(baseDirectory: dir);
      await store.addSite('Original', 'https://example.com/old');
      await store.updateSite('https://example.com/old',
          'Changed', 'https://example.com/new');
      expect(store.sites, hasLength(1));
      expect(store.sites.single.name, 'Changed');
      expect(store.sites.single.url, 'https://example.com/new');
      await store.addSite('Another', 'https://other.example.org/a');
      await expectLater(store.updateSite('https://other.example.org/a',
          'Duplicate', 'https://example.com/new'), throwsStateError);
      expect(store.sites, hasLength(2));
      await store.removeSite('https://example.com/new');
      expect(store.sites.single.name, 'Another');
      store.dispose();
      final restored = WebViewerStore(baseDirectory: dir);
      await restored.load();
      expect(restored.sites.single.url, 'https://other.example.org/a');
      restored.dispose();
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('last visited tab persists, excludes secret query fields, and is '
      'not automatically bookmarked', () async {
    final dir = await Directory.systemTemp.createTemp('web051-last-');
    try {
      final store = WebViewerStore(baseDirectory: dir);
      await store.recordVisitedPage(
        'https://example.com/read?category=new&token=hidden&sig=private#chapter',
        'Chapter 12',
      );
      expect(store.lastTab?.name, 'Chapter 12');
      final parsed = Uri.parse(store.lastTab!.url);
      expect(parsed.queryParameters['category'], 'new');
      expect(parsed.queryParameters.containsKey('token'), isFalse);
      expect(parsed.queryParameters.containsKey('sig'), isFalse);
      expect(parsed.hasFragment, isFalse);
      expect(store.sites, isEmpty);
      await store.recordVisitedPage('https://example.com/another', 'Second');
      expect(store.lastTab?.name, 'Second');
      store.dispose();
      final restored = WebViewerStore(baseDirectory: dir);
      await restored.load();
      expect(restored.recentPages, hasLength(2));
      expect(restored.lastTab?.url, 'https://example.com/another');
      restored.dispose();
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('failure logs can be removed individually or all without deleting '
      'archive metadata', () {
    final store = WebViewerStore();
    store.errors['111'] = 'connection reset';
    store.errors['222'] = 'response 403';
    store.clearFailedDownload('111');
    expect(store.errors.keys.toList(), ['222']);
    store.clearAllFailedDownloads();
    expect(store.errors, isEmpty);
    expect(store.works, isEmpty);
    store.dispose();
  });

  test('webtoon snapshot retains loaded pages in order and indicates '
      '105 expected slots without collecting banners', () {
    final raw = jsonEncode({
      'url': 'https://sample.example.org/webtoon/6549/episode',
      'title': 'Sample Series 77',
      'expectedImages': 105,
      'images': [
        {
          'order': 7,
          'url': 'https://cdn.example.org/shards/file-7.woff2',
          'width': 1200,
          'height': 1600,
          'noReferrer': true,
        },
        {
          'order': 2,
          'url': 'https://cdn.example.org/shards/file-2.css',
          'width': 1200,
          'height': 1600,
          'noReferrer': true,
        },
        {
          'order': 1,
          'url': 'https://cdn.example.org/shards/file-1.json',
          'width': 1200,
          'height': 1600,
          'noReferrer': true,
        },
        {
          'order': 8,
          'url': 'https://127.0.0.1/private',
        },
      ],
    });
    final result = WebPageCapture.parse(raw);
    expect(result, isNotNull);
    expect(result!.expectedImages, 105);
    expect(result.images.map((x) => x.order), [1, 2, 7]);
    expect(result.images.every((x) => x.noReferrer), isTrue);
    expect(result.images.first.url.path, endsWith('.json'));
  });

  test('webtoon DOM detector only scans reading area and verified '
      'rendered images', () {
    final javascript = WebPageCapture.captureJavaScript;
    expect(javascript, contains("document.querySelector('[data-theme-viewer-images]')"));
    expect(javascript, contains("themeViewer.querySelectorAll('.theme-viewer-image[data-theme-page] img')"));
    expect(javascript, contains("themeSlot.getAttribute('data-theme-page')"));
    expect(javascript, contains('node.naturalWidth <= 0'));
    expect(javascript, contains("document.querySelector('.theme-viewer-title')"));
    expect(javascript, contains("node.getAttribute('referrerpolicy')"));
    expect(javascript, contains('expectedImages: slots.length'));
  });
}
