import 'dart:typed_data';
import 'dart:ui' as ui;

/// A bounded on-device visual fingerprint; never evidence of definite identity.
class VisualSignature {
  final String pattern;
  final int red, green, blue;
  const VisualSignature(this.pattern, this.red, this.green, this.blue);

  Map<String, Object> toJson() => {
    'pattern': pattern, 'red': red, 'green': green, 'blue': blue,
  };

  static VisualSignature? fromJson(dynamic data) {
    if (data is! Map || data['pattern'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(data['pattern'] as String)) {
      return null;
    }
    if (data['red'] is! int || data['green'] is! int ||
        data['blue'] is! int) return null;
    final r = data['red'] as int, g = data['green'] as int,
        b = data['blue'] as int;
    if (r < 0 || r > 255 || g < 0 || g > 255 || b < 0 || b > 255) {
      return null;
    }
    return VisualSignature(data['pattern'] as String, r, g, b);
  }

  static Future<VisualSignature?> fromImage(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 16 * 1024 * 1024) return null;
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(bytes,
          targetWidth: 16, targetHeight: 16);
      image = (await codec.getNextFrame()).image;
      final buffer = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (buffer == null || buffer.lengthInBytes < 16 * 16 * 4) return null;
      final rgba = buffer.buffer.asUint8List(
          buffer.offsetInBytes, buffer.lengthInBytes);
      final light = <double>[];
      var r = 0.0, g = 0.0, b = 0.0;
      for (var i = 0; i < 256; i++) {
        final start = i * 4;
        final alpha = rgba[start + 3] / 255;
        final cr = rgba[start] * alpha + 255 * (1 - alpha);
        final cg = rgba[start + 1] * alpha + 255 * (1 - alpha);
        final cb = rgba[start + 2] * alpha + 255 * (1 - alpha);
        r += cr; g += cg; b += cb;
        light.add(cr * 0.2126 + cg * 0.7152 + cb * 0.0722);
      }
      final avg = light.reduce((a, b) => a + b) / 256;
      final encoded = StringBuffer();
      for (var i = 0; i < 256; i += 4) {
        var nibble = 0;
        for (var j = 0; j < 4; j++) {
          nibble = (nibble << 1) | (light[i + j] >= avg ? 1 : 0);
        }
        encoded.write(nibble.toRadixString(16));
      }
      return VisualSignature(encoded.toString(),
          (r / 256).round(), (g / 256).round(), (b / 256).round());
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  static const _popcount = <int>[0, 1, 1, 2, 1, 2, 2, 3,
    1, 2, 2, 3, 2, 3, 3, 4];

  double similarity(VisualSignature other) {
    if (pattern.length != 64 || other.pattern.length != 64) return 0;
    var distance = 0;
    for (var i = 0; i < 64; i++) {
      final a = int.tryParse(pattern[i], radix: 16);
      final b = int.tryParse(other.pattern[i], radix: 16);
      if (a == null || b == null) return 0;
      distance += _popcount[a ^ b];
    }
    final shape = 1 - distance / 256;
    final color = 1 - ((red - other.red).abs() +
        (green - other.green).abs() + (blue - other.blue).abs()) / 765;
    return (0.8 * shape + 0.2 * color).clamp(0.0, 1.0);
  }
}
