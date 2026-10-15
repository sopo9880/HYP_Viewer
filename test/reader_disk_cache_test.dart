import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/gallery.dart';
import 'package:hyp_viewer/core/reader_disk_cache.dart';

class _Pages implements GalleryPageSource {
  int calls = 0;
  @override int get pageCount => 6;
  @override String filename(int index) => 'page_$index.jpg';
  @override Future<Uint8List> loadPage(int index) async {
    calls++;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return Uint8List.fromList([index + 1, 2, 3]);
  }
}

void main() {
  test('full preloading stores pages on disk and avoids duplicate fetches',
      () async {
    final parent = await Directory.systemTemp.createTemp('hyp-preload-test-');
    addTearDown(() => parent.delete(recursive: true));
    final source = _Pages();
    final disk = GalleryDiskCache(source, parent: parent);
    disk.warmAll();
    // A visible page requested during warmup shares the in-flight request.
    await disk.loadPage(0);
    // Drain the preload worker through actual results, not a fragile timer.
    for (var i = 0; i < 200 && source.calls < 6; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(source.calls, 6);
    expect(await disk.loadPage(0), [1, 2, 3]);
    expect(source.calls, 6);
    await disk.dispose();
    expect(await parent.list().toList(), isEmpty);
  });

  test('manual retry purges only the failed page, preserving good pages',
      () async {
    final parent = await Directory.systemTemp.createTemp('hyp-retry-test-');
    addTearDown(() => parent.delete(recursive: true));
    final source = _Pages();
    final cache = GalleryDiskCache(source, parent: parent);
    try {
      expect(await cache.loadPage(0), [1, 2, 3]);
      expect(await cache.loadPage(1), [2, 2, 3]);
      expect(source.calls, 2);
      await cache.invalidate(0);
      expect(await cache.loadPage(0), [1, 2, 3]);
      expect(source.calls, 3);
      expect(await cache.loadPage(1), [2, 2, 3]);
      expect(source.calls, 3,
          reason: 'Retrying a corrupt page must not clear valid page caches');
    } finally {
      await cache.dispose();
    }
  });

  test('small disk budget safely refuses further full-cache writes',
      () async {
    final parent = await Directory.systemTemp.createTemp('hyp-limit-test-');
    addTearDown(() => parent.delete(recursive: true));
    final disk = GalleryDiskCache(_Pages(), parent: parent, maxBytes: 4);
    await disk.loadPage(0);
    await disk.loadPage(1);
    expect(disk.capacityReached, true);
    await disk.dispose();
  });
}
