import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/gallery.dart';
import 'package:hyp_viewer/core/reader_settings.dart';
import 'package:hyp_viewer/core/work.dart';
import 'package:hyp_viewer/l10n/app_localizations.dart';
import 'package:hyp_viewer/ui/gallery_reader.dart';

class _Pages implements GalleryPageSource {
  static final Uint8List pixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91Jpz'
    'AAAAFklEQVR4nGP8//8/AwMDEwMDAwMDAwAkBgMB/DXemwAAAABJRU5ErkJggg==',
  );

  @override
  int get pageCount => 6;

  @override
  String filename(int index) => 'test_$index.png';

  @override
  Future<Uint8List> loadPage(int index) async => pixel;
}

Widget _app(ReaderSettings settings, {bool preview = false,
    ValueChanged<int>? onPageChanged}) => MaterialApp(
  locale: const Locale('ko'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: GalleryReader(
    work: WorkEntry.create(workId: '2711759').copyWith(currentPage: 3),
    archive: _Pages(),
    settings: settings,
    diskCacheEnabled: false,
    previewMode: preview,
    onPageChanged: onPageChanged ?? (_) {},
  ),
);

Future<void> _pinchOut(WidgetTester tester, Rect bounds) async {
  final center = bounds.center;
  final left = await tester.startGesture(
    center + const Offset(-25, 0), pointer: 31);
  final right = await tester.startGesture(
    center + const Offset(25, 0), pointer: 32);
  await tester.pump();
  await left.moveTo(center + const Offset(-110, 0));
  await right.moveTo(center + const Offset(110, 0));
  await tester.pump(const Duration(milliseconds: 70));
  await left.up();
  await right.up();
  await tester.pump(const Duration(milliseconds: 70));
}

Future<void> _doubleTap(WidgetTester tester, Offset point) async {
  await tester.tapAt(point);
  await tester.pump(const Duration(milliseconds: 55));
  await tester.tapAt(point);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('pinch and double tap reset in single, spread, vertical and preview',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1050, 810));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final mode in ['single', 'spread', 'vertical', 'preview']) {
      final changed = <int>[];
      final settings = ReaderSettings(
        preloadPages: 0,
        hideReaderUiOnOpen: false,
        twoPageSpread: mode == 'spread',
        verticalScrolling: mode == 'vertical',
      );
      await tester.pumpWidget(_app(settings,
          preview: mode == 'preview', onPageChanged: changed.add));
      await tester.pumpAndSettle();

      final zoom = find.byKey(const Key('reader-pinch-zoom'));
      expect(zoom, findsOneWidget, reason: mode);
      final view = tester.widget<InteractiveViewer>(zoom);
      final transform = view.transformationController!;
      final rect = tester.getRect(zoom);

      await _pinchOut(tester, rect);
      expect(transform.value.getMaxScaleOnAxis(), greaterThan(1.05),
          reason: '$mode must zoom with two fingers');
      expect(changed, isEmpty, reason: '$mode must not turn a page during pinch');

      await _doubleTap(tester, rect.center);
      expect(transform.value.getMaxScaleOnAxis(), closeTo(1, 0.001),
          reason: '$mode double tap resets zoom');
      expect(transform.value.getTranslation().length, lessThan(0.001),
          reason: '$mode double tap resets pan');
      expect(changed, isEmpty);
    }
  });

  testWidgets('webtoon continuous mode pinches and double tap resets',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1050, 810));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(const ReaderSettings(
      webtoonMode: true, preloadPages: 0, hideReaderUiOnOpen: false,
    )));
    await tester.pumpAndSettle();
    final iv = find.byType(InteractiveViewer);
    expect(iv, findsOneWidget);
    final view = tester.widget<InteractiveViewer>(iv);
    final transform = view.transformationController!;
    final rect = tester.getRect(iv);

    await _pinchOut(tester, rect);
    expect(transform.value.getMaxScaleOnAxis(), greaterThan(1.05));
    await _doubleTap(tester, rect.center);
    expect(transform.value.getMaxScaleOnAxis(), closeTo(1, 0.001));
    expect(transform.value.getTranslation().length, lessThan(0.001));
    expect(find.byKey(const Key('webtoon-continuous-reader')), findsOneWidget);
  });

  testWidgets('double tap at 1x never changes pages or toolbar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1050, 810));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pages = <int>[];
    await tester.pumpWidget(_app(const ReaderSettings(
      preloadPages: 0, hideReaderUiOnOpen: false,
    ), onPageChanged: pages.add));
    await tester.pumpAndSettle();
    final center = tester.getRect(find.byKey(
        const Key('reader-pinch-zoom'))).center;
    await _doubleTap(tester, center);
    expect(pages, isEmpty);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('3 / 6'), findsOneWidget);
  });
}
