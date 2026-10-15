import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

import 'gallery.dart';
import 'hitomi_gallery.dart';
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
    // A stable per-work directory lets partial pages survive app restarts.
    // Never stage inside the installed app folder: updates can replace it.
    final root = Directory(dir.path + Platform.pathSeparator +
        'reader_transfers');
    await root.create(recursive: true);
    final staging = Directory(root.path + Platform.pathSeparator + workId);
    final metadata = File(staging.path + Platform.pathSeparator + 'source.json');

    // Hitomi URLs contain expiring tokens: compare stable image identifiers
    // rather than their transient delivery URLs. Other manifests use their
    // literal public image URLs for identity and cannot cross-load origins.
    final imageIdentity = <String>[
      workId,
      source.runtimeType.toString(),
      source.pageCount.toString(),
      for (var i = 0; i < source.pageCount; i++)
        source is HitomiGallery
            ? source.pageUrls[i].pathSegments.last
            : source is OnlineGallery
                ? source.pageUrls[i].toString()
                : source.filename(i),
    ].join('|');
    final signature = sha256.convert(utf8.encode(imageIdentity)).toString();
    var matchesPrevious = false;
    if (await metadata.exists()) {
      try {
        final existing = jsonDecode(await metadata.readAsString());
        matchesPrevious = existing is Map &&
            existing['version'] == 1 &&
            existing['signature'] == signature;
      } catch (_) { /* Old/corrupt checkpoint; safely start again. */ }
    }
    if (!matchesPrevious && await staging.exists()) {
      await staging.delete(recursive: true);
    }
    await staging.create(recursive: true);
    await metadata.writeAsString(jsonEncode({
      'version': 1, 'signature': signature, 'pageCount': source.pageCount,
    }), flush: true);
    final zip = File(staging.path + Platform.pathSeparator + 'gallery.cbz');
    final encoder = ZipFileEncoder();
    var opened = false;
    var count = 0;
    var bytesTotal = 0;
    var finished = false;

    String imageName(int index) {
      final sourceName = source.filename(index);
      final extension = RegExp(r'\.(jpg|jpeg|png|webp|gif|bmp)$',
              caseSensitive: false)
          .firstMatch(sourceName)?.group(1)?.toLowerCase();
      if (extension == null) {
        throw const FormatException('지원하지 않는 이미지 확장자야.');
      }
      return 'page_' + (index + 1).toString().padLeft(5, '0') +
          '.' + extension;
    }

    try {
      // Archives are rebuilt from completed page files on every attempt.
      // A previously valid CBZ is never touched until import succeeds.
      if (await zip.exists()) await zip.delete();
      encoder.create(zip.path, level: ZipFileEncoder.store);
      opened = true;
      for (var index = 0; index < source.pageCount; index++) {
        await transfer.checkpoint();
        final name = imageName(index);
        final pageFile = File(staging.path + Platform.pathSeparator + name);
        var valid = false;
        var size = 0;
        if (await pageFile.exists()) {
          size = await pageFile.length();
          valid = size > 0 && size <= GalleryArchive.maxSingleImageBytes &&
              bytesTotal + size <= maxTotalImageBytes;
          if (!valid) await pageFile.delete();
        }
        if (!valid) {
          final image = source is OnlineGallery
              ? await source.loadPage(index, cancellation: transfer)
              : await source.loadPage(index);
          transfer.check();
          size = image.length;
          if (image.isEmpty ||
              size > GalleryArchive.maxSingleImageBytes ||
              bytesTotal + size > maxTotalImageBytes) {
            throw const FormatException('다운로드 이미지 용량 제한을 초과했어.');
          }
          // Write to a temporary file and commit by rename only after flush.
          // An interrupted .part can never masquerade as a complete page.
          final partial = File(pageFile.path + '.part');
          if (await partial.exists()) await partial.delete();
          await partial.writeAsBytes(image, flush: true);
          await partial.rename(pageFile.path);
        }
        transfer.check();
        bytesTotal += size;
        await encoder.addFile(pageFile, name, ZipFileEncoder.store);
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
      final imported = await galleryStore.importFile(workId, zip.path);
      finished = true;
      return imported;
    } finally {
      if (opened) {
        try { await encoder.close(); } catch (_) {}
      }
      // Keep completed pages after transient failure/app termination. Delete
      // them only on success or deliberate cancellation by the user.
      if ((finished || transfer.isCancelled) && await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
  }
}
