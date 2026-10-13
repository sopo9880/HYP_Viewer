import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

/// A local, user-selected CBZ/ZIP gallery. No archive entry is extracted to
/// the filesystem, avoiding ZIP path traversal and other path overwrite bugs.
class GalleryArchive {
  static const int maxCompressedBytes = 180 * 1024 * 1024;
  static const int maxUncompressedBytes = 750 * 1024 * 1024;
  static const int maxSingleImageBytes = 35 * 1024 * 1024;
  static const int maxPages = 1500;

  final List<ArchiveFile> _pages;
  GalleryArchive._(this._pages);

  int get pageCount => _pages.length;

  static GalleryArchive decode(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxCompressedBytes) {
      throw const FormatException('압축 파일 크기는 최대 180MB까지 지원해.');
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
        throw const FormatException('이미지 한 장은 최대 35MB까지 지원해.');
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
  Future<File> _localFile(String workId) async {
    if (!RegExp(r'^\d{1,12}$').hasMatch(workId)) {
      throw const FormatException('잘못된 작품 번호');
    }
    final root = await getApplicationSupportDirectory();
    final dir = Directory(root.path + Platform.pathSeparator + 'galleries');
    await dir.create(recursive: true);
    return File(dir.path + Platform.pathSeparator + workId + '.cbz');
  }

  Future<bool> exists(String workId) async =>
      await (await _localFile(workId)).exists();

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
      throw const FormatException('파일이 180MB를 초과했어.');
    }
    final bytes = await src.readAsBytes();
    final archive = GalleryArchive.decode(bytes); // Validate BEFORE replacing.
    final target = await _localFile(workId);
    final tmp = File(target.path + '.importing');
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      // Existing gallery is copied to a local fallback before replacing.
      if (await target.exists()) {
        await target.copy(target.path + '.previous');
        await target.delete();
      }
      await tmp.rename(target.path);
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
    return archive;
  }
}
