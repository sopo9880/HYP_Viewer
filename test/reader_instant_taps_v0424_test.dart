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
  String filename(int index) => 'page_' + index.toString() + '.png';

  @override
  Future<Uint8List> loadPage(int index) async => pixel;
}

Widget _app(String mode, ValueChanged<int> onPageChanged) => MaterialApp(
  key: ValueKey('app-' + mode),
  locale: const Locale('ko'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: GalleryReader(
    key: ValueKey('reader-' + mode),
    work: WorkEntry.create(workId: '2711759').copyWith(currentPage: 3),
    archive: _Pages(),
    settings: ReaderSettings(
      hideReaderUiOnOpen: mode == 'webtoon',
      preloadPages: 0,
      twoPageSpread: mode == 'spread',
      verticalScrolling: mode == 'vertical',
      webtoonMode: mode == 'webtoon',
    ),
    previewMode: mode == 'preview',
    diskCacheEnabled: false,
    onPageChanged: onPageChanged,
  ),
);

void main() {
  testWidgets('1x edge taps complete their page turn before old 310ms delay',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1050, 810));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final mode in ['single', 'spread', 'vertical', 'preview']) {
      final pages = <int>[];
      await tester.pumpWidget(_app(mode, pages.add));
      await tester.pumpAndSettle();

      final zone = tester.getRect(
          find.byKey(const Key('reader-tap-zones')));
      await tester.tapAt(Offset(
          zone.left + zone.width * 0.85, zone.center.dy));
      await tester.pump(); // begin the unchanged 180ms page animation
      await tester.pump(const Duration(milliseconds: 230));

      final expected = mode == 'spread' ? 5 : 4;
      expect(find.text(expected.toString() + ' / 6'), findsOneWidget,
          reason: mode + ' must not wait for double-tap detection at 1x');
      expect(pages, isNotEmpty, reason: mode);
      expect(pages.last, expected, reason: mode);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('1x webtoon center click reveals controls immediately',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1050, 810));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app('webtoon', (_) {}));
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsNothing);
    final area = tester.getRect(
        find.byKey(const Key('webtoon-continuous-reader')));
    await tester.tapAt(area.center);
    await tester.pump();
    expect(find.byType(AppBar), findsOneWidget);
  });
}
