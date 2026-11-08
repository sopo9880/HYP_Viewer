import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/viewer_mode.dart';
import 'package:hyp_viewer/core/web_viewer_store.dart';

void main() {
  test('SERIES web tab maps to shared browser workspace', () {
    expect(ViewerMode.series.containsPage('favorites'), isTrue);
    expect(ViewerMode.series.contentSection('favorites'), 'series_web');
    expect(ViewerMode.series.mobilePages,
      ['favorites', 'library', 'home', 'downloads', 'settings']);
  });

  test('visit history persists past legacy 20-item cap', () async {
    final dir = await Directory.systemTemp.createTemp('v053-history-');
    try {
      final store = WebViewerStore(baseDirectory: dir);
      await store.load();
      for (var i = 0; i < 30; i++) {
        await store.recordVisitedPage(
          'https://example.org/article/$i', 'Article $i');
      }
      expect(store.recentPages, hasLength(30));
      store.dispose();

      final restored = WebViewerStore(baseDirectory: dir);
      await restored.load();
      expect(restored.recentPages, hasLength(30));
      expect(restored.recentPages.first.url,
        'https://example.org/article/29');
      expect(restored.recentPages.last.url,
        'https://example.org/article/0');
      await restored.removeRecentPage('https://example.org/article/15');
      expect(restored.recentPages, hasLength(29));
      restored.dispose();
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('history strips authentication query fields', () {
    final sanitized = WebViewerStore.safeHistoryUrl(
      'https://example.org/chapter?chapter=2&token=secret#panel');
    expect(sanitized, isNotNull);
    expect(sanitized!.toString(),
      'https://example.org/chapter?chapter=2');
  });
}
