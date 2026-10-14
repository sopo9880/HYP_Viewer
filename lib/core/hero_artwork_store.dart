import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Device-local artwork for the FIRST home banner slide. This is deliberately
/// outside the JSON library export, just like locally generated covers.
class HeroArtworkStore {
  final Directory? baseDirectory;
  const HeroArtworkStore({this.baseDirectory});

  static const maxBytes = 12 * 1024 * 1024;

  Future<File> get _file async {
    final root = baseDirectory ?? await getApplicationSupportDirectory();
    await root.create(recursive: true);
    return File(root.path + Platform.pathSeparator + 'hero_artwork.bin');
  }

  static bool isSupportedImage(Uint8List bytes) {
    if (bytes.length < 12 || bytes.length > maxBytes) return false;
    const png = [137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length >= 8 &&
        List.generate(8, (i) => bytes[i] == png[i]).every((yes) => yes)) {
      return true;
    }
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return true;
    }
    return String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
  }

  Future<Uint8List?> read() async {
    final f = await _file;
    if (!await f.exists() || await f.length() > maxBytes) return null;
    final bytes = await f.readAsBytes();
    return isSupportedImage(bytes) ? bytes : null;
  }

  Future<void> save(Uint8List bytes) async {
    if (!isSupportedImage(bytes)) {
      throw const FormatException('PNG, JPG, WebP 이미지만 지원해 (최대 12MB).');
    }
    await (await _file).writeAsBytes(bytes, flush: true);
  }

  Future<void> clear() async {
    final f = await _file;
    if (await f.exists()) await f.delete();
  }
}
