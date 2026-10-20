import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

import 'gallery_download_limits.dart';

/// A shared page interface for local archives and authorized online galleries.
abstract class GalleryPageSource {
  int get pageCount;
  String filename(int index);
  Future<Uint8List> loadPage(int index);
}

/// A local, user-selected CBZ/ZIP gallery. No archive entry is extracted to
/// the filesystem, avoiding ZIP path traversal and other path overwrite bugs.
class GalleryArchive implements GalleryPageSource {
  // Absolute safety boundaries, NOT the user-configured download limits.
  static const int maxCompressedBytes =
      GalleryDownloadLimits.hardArchiveMiB * GalleryDownloadLimits.mib;
  static const int maxUncompressedBytes =
      GalleryDownloadLimits.hardUncompressedMiB * GalleryDownloadLimits.mib;
  static const int maxSingleImageBytes =
      GalleryDownloadLimits.hardImageMiB * GalleryDownloadLimits.mib;
  static const int maxPages = 1500;

  final List<ArchiveFile> _pages;
  GalleryArchive._(this._pages);

  int get pageCount => _pages.length;

  static GalleryArchive decode(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxCompressedBytes) {
      throw const FormatException('압축 파일 크기는 안전 상한(1GiB)을 초과했어.');
    }
    final decoded = ZipDecoder().decodeBytes(bytes);
    final pages = decoded
        .where((f) =>
            f.isFile &&
            !f.name.startsWith('__MACOSX/') &&
            RegExp(r'\.(png|jpg|jpeg|webp|gif|bmp)$', caseSensitive: false)
                .hasMatch(f.name))
        .toList();
    if (pages.isEmpty) {
      throw const FormatException('압축 파일 안에 이미지 페이지가 없어.');
    }
    if (pages.length > maxPages) {
      throw const FormatException('페이지 수가 너무 많아 (최대 1500장).');
    }
    var total = 0;
    for (final page in pages) {
      if (page.size < 1 || page.size > maxSingleImageBytes) {
        throw const FormatException('이미지 한 장은 안전 상한(128MiB)을 초과했어.');
      }
      total += page.size;
      if (total > maxUncompressedBytes) {
        throw const FormatException('압축 해제되는 이미지의 총 크기가 너무 커.');
      }
    }
    pages.sort((a, b) => _naturalCompare(a.name, b.name));
    return GalleryArchive._(pages);
  }

  String filename(int index) => _pages[index].name;

  @override
  Future<Uint8List> loadPage(int index) async => pageBytes(index);

  Uint8List pageBytes(int index) {
    if (index < 0 || index >= pageCount) throw RangeError.index(index, _pages);
    final bytes = _pages[index].readBytes();
    if (bytes == null || bytes.length > maxSingleImageBytes) {
      throw const FormatException('이미지 페이지를 읽지 못했어.');
    }
    return bytes;
  }

  static int _naturalCompare(String a, String b) {
    final aa = RegExp(r'\d+|\D+').allMatches(a.toLowerCase())
        .map((m) => m.group(0)!).toList();
    final bb = RegExp(r'\d+|\D+').allMatches(b.toLowerCase())
        .map((m) => m.group(0)!).toList();
    for (var i = 0; i < aa.length && i < bb.length; i++) {
      final an = BigInt.tryParse(aa[i]);
      final bn = BigInt.tryParse(bb[i]);
      final result = (an != null && bn != null)
          ? an.compareTo(bn)
          : aa[i].compareTo(bb[i]);
      if (result != 0) return result;
    }
    return aa.length.compareTo(bb.length);
  }
}

/// CBZ is stored in app support files, outside the application installation
/// directory. JSON library backups store only metadata; CBZ stays local.
class GalleryStore {
  final Directory? baseDirectory;

  const GalleryStore({this.baseDirectory});

  Future<File> _localFile(String workId) async {
    if (!RegExp(r'^\d{1,12}$').hasMatch(workId)) {
      throw const FormatException('잘못된 작품 번호');
    }
    final root = baseDirectory ?? await getApplicationSupportDirectory();
    final dir = Directory(root.path + Platform.pathSeparator + 'galleries');
    await dir.create(recursive: true);
    return File(dir.path + Platform.pathSeparator + workId + '.cbz');
  }

  Future<bool> exists(String workId) async =>
      await (await _localFile(workId)).exists();

  /// Read-only access to an already downloaded CBZ for user-authorized
  /// export. Never exposes arbitrary app-private filesystem paths.
  Future<File> existingCbzFile(String workId) async {
    final file = await _localFile(workId);
    if (!await file.exists()) {
      throw const FileSystemException('저장된 CBZ 파일이 없어.');
    }
    if (await file.length() > GalleryArchive.maxCompressedBytes) {
      throw const FormatException('저장된 CBZ 크기가 허용 범위를 넘어.');
    }
    return file;
  }

  /// Delete the local CBZ without touching the library, progress or covers.
  Future<void> delete(String workId) async {
    final file = await _localFile(workId);
    if (await file.exists()) await file.delete();
    final previous = File(file.path + '.previous');
    if (await previous.exists()) await previous.delete();
  }

  Future<GalleryArchive> read(String workId) async {
    final f = await _localFile(workId);
    if (!await f.exists()) {
      throw const FileSystemException('작품의 로컬 이미지 파일이 없어.');
    }
    if (await f.length() > GalleryArchive.maxCompressedBytes) {
      throw const FormatException('파일이 너무 커.');
    }
    return GalleryArchive.decode(await f.readAsBytes());
  }

  Future<GalleryArchive> importFile(String workId, String selectedPath) async {
    final src = File(selectedPath);
    if (!await src.exists()) {
      throw const FileSystemException('선택한 파일을 찾지 못했어.');
    }
    if (await src.length() > GalleryArchive.maxCompressedBytes) {
      throw const FormatException('파일이 안전 상한(1GiB)을 초과했어.');
    }
    final bytes = await src.readAsBytes();
    final archive = GalleryArchive.decode(bytes); // Validate BEFORE replacing.
    final target = await _localFile(workId);
    final tmp = File(target.path + '.importing');
    final previous = File(target.path + '.previous');
    var movedExisting = false;
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      // Move the existing file to a local rollback copy only after the new
      // CBZ was fully validated and saved to staging.
      if (await target.exists()) {
        if (await previous.exists()) await previous.delete();
        await target.rename(previous.path);
        movedExisting = true;
      }
      await tmp.rename(target.path);
    } catch (_) {
      if (movedExisting && !await target.exists() && await previous.exists()) {
        await previous.rename(target.path);
      }
      rethrow;
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
    return archive;
  }
}
