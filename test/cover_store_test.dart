import 'dart:ui' as ui;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/cover_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('writes scaled thumbnails to separate automatic and page files', () async {
    final dir = await Directory.systemTemp.createTemp('hyp-cover-');
    addTearDown(() => dir.delete(recursive: true));
    final images = const CoverStore().baseDirectory; // default is null
    expect(images, isNull);

    final store = CoverStore(baseDirectory: dir);
    // Generate an actual valid PNG instead of relying on a tiny fixture
    // that may be rejected by the Flutter engine on Windows/Linux.
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2),
        ui.Paint()..color = const ui.Color(0xFF925BFF));
    final picture = recorder.endRecording();
    final image = await picture.toImage(2, 2);
    final raw = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    final bytes = raw!.buffer.asUint8List();
    final first = await store.save('2711759', bytes);
    final chosen = await store.save('2711759', bytes,
        mode: 'page', page: 7);
    expect(first, isNotEmpty);
    expect(chosen, isNotEmpty);
    expect(await store.read('2711759'), isNotNull);
    expect(await store.read('2711759', mode: 'page', page: 7), isNotNull);
    expect(await store.read('2711759', mode: 'page', page: 8), isNull);
    expect(await store.read('2711759', mode: 'preset'), isNull);
  });
}
