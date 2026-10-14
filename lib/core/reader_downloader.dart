import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

import 'gallery.dart';
import 'online_gallery.dart';

/// Pauses between pages, not halfway through a page.
class GalleryTransfer extends CancelDownload {
  bool _paused = false;
  Completer<void>? _wake;

  bool get isPaused => _paused;

  void pause() {
    if (isCancelled || _paused) return;
    _paused = true;
    _wake ??= Completer<void>();
  }

  void resume() {
    _paused = false;
    final pending = _wake;
    _wake = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  @override
  void cancel() {
    super.cancel();
    resume();
  }

  Future<void> checkpoint() async {
    check();
    while (_paused && !isCancelled) {
      await (_wake ??= Completer<void>()).future;
    }
    check();
  }
}

/// Saves the exact images used by the online reader, subject to a deliberate
/// user confirmation and rights check. Never replaces a valid CBZ until a
/// complete new ZIP is staged, decoded and verified by GalleryStore.
class ReaderGalleryDownloader {
  static const maxTotalImageBytes = OnlineGalleryDownloader.maxTotalImageBytes;
  final GalleryStore galleryStore;
  final Directory? temporaryDirectory;

  const ReaderGalleryDownloader(this.galleryStore, {this.temporaryDirectory});

  Future<GalleryArchive> download(
    String workId,
    GalleryPageSource source, {
    required GalleryTransfer transfer,
    void Function(int completed, int total, int bytes)? onProgress,
  }) async {
    if (!RegExp(r'^\d{1,12}$').hasMatch(workId)) {
      throw const FormatException('작품 번호가 유효하지 않아.');
    }
    if (source.pageCount < 1 || source.pageCount > GalleryArchive.maxPages) {
      throw const FormatException('지원하지 않는 페이지 수야.');
    }

    final dir = temporaryDirectory ?? await getApplicationSupportDirectory();
    final staging = Directory(dir.path + Platform.pathSeparator +
      'reader_download_' + workId + '_' +
      DateTime.now().microsecondsSinceEpoch.toString());
    await staging.create(recursive: true);
    final zip = File(staging.path + Platform.pathSeparator + 'gallery.cbz');
    final encoder = ZipFileEncoder();
    var opened = false;
    var count = 0;
    var bytesTotal = 0;
    try {
      encoder.create(zip.path, level: ZipFileEncoder.store);
      opened = true;
      for (var index = 0; index < source.pageCount; index++) {
        await transfer.checkpoint();
        final image = source is OnlineGallery
            ? await source.loadPage(index, cancellation: transfer)
            : await source.loadPage(index);
        transfer.check();
        bytesTotal += image.length;
        if (image.isEmpty ||
            image.length > GalleryArchive.maxSingleImageBytes ||
            bytesTotal > maxTotalImageBytes) {
          throw const FormatException('다운로드 이미지 용량 제한을 초과했어.');
        }
        final sourceName = source.filename(index);
        final extension = RegExp(r'\.(jpg|jpeg|png|webp|gif|bmp)$',
                caseSensitive: false)
            .firstMatch(sourceName)
            ?.group(1)
            ?.toLowerCase();
        if (extension == null) {
          throw const FormatException('지원하지 않는 이미지 확장자야.');
        }
        final name = 'page_' + (index + 1).toString().padLeft(5, '0') +
            '.' + extension;
        final pageFile = File(staging.path + Platform.pathSeparator + name);
        try {
          await pageFile.writeAsBytes(image, flush: true);
          transfer.check();
          await encoder.addFile(pageFile, name, ZipFileEncoder.store);
        } finally {
          if (await pageFile.exists()) await pageFile.delete();
        }
        count++;
        onProgress?.call(count, source.pageCount, bytesTotal);
      }
      await transfer.checkpoint();
      await encoder.close();
      opened = false;
      transfer.check();
      if (await zip.length() > GalleryArchive.maxCompressedBytes) {
        throw const FormatException('CBZ 파일이 180MB를 초과했어.');
      }
      return await galleryStore.importFile(workId, zip.path);
    } finally {
      if (opened) {
        try { await encoder.close(); } catch (_) {}
      }
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }
}
