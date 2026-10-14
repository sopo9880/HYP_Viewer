import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/gallery.dart';
import 'package:hyp_viewer/core/reader_disk_cache.dart';

class _RateLimitedPages implements GalleryPageSource {
  final List<int> called = [];
  int active = 0;
  int maxActive = 0;
  @override int get pageCount => 22;
  @override String filename(int index) => '$index.webp';
  @override Future<Uint8List> loadPage(int index) async {
    called.add(index);
    active++;
    if (active > maxActive) maxActive = active;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 12));
      return Uint8List.fromList([index + 1, 1, 2, 3]);
    } finally {
      active--;
    }
  }
}

class _RecoveringPages implements GalleryPageSource {
  int calls = 0;
  @override int get pageCount => 3;
  @override String filename(int index) => 'p$index.webp';
  @override Future<Uint8List> loadPage(int index) async {
    calls++;
    if (calls == 1) throw const FormatException(
        'WebP 이미지 로딩 실패, HttpException: 서버가 응답하지 않았어: 503');
    return Uint8List.fromList([1, 2, 3]);
  }
}

void main() {
  test('whole background load and far-page jumps share concurrency ceiling',
      () async {
    final src = _RateLimitedPages();
    final cache = GalleryDiskCache(src, concurrency: 2);
    cache.warmAll();
    final distant = await cache.loadPage(19);
    expect(distant.first, 20);
    expect(src.maxActive, lessThanOrEqualTo(2));
    expect(src.called.indexOf(19), lessThanOrEqualTo(2));
    // The next load of the same page should use the temporary disk cache.
    final calls = src.called.where((i) => i == 19).length;
    expect((await cache.loadPage(19)).first, 20);
    expect(src.called.where((i) => i == 19).length, calls);
    await cache.dispose();
  });

  test('503 transient errors are retried a bounded number of times', () async {
    final src = _RecoveringPages();
    final cache = GalleryDiskCache(src, concurrency: 1);
    expect(await cache.loadPage(0), [1, 2, 3]);
    expect(src.calls, 2);
    await cache.dispose();
  });

  test('data saver can configure a strict one-request queue', () async {
    final src = _RateLimitedPages();
    final cache = GalleryDiskCache(src, concurrency: 1);
    cache.warmAround(2, 1);
    await cache.loadPage(17);
    expect(src.maxActive, 1);
    await cache.dispose();
  });
}
