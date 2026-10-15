import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/cover_similarity.dart';

Future<Uint8List> _cover() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 16, 16),
      ui.Paint()..color = const ui.Color(0xFF121212));
  canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 8, 16),
      ui.Paint()..color = const ui.Color(0xFFFFF0D0));
  final image = await recorder.endRecording().toImage(16, 16);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List(
        data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('same image has maximum perceptual cover similarity', () async {
    final bytes = await _cover();
    expect(await CoverSimilarity.compare(bytes, bytes), 1.0);
    expect(await CoverSimilarity.compare(bytes, Uint8List(0)), isNull);
  });
}
