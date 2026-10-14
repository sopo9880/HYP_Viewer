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
  testWidgets('Space hides full UI and Space restores it', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: GalleryReader(
        work: WorkEntry.create(workId: '2711759'),
        archive: _Pages(), diskCacheEnabled: false,
        settings: const ReaderSettings(preloadPages: 0),
        onPageChanged: (_) {},
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing);
    expect(find.byKey(const Key('reader-next')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets('final page successfully decoding marks the work completed',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final completed = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: GalleryReader(
        work: WorkEntry.create(workId: '2711759').copyWith(currentPage: 5),
        archive: _Pages(), diskCacheEnabled: false,
        settings: const ReaderSettings(preloadPages: 0),
        onPageChanged: (_) {},
        onFinishedReading: completed.add,
      ),
    ));
    await tester.pumpAndSettle();
    expect(completed, [5]);
  });

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
        diskCacheEnabled: false,
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

  testWidgets('RTL reverses bottom controls and slider, toolbar toggle persists',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1120, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final changes = <bool>[];
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: GalleryReader(
        work: WorkEntry.create(workId: '2711759'),
        archive: _Pages(),
        diskCacheEnabled: false,
        settings: const ReaderSettings(nextDirection: 'right'),
        onPageChanged: (_) {},
        onVerticalScrollingChanged: changes.add,
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const Key('reader-next'))).dx,
        lessThan(tester.getTopLeft(
            find.byKey(const Key('reader-previous'))).dx));
    expect(Directionality.of(tester.element(find.byType(Slider))),
        TextDirection.rtl);
    // Switching to vertical reading must keep next BELOW/forward, not RTL.
    await tester.tap(find.byTooltip('세로 넘기기'));
    await tester.pumpAndSettle();
    expect(changes, [true]);
    expect(find.byTooltip('가로 넘기기'), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const Key('reader-next'))).dx,
        greaterThan(tester.getTopLeft(
            find.byKey(const Key('reader-previous'))).dx));
    expect(Directionality.of(tester.element(find.byType(Slider))),
        TextDirection.ltr);
  });

  testWidgets('viewer upper-right toolbar visibility follows settings',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: GalleryReader(
        work: WorkEntry.create(workId: '2711759'),
        archive: _Pages(),
        diskCacheEnabled: false,
        settings: const ReaderSettings(
          showPageControlsAction: false,
          showOrientationAction: false,
          showCoverAction: false,
          showWebReaderAction: false,
        ),
        onPageChanged: (_) {},
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byTooltip('페이지 도구 숨기기'), findsNothing);
    expect(find.byTooltip('세로 넘기기'), findsNothing);
    expect(find.byKey(const Key('reader-next')), findsOneWidget);
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
        diskCacheEnabled: false,
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
