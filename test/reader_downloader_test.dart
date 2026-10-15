import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/gallery.dart';
import 'package:hyp_viewer/core/reader_downloader.dart';

class _TestPages implements GalleryPageSource {
  int requested = 0;
  @override
  int get pageCount => 3;
  @override
  String filename(int index) => 'test_$index.webp';
  @override
  Future<Uint8List> loadPage(int index) async {
    requested++;
    return Uint8List.fromList([0x52, 0x49, 0x46, 0x46, index, 1, 2, 3]);
  }
}

class _FailAfterOne extends _TestPages {
  @override
  Future<Uint8List> loadPage(int index) async {
    if (index == 1) {
      requested++;
      throw StateError('temporary disconnect');
    }
    return super.loadPage(index);
  }
}

void main() {
  test('uses reader page loader and imports complete CBZ', () async {
    final dir = await Directory.systemTemp.createTemp('hyp-cbz-');
    addTearDown(() => dir.delete(recursive: true));
    final gallery = GalleryStore(baseDirectory: dir);
    final source = _TestPages();
    final progress = <int>[];
    final result = await ReaderGalleryDownloader(gallery,
      temporaryDirectory: dir).download('2711759', source,
        transfer: GalleryTransfer(),
        onProgress: (done, _, __) => progress.add(done));
    expect(progress, [1, 2, 3]);
    expect(source.requested, 3);
    expect(result.pageCount, 3);
    expect(await gallery.exists('2711759'), true);
    expect((await gallery.read('2711759')).pageCount, 3);
    final staged = await dir.list().toList();
    expect(staged.where((e) => e.path.contains('reader_download_')), isEmpty);
  });

  test('can pause, resume and cancel without overwriting previous CBZ',
      () async {
    final dir = await Directory.systemTemp.createTemp('hyp-cancel-');
    addTearDown(() => dir.delete(recursive: true));
    final store = GalleryStore(baseDirectory: dir);
    final downloader = ReaderGalleryDownloader(store, temporaryDirectory: dir);
    await downloader.download('321', _TestPages(), transfer: GalleryTransfer());

    final session = GalleryTransfer();
    final source = _TestPages();
    final firstPagePaused = Completer<void>();
    final run = downloader.download('321', source, transfer: session,
      onProgress: (done, total, bytes) {
        if (done == 1) {
          session.pause();
          if (!firstPagePaused.isCompleted) firstPagePaused.complete();
        }
      },
    );
    // Wait for an actual event, not a fixed wall-clock delay. Filesystem
    // latency on shared CI runners varies and can exceed 120 ms.
    await firstPagePaused.future.timeout(const Duration(seconds: 30));
    expect(session.isPaused, true);
    expect(source.requested, 1);
    session.cancel();
    await expectLater(run, throwsA(isA<Exception>()));
    expect((await store.read('321')).pageCount, 3);
  });

  test('failed transfer resumes completed pages with the same source', () async {
    final dir = await Directory.systemTemp.createTemp('hyp-resume-');
    addTearDown(() => dir.delete(recursive: true));
    final store = GalleryStore(baseDirectory: dir);
    final downloader = ReaderGalleryDownloader(store, temporaryDirectory: dir);
    final first = _FailAfterOne();
    await expectLater(
      downloader.download('78123', first, transfer: GalleryTransfer()),
      throwsA(isA<StateError>()),
    );
    expect(first.requested, 2);
    expect(await store.exists('78123'), false);
    final second = _TestPages();
    final events = <int>[];
    final result = await downloader.download('78123', second,
        transfer: GalleryTransfer(),
        onProgress: (n, _, __) => events.add(n));
    expect(result.pageCount, 3);
    expect(second.requested, 2); // First completed page was reused.
    expect(events, [1, 2, 3]);
  });

  test('rejects invalid IDs', () async {
    final dir = await Directory.systemTemp.createTemp('hyp-id-');
    addTearDown(() => dir.delete(recursive: true));
    await expectLater(
      ReaderGalleryDownloader(GalleryStore(baseDirectory: dir),
        temporaryDirectory: dir).download('../evil', _TestPages(),
            transfer: GalleryTransfer()),
      throwsFormatException,
    );
  });
}
