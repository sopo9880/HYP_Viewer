import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/gallery.dart';
import 'package:hyp_viewer/core/reader_settings.dart';
import 'package:hyp_viewer/core/work.dart';
import 'package:hyp_viewer/ui/gallery_reader.dart';

class _FailingGallery implements GalleryPageSource {
  int attempts = 0;

  @override
  int get pageCount => 32;

  @override
  String filename(int index) => 'page_$index.webp';

  @override
  Future<Uint8List> loadPage(int index) async {
    attempts++;
    throw const FormatException('HTTP 404 from image server');
  }
}

void main() {
  testWidgets('shows actionable error instead of a blank reader', (tester) async {
    final archive = _FailingGallery();
    int? browserPage;
    var downloadRequests = 0;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: GalleryReader(
        work: WorkEntry.create(workId: '2711759'),
        archive: archive,
        diskCacheEnabled: false,
        settings: const ReaderSettings(preloadPages: 0),
        onPageChanged: (_) {},
        onOpenInBrowser: (page) async { browserPage = page; },
        onDownloadOffline: () async { downloadRequests++; },
      ),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('1 / 32'), findsOneWidget);
    // Regression: previously the unconstrained Slider covered the page
    // and appeared in the center of the entire window.
    expect(tester.getCenter(find.byType(Slider)).dy, greaterThan(400));
    expect(find.textContaining('1페이지를 불러오지 못했어.'), findsOneWidget);
    expect(find.textContaining('HTTP 404'), findsOneWidget);
    expect(find.byKey(const Key('reader-download-offline')), findsOneWidget);
    await tester.tap(find.byKey(const Key('reader-download-offline')));
    await tester.pump();
    expect(downloadRequests, 1);
    expect(find.byKey(const Key('reader-retry-page')), findsOneWidget);
    expect(find.byKey(const Key('reader-web-fallback')), findsOneWidget);
    expect(archive.attempts, 1);

    await tester.tap(find.byKey(const Key('reader-retry-page')));
    await tester.pump();
    await tester.pump();
    expect(archive.attempts, 2);

    await tester.tap(find.byKey(const Key('reader-web-fallback')));
    await tester.pump();
    expect(browserPage, 1);
  });
}
