import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/gallery.dart';
import 'package:hyp_viewer/core/reader_settings.dart';
import 'package:hyp_viewer/core/work.dart';
import 'package:hyp_viewer/ui/gallery_reader.dart';

class _Pages implements GalleryPageSource {
  final List<int> requested = [];
  static final Uint8List pixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
    'AAAADUlEQVQIHWP4z8DwHwAFgAI/ScLytQAAAABJRU5ErkJggg==',
  );

  @override
  int get pageCount => 5;

  @override
  String filename(int index) => 'test_$index.png';

  @override
  Future<Uint8List> loadPage(int index) async {
    requested.add(index);
    return pixel;
  }
}

void main() {
  testWidgets('preloads both directions and has physical previous button',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pages = _Pages();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: GalleryReader(
        work: WorkEntry.create(workId: '2711759').copyWith(currentPage: 2),
        archive: pages,
        settings: const ReaderSettings(preloadPages: 2),
        onPageChanged: (_) {},
      ),
    ));
    await tester.pumpAndSettle();
    expect(pages.requested, containsAll([0, 1, 2, 3]));
    expect(find.text('2 / 5'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reader-previous')));
    await tester.pumpAndSettle();
    expect(find.text('1 / 5'), findsOneWidget);
  });

  testWidgets('two-page spread turns by pairs and keyboard works in RTL',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pages = _Pages();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: GalleryReader(
        work: WorkEntry.create(workId: '2711759'),
        archive: pages,
        settings: const ReaderSettings(
            nextDirection: 'right', twoPageSpread: true, preloadPages: 1),
        onPageChanged: (_) {},
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('1 / 5'), findsOneWidget);
    // In right-to-left mode, a left arrow advances.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('3 / 5'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pumpAndSettle();
    expect(find.text('1 / 5'), findsOneWidget);
  });
}
