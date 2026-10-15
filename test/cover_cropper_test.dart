import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hyp_viewer/l10n/app_localizations.dart';
import 'package:hyp_viewer/ui/cover_cropper.dart';

Future<Uint8List> _testPng() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 24, 24),
      ui.Paint()..color = const ui.Color(0xFF24B0F2));
  final picture = recorder.endRecording();
  final image = await picture.toImage(24, 24);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List png;
  // Picture.toImage is an engine async operation. Preparing it inside a
  // testWidgets fake-async zone deadlocks before the first frame is pumped.
  setUpAll(() async {
    png = await _testPng();
  });

  testWidgets('cropping returns exactly an image preview, not raw source',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Uint8List? cropped;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko'), Locale('en'), Locale('ja')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: Builder(builder: (context) => ElevatedButton(
        onPressed: () async { cropped = await showCoverCropper(context, png); },
        child: const Text('표지 자르기 열기'),
      ))),
    ));
    await tester.tap(find.text('표지 자르기 열기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cover-crop-zoom')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('cover-crop-save')));
    await tester.tap(find.byKey(const Key('cover-crop-save')));
    await tester.pumpAndSettle();
    // RenderRepaintBoundary.toImage uses the real engine asynchronous image
    // rasterization, which may finish after pumpAndSettle's fake-async frames.
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 24 && cropped == null; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    });
    await tester.pumpAndSettle();
    expect(cropped, isNotNull);
    expect(cropped!.length, greaterThan(100));
    expect(cropped!.sublist(0, 4), [137, 80, 78, 71]);
  });
}
