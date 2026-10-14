import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';

/// Stores small, locally generated previews. The files are intentionally
/// excluded from JSON backups; chosen page numbers survive and can regenerate.
class CoverStore {
  final Directory? baseDirectory;
  const CoverStore({this.baseDirectory});

  static bool _valid(String id) => RegExp(r'^\d{1,12}$').hasMatch(id);

  Future<File> _imageFile(String workId, String mode, int page) async {
    if (!_valid(workId) || !{'auto', 'page', 'custom'}.contains(mode) ||
        page < 1 || page > 1000000) {
      throw const FormatException('표지 파일 경로가 유효하지 않아.');
    }
    final root = baseDirectory ?? await getApplicationSupportDirectory();
    final dir = Directory(root.path + Platform.pathSeparator + 'covers');
    await dir.create(recursive: true);
    final suffix = mode == 'auto' ? 'auto' :
        mode == 'custom' ? 'custom' : 'page_' + page.toString();
    return File(dir.path + Platform.pathSeparator + workId + '_' + suffix + '.png');
  }

  Future<Uint8List?> read(String workId, {
    String mode = 'auto', int page = 1,
  }) async {
    if (mode == 'preset') return null;
    final f = await _imageFile(workId, mode, page);
    if (!await f.exists()) return null;
    if (await f.length() > 3 * 1024 * 1024) return null;
    return f.readAsBytes();
  }

  Future<bool> exists(String workId, {
    String mode = 'auto', int page = 1,
  }) async => (await _imageFile(workId, mode, page)).exists();

  Future<Uint8List> save(String workId, Uint8List original, {
    String mode = 'auto', int page = 1,
  }) async {
    if (original.isEmpty || original.length > 35 * 1024 * 1024) {
      throw const FormatException('표지 이미지는 최대 35MB까지 지원해.');
    }
    // Decode and scale down instead of persisting huge original images.
    final codec = await ui.instantiateImageCodec(original, targetWidth: 280);
    try {
      final frame = await codec.getNextFrame();
      try {
        final encoded = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (encoded == null) throw const FormatException('표지를 변환하지 못했어.');
        final data = encoded.buffer.asUint8List();
        final file = await _imageFile(workId, mode, page);
        await file.writeAsBytes(data, flush: true);
        return data;
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }
}
