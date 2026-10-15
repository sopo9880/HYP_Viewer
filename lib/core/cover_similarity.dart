import 'dart:typed_data';
import 'dart:ui' as ui;

/// Compare candidate cover images after the metadata/chapter filter narrows
/// the search. An unavailable/corrupt cover is "unknown", never "different".
/// This is advisory evidence only: never auto-link based on covers alone.
abstract final class CoverSimilarity {
  static Future<double?> compare(Uint8List a, Uint8List b) async {
    final left = await _signature(a);
    final right = await _signature(b);
    if (left == null || right == null) return null;
    var differences = 0;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) differences++;
    }
    return 1 - differences / left.length;
  }

  static Future<List<bool>?> _signature(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 12 * 1024 * 1024) return null;
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(bytes,
          targetWidth: 16, targetHeight: 16);
      image = (await codec.getNextFrame()).image;
      final frame = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (frame == null || frame.lengthInBytes < 16 * 16 * 4) return null;
      final data = frame.buffer.asUint8List(
          frame.offsetInBytes, frame.lengthInBytes);
      final gray = <double>[];
      for (var i = 0; i < 16 * 16 * 4; i += 4) {
        final alpha = data[i + 3] / 255;
        final luminous = data[i] * .2126 + data[i + 1] * .7152 +
            data[i + 2] * .0722;
        gray.add(luminous * alpha + 255 * (1 - alpha));
      }
      final avg = gray.reduce((a, b) => a + b) / gray.length;
      return gray.map((value) => value >= avg).toList();
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }
}
