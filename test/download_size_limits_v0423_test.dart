import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/download_queue_store.dart';
import 'package:hyp_viewer/core/gallery.dart';
import 'package:hyp_viewer/core/gallery_download_limits.dart';
import 'package:hyp_viewer/core/reader_downloader.dart';
import 'package:hyp_viewer/core/reader_settings.dart';

class _Pages implements GalleryPageSource {
  final List<int> sizes;
  int loaded = 0;
  _Pages(this.sizes);

  @override
  int get pageCount => sizes.length;
  @override
  String filename(int index) => 'page_' + (index + 1).toString() + '.png';
  @override
  Future<Uint8List> loadPage(int index) async {
    loaded++;
    return Uint8List(sizes[index]);
  }
}

void main() {
  test('legacy and invalid settings preserve safe defaults', () {
    final old = ReaderSettings.fromJson({'nextDirection': 'right'});
    expect(old.downloadImageLimitMiB, 35);
    expect(old.downloadTotalLimitMiB, 165);
    expect(old.downloadArchiveLimitMiB, 180);

    final saved = ReaderSettings.fromJson(old.copyWith(
        downloadImageLimitMiB: 100,
        downloadTotalLimitMiB: 512,
        downloadArchiveLimitMiB: 1024).toJson());
    expect(saved.downloadImageLimitMiB, 100);
    expect(saved.downloadTotalLimitMiB, 512);
    expect(saved.downloadArchiveLimitMiB, 1024);
    expect(saved.nextDirection, 'right');

    final invalid = ReaderSettings.fromJson({
      'downloadImageLimitMiB': 1000000,
      'downloadTotalLimitMiB': -500,
      'downloadArchiveLimitMiB': '1000',
    });
    expect(invalid.downloadImageLimitMiB, 35);
    expect(invalid.downloadTotalLimitMiB, 165);
    expect(invalid.downloadArchiveLimitMiB, 180);
  });

  test('single-image limit has a specific failure code and retry succeeds',
      () async {
    final dir = await Directory.systemTemp.createTemp('hyp-size-img-');
    addTearDown(() => dir.delete(recursive: true));
    final source = _Pages([1200000]);
    final store = GalleryStore(baseDirectory: dir);
    final downloader = ReaderGalleryDownloader(
        store, temporaryDirectory: dir);
    const limits = GalleryDownloadLimits(
        imageMiB: 1, totalMiB: 2, archiveMiB: 2);
    try {
      await downloader.download('1234', source,
          transfer: GalleryTransfer(), limits: limits);
      fail('expected image soft limit');
    } on GallerySizeLimitException catch (error) {
      expect(error.code, 'DOWNLOAD_IMAGE_SIZE_LIMIT');
      expect(error.limitBytes, GalleryDownloadLimits.mib);
    }
    final archive = await downloader.download('1234', source,
        transfer: GalleryTransfer(), limits: limits,
        allowSizeOverride: true);
    expect(archive.pageCount, 1);
    expect((await store.read('1234')).pageCount, 1);
  });

  test('total limit retains complete pages; manual retry reuses them',
      () async {
    final dir = await Directory.systemTemp.createTemp('hyp-size-total-');
    addTearDown(() => dir.delete(recursive: true));
    final source = _Pages([650000, 650000]);
    final store = GalleryStore(baseDirectory: dir);
    final downloader = ReaderGalleryDownloader(
        store, temporaryDirectory: dir);
    const limits = GalleryDownloadLimits(
        imageMiB: 1, totalMiB: 1, archiveMiB: 2);
    try {
      await downloader.download('2345', source,
          transfer: GalleryTransfer(), limits: limits);
      fail('expected total soft limit');
    } on GallerySizeLimitException catch (error) {
      expect(error.code, 'DOWNLOAD_TOTAL_SIZE_LIMIT');
    }
    expect(await store.exists('2345'), isFalse);
    expect(await File(dir.path +
        '/reader_transfers/2345/page_00001.png').exists(), isTrue);
    expect(source.loaded, 2);
    final archive = await downloader.download('2345', source,
        transfer: GalleryTransfer(), limits: limits,
        allowSizeOverride: true);
    expect(archive.pageCount, 2);
    expect(source.loaded, 3);
    expect((await store.read('2345')).pageCount, 2);
  });

  test('archive limit blocks import; retry can import and reopen',
      () async {
    final dir = await Directory.systemTemp.createTemp('hyp-size-zip-');
    addTearDown(() => dir.delete(recursive: true));
    final source = _Pages([1200000]);
    final store = GalleryStore(baseDirectory: dir);
    final downloader = ReaderGalleryDownloader(
        store, temporaryDirectory: dir);
    const limits = GalleryDownloadLimits(
        imageMiB: 2, totalMiB: 2, archiveMiB: 1);
    try {
      await downloader.download('3456', source,
          transfer: GalleryTransfer(), limits: limits);
      fail('expected CBZ soft limit');
    } on GallerySizeLimitException catch (error) {
      expect(error.code, 'DOWNLOAD_ARCHIVE_SIZE_LIMIT');
    }
    expect(await store.exists('3456'), isFalse);
    final archive = await downloader.download('3456', source,
        transfer: GalleryTransfer(), limits: limits,
        allowSizeOverride: true);
    expect(archive.pageCount, 1);
    expect(source.loaded, 1);
    expect((await store.read('3456')).pageCount, 1);
  });

  test('per-work approval survives restart and is removed on completion',
      () async {
    final dir = await Directory.systemTemp.createTemp('hyp-size-queue-');
    addTearDown(() => dir.delete(recursive: true));
    final initial = DownloadQueueStore(baseDirectory: dir);
    await initial.add('101', source: 'json', allowSizeOverride: true);
    await initial.add('101', source: 'json');
    await initial.add('202');
    final restored = DownloadQueueStore(baseDirectory: dir);
    expect(await restored.load(), {'101': 'json', '202': 'hitomi'});
    expect(await restored.loadSizeOverrides(), {'101'});
    for (final code in ['DOWNLOAD_TOTAL_SIZE_LIMIT', 'IMAGE_SIZE_LIMIT',
        'DOWNLOAD_FAILED']) {
      expect(GallerySizeLimitException.allowsExplicitRetry(code), isTrue);
    }
    for (final code in ['DOWNLOAD_NETWORK_FAILED', 'META_ID_MISMATCH']) {
      expect(GallerySizeLimitException.allowsExplicitRetry(code), isFalse);
    }
    await restored.remove('101');
    expect(await DownloadQueueStore(baseDirectory: dir)
        .loadSizeOverrides(), isEmpty);
  });

  test('hard parser limits are independent of selected and retry limits', () {
    expect(GalleryArchive.maxSingleImageBytes,
        GalleryDownloadLimits.hardImageMiB * GalleryDownloadLimits.mib);
    expect(GalleryArchive.maxCompressedBytes,
        GalleryDownloadLimits.hardArchiveMiB * GalleryDownloadLimits.mib);
    expect(GalleryArchive.maxUncompressedBytes,
        GalleryDownloadLimits.hardUncompressedMiB * GalleryDownloadLimits.mib);
    expect(GalleryArchive.maxPages, 1500);
  });

  test('download UI, queue, and both sources wire soft limits', () {
    final ui = File('lib/ui/hyp_dashboard.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    for (final key in ['download-limit-image', 'download-limit-total',
        'download-limit-archive']) {
      expect(ui, contains(key));
    }
    expect(main, contains('readerSettings.downloadLimits'));
    expect(main, contains('sizeOverrideIds: sizeApproved'));
    expect(main, contains('_downloadJobs.loadSizeOverrides()'));
    expect(File('lib/core/online_gallery.dart').readAsStringSync(),
        contains('loadPageWithLimit'));
    expect(File('lib/core/hitomi_gallery.dart').readAsStringSync(),
        contains('loadPageWithLimit'));
  });
}
