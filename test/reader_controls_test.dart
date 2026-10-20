import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/gallery.dart';
import 'package:hyp_viewer/core/reader_settings.dart';
import 'package:hyp_viewer/core/work.dart';
import 'package:hyp_viewer/l10n/app_localizations.dart';
import 'package:hyp_viewer/ui/gallery_reader.dart';

class _Pages implements GalleryPageSource {
  final List<int> requested = [];
  static final Uint8List pixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91Jpz'
    'AAAAFklEQVR4nGP8//8/AwMDEwMDAwMDAwAkBgMB/DXemwAAAABJRU5ErkJggg==',
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


Widget _localizedApp({required Widget home, ThemeData? theme, Key? key}) =>
    MaterialApp(
      key: key,
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: theme,
      home: home,
    );

void main() {

  testWidgets('reader enters hidden and tapping center reveals the toolbar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_localizedApp(
      home: GalleryReader(
        work: WorkEntry.create(workId: '2711759'),
        archive: _Pages(), diskCacheEnabled: false,
        settings: const ReaderSettings(preloadPages: 0),
        onPageChanged: (_) {},
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing);
    expect(find.byKey(const Key('reader-next')), findsNothing);
    final zone = tester.getRect(find.byKey(const Key('reader-tap-zones')));
    await tester.tapAt(zone.center);
    // Reader taps wait briefly to distinguish a single tap from a
    // double tap that must reset zoom without changing the toolbar.
    await tester.pump(const Duration(milliseconds: 330));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byKey(const Key('reader-toggle-spread')), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off), findsNothing);
  });

  testWidgets('reader spread toolbar toggle preserves the current page',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final changes = <bool>[];
    await tester.pumpWidget(_localizedApp(
      home: GalleryReader(
        work: WorkEntry.create(workId: '2711759').copyWith(currentPage: 3),
        archive: _Pages(), diskCacheEnabled: false,
        settings: const ReaderSettings(
            preloadPages: 0, hideReaderUiOnOpen: false),
        onPageChanged: (_) {},
        onTwoPageSpreadChanged: changes.add,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('3 / 5'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reader-toggle-spread')));
    await tester.pumpAndSettle();
    expect(changes, [true]);
    expect(find.text('3 / 5'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reader-toggle-spread')));
    await tester.pumpAndSettle();
    expect(changes, [true, false]);
    expect(find.text('3 / 5'), findsOneWidget);
  });
  testWidgets('Space hides full UI and Space restores it', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_localizedApp(
      home: GalleryReader(
        work: WorkEntry.create(workId: '2711759'),
        archive: _Pages(), diskCacheEnabled: false,
        settings: const ReaderSettings(hideReaderUiOnOpen: false, preloadPages: 0),
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
    await tester.pumpWidget(_localizedApp(
      home: GalleryReader(
        work: WorkEntry.create(workId: '2711759').copyWith(currentPage: 5),
        archive: _Pages(), diskCacheEnabled: false,
        settings: const ReaderSettings(
            hideReaderUiOnOpen: false, preloadPages: 0,
            confirmCompleteOnNext: false),
        onPageChanged: (_) {},
        onFinishedReading: completed.add,
      ),
    ));
    await tester.pumpAndSettle();
    // Image codecs can finish after the last scheduled widget animation.
    for (var i = 0; i < 5 && completed.isEmpty; i++) {
      await tester.runAsync(() async =>
          Future<void>.delayed(const Duration(milliseconds: 45)));
      await tester.pump();
    }
    expect(completed, [5]);
  });

  testWidgets('last page requires explicit NEXT and supports keep reading',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final completed = <int>[];
    await tester.pumpWidget(_localizedApp(home: GalleryReader(
      work: WorkEntry.create(workId: '2711759').copyWith(currentPage: 5),
      archive: _Pages(), diskCacheEnabled: false,
      settings: const ReaderSettings(hideReaderUiOnOpen: false, preloadPages: 0),
      onPageChanged: (_) {}, onFinishedReading: completed.add,
    )));
    await tester.pumpAndSettle();
    // Give asynchronous frame decoding the same chance as the legacy test.
    await tester.runAsync(() async =>
        Future<void>.delayed(const Duration(milliseconds: 90)));
    await tester.pumpAndSettle();
    expect(completed, isEmpty); // reaching final image never auto-completes
    await tester.tap(find.byKey(const Key('reader-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-finish-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('reader-keep-reading')));
    await tester.pumpAndSettle();
    expect(completed, isEmpty);
    await tester.tap(find.byKey(const Key('reader-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader-finish-and-exit')));
    await tester.pumpAndSettle();
    expect(completed, [5]);
  });

  testWidgets('two-page spread final next can exit without completing',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final completed = <int>[];
    await tester.pumpWidget(_localizedApp(home: GalleryReader(
      work: WorkEntry.create(workId: '2711759').copyWith(currentPage: 5),
      archive: _Pages(), diskCacheEnabled: false,
      settings: const ReaderSettings(hideReaderUiOnOpen: false,
          preloadPages: 0, twoPageSpread: true),
      onPageChanged: (_) {}, onFinishedReading: completed.add,
    )));
    await tester.pumpAndSettle();
    await tester.runAsync(() async =>
        Future<void>.delayed(const Duration(milliseconds: 90)));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-finish-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('reader-exit-incomplete')));
    await tester.pumpAndSettle();
    expect(completed, isEmpty);
  });

  testWidgets('side taps navigate toward physical direction for both settings',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final rtl in [false, true]) {
      final pages = _Pages();
      await tester.pumpWidget(_localizedApp(
        key: ValueKey('direction-$rtl'),
        home: GalleryReader(
          key: ValueKey('tap-reader-$rtl'),
          work: WorkEntry.create(workId: '2711759').copyWith(currentPage: 3),
          archive: pages, diskCacheEnabled: false,
          settings: ReaderSettings(hideReaderUiOnOpen: false, preloadPages: 0,
              nextDirection: rtl ? 'right' : 'left'),
          onPageChanged: (_) {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('3 / 5'), findsOneWidget);
      final rect = tester.getRect(find.byKey(const Key('reader-tap-zones')));
      await tester.tapAt(Offset(rect.left + rect.width * 0.15,
          rect.top + rect.height * 0.5));
      await tester.pump(const Duration(milliseconds: 330));
      await tester.pumpAndSettle();
      // Default LTR: tapping the physical left edge goes backward.
      // RTL reverses the direction, so the left edge advances.
      expect(find.text(rtl ? '4 / 5' : '2 / 5'), findsOneWidget);
      await tester.tapAt(Offset(rect.left + rect.width * 0.85,
          rect.top + rect.height * 0.5));
      await tester.pump(const Duration(milliseconds: 330));
      await tester.pumpAndSettle();
      expect(find.text('3 / 5'), findsOneWidget);
    }
  });

  testWidgets('preloads both directions and has physical previous button',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pages = _Pages();
    await tester.pumpWidget(_localizedApp(
      theme: ThemeData.dark(),
      home: GalleryReader(
        work: WorkEntry.create(workId: '2711759').copyWith(currentPage: 2),
        archive: pages,
        diskCacheEnabled: false,
        settings: const ReaderSettings(hideReaderUiOnOpen: false, preloadPages: 2),
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
    await tester.pumpWidget(_localizedApp(
      theme: ThemeData.dark(),
      home: GalleryReader(
        work: WorkEntry.create(workId: '2711759'),
        archive: _Pages(),
        diskCacheEnabled: false,
        settings: const ReaderSettings(hideReaderUiOnOpen: false, nextDirection: 'right'),
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
    await tester.pumpWidget(_localizedApp(
      theme: ThemeData.dark(),
      home: GalleryReader(
        work: WorkEntry.create(workId: '2711759'),
        archive: _Pages(),
        diskCacheEnabled: false,
        settings: const ReaderSettings(hideReaderUiOnOpen: false, 
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
    await tester.pumpWidget(_localizedApp(
      theme: ThemeData.dark(),
      home: GalleryReader(
        work: WorkEntry.create(workId: '2711759'),
        archive: pages,
        diskCacheEnabled: false,
        settings: const ReaderSettings(hideReaderUiOnOpen: false, 
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
  testWidgets('restart action appears above continue and rewinds all viewer modes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final mode in ['normal', 'spread', 'webtoon']) {
      final completed = <int>[];
      final readPages = <int>[];
      final settings = ReaderSettings(
        hideReaderUiOnOpen: false,
        preloadPages: 0,
        twoPageSpread: mode == 'spread',
        webtoonMode: mode == 'webtoon',
      );
      await tester.pumpWidget(_localizedApp(
        key: ValueKey('restart-$mode'),
        home: GalleryReader(
          key: ValueKey('reader-$mode'),
          work: WorkEntry.create(workId: '2711759')
              .copyWith(currentPage: 5),
          archive: _Pages(),
          diskCacheEnabled: false,
          settings: settings,
          onPageChanged: readPages.add,
          onFinishedReading: completed.add,
        ),
      ));
      await tester.pumpAndSettle();
      // Match the image decoder's asynchronous end-frame timing.
      await tester.runAsync(() async =>
          Future<void>.delayed(const Duration(milliseconds: 90)));
      await tester.pumpAndSettle();

      expect(find.text('5 / 5'), findsOneWidget);
      await tester.tap(find.byKey(const Key('reader-next')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reader-finish-dialog')), findsOneWidget,
          reason: '$mode did not open the completion dialog');
      final restart = find.byKey(const Key('reader-restart-from-first'));
      final keepReading = find.byKey(const Key('reader-keep-reading'));
      expect(find.text('처음으로'), findsOneWidget);
      expect(tester.getTopLeft(restart).dy,
          lessThan(tester.getTopLeft(keepReading).dy));

      await tester.tap(restart);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reader-finish-dialog')), findsNothing);
      expect(find.text('1 / 5'), findsOneWidget,
          reason: '$mode must rewind to the first page');
      expect(readPages.last, 1);
      expect(completed, isEmpty,
          reason: 'Restarting must never flag the work completed');
    }
  });

  testWidgets('restart can revisit the end without silently completing',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final completed = <int>[];
    await tester.pumpWidget(_localizedApp(
      home: GalleryReader(
        work: WorkEntry.create(workId: '2711759')
            .copyWith(currentPage: 5),
        archive: _Pages(), diskCacheEnabled: false,
        settings: const ReaderSettings(
          hideReaderUiOnOpen: false, preloadPages: 0,
        ),
        onPageChanged: (_) {},
        onFinishedReading: completed.add,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.runAsync(() async =>
        Future<void>.delayed(const Duration(milliseconds: 90)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reader-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader-restart-from-first')));
    await tester.pumpAndSettle();
    expect(completed, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(find.text('5 / 5'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reader-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-finish-dialog')), findsOneWidget);
    expect(completed, isEmpty);
  });

}
