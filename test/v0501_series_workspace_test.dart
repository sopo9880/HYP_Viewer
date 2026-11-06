import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/viewer_mode.dart';
import 'package:hyp_viewer/core/web_series_capture.dart';
import 'package:hyp_viewer/core/web_viewer_store.dart';
import 'package:hyp_viewer/l10n/app_localizations.dart';
import 'package:hyp_viewer/ui/series_viewer_pages.dart';

WebSeriesCapture _series() => WebSeriesCapture.parse(jsonEncode({
  'url': 'https://example.org/series/12',
  'title': 'Test series',
  'episodes': [
    {'url': '/series/12/chapter-3', 'title': '3화', 'order': 3},
    {'url': '/series/12/chapter-2', 'title': '2화', 'order': 2},
    {'url': '/series/12/chapter-1', 'title': '1화', 'order': 1},
  ],
}))!;

void main() {
  test('HYP has original pages; WEB and SERIES have independent routing', () {
    expect(ViewerMode.hyp.title, 'HYP Viewer');
    expect(ViewerMode.web.title, 'WEB Viewer');
    expect(ViewerMode.series.title, 'SERIES Viewer');
    expect(ViewerMode.hyp.pages, [
      'home', 'library', 'favorites', 'downloads', 'history', 'settings',
    ]);
    expect(ViewerMode.web.pages, [
      'home', 'favorites', 'library', 'downloads', 'settings',
    ]);
    expect(ViewerMode.series.pages, [
      'home', 'library', 'downloads', 'settings',
    ]);
    expect(ViewerMode.series.mobilePages, [
      'home', 'library', 'downloads', 'settings',
    ]);
    expect(ViewerMode.web.initialPage, 'favorites');
    expect(ViewerMode.series.initialPage, 'home');
    expect(ViewerMode.series.containsPage('favorites'), isFalse);
    expect(ViewerMode.series.containsPage('history'), isFalse);
    expect(ViewerMode.web.containsPage('favorites'), isTrue);
    expect(ViewerMode.hyp.containsPage('history'), isTrue);
    expect(ViewerMode.web.contentSection('favorites'), 'web');
    expect(ViewerMode.web.contentSection('library'), 'library');
    expect(ViewerMode.series.contentSection('home'), 'series_home');
    expect(ViewerMode.series.contentSection('library'), 'series_library');
    expect(ViewerMode.series.contentSection('downloads'), 'series_downloads');
    expect(ViewerMode.series.contentSection('settings'), 'series_settings');
  });

  test('SERIES settings persist independently and change queue order',
      () async {
    final dir = await Directory.systemTemp.createTemp('series-mode-test-');
    try {
      final store = WebViewerStore(baseDirectory: dir);
      final capture = _series();
      await store.saveSeries(capture);
      await store.queueSeriesEpisodes(capture.url.toString(),
          capture.episodes.map((e) => e.url.toString()));
      expect(store.nextSeriesEpisode(capture.url.toString())?.number, 1);
      await store.setSeriesOldestFirst(false);
      expect(store.nextSeriesEpisode(capture.url.toString())?.number, 3);
      await store.setSeriesSelectUnsaved(false);
      await store.setSeriesHideCompleted(true);
      expect(store.autoSelectImages, isTrue);
      store.dispose();
      final reopened = WebViewerStore(baseDirectory: dir);
      await reopened.load();
      expect(reopened.seriesOldestFirst, isFalse);
      expect(reopened.seriesSelectUnsaved, isFalse);
      expect(reopened.seriesHideCompleted, isTrue);
      expect(reopened.autoSelectImages, isTrue);
      expect(reopened.nextSeriesEpisode(capture.url.toString())?.number, 3);
      expect(reopened.works, isEmpty);
      reopened.dispose();
    } finally {
      await dir.delete(recursive: true);
    }
  });

  testWidgets('SERIES mode renders its four localized independent pages',
      (tester) async {
    // Widget tests run under fake async: avoid real file-system awaits here.
    // SERIES page rendering uses empty in-memory data and does not load files.
    final store = WebViewerStore();
    addTearDown(store.dispose);
    Widget screen(String section) => MaterialApp(
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(
        child: SeriesViewerPages(
          store: store,
          section: section,
          onOpenSeries: (_) {},
          onReadWork: (_) {},
          onOpenSeriesSource: (_) {},
          onOpenEpisodeSource: (_) {},
          onError: (_) {},
        ),
      )),
    );
    await tester.pumpWidget(screen('series_home'));
    await tester.pumpAndSettle();
    expect(find.text('등록한 시리즈: 0'), findsOneWidget);
    await tester.pumpWidget(screen('series_library'));
    await tester.pumpAndSettle();
    expect(find.textContaining('아직 등록한 시리즈가 없어'), findsOneWidget);
    await tester.pumpWidget(screen('series_downloads'));
    await tester.pumpAndSettle();
    expect(find.text('진행 중이거나 확인이 필요한 시리즈 다운로드가 없어.'),
      findsOneWidget);
    await tester.pumpWidget(screen('series_settings'));
    await tester.pumpAndSettle();
    expect(find.text('오래된 회차부터 다운로드'), findsOneWidget);
    expect(find.text('미저장 회차 기본 선택'), findsOneWidget);
    expect(find.text('저장 완료 회차 숨기기'), findsOneWidget);
  });
}
