import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/gallery.dart';
import 'package:hyp_viewer/core/reader_settings.dart';
import 'package:hyp_viewer/core/work.dart';
import 'package:hyp_viewer/l10n/app_localizations.dart';
import 'package:hyp_viewer/ui/gallery_reader.dart';

class _PreviewPage implements GalleryPageSource {
  @override
  int get pageCount => 1;

  @override
  String filename(int index) => 'one.png';

  @override
  Future<Uint8List> loadPage(int index) async => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91Jpz'
    'AAAAFklEQVR4nGP8//8/AwMDEwMDAwMDAwAkBgMB/DXemwAAAABJRU5ErkJggg==');
}

void main() {
  testWidgets('preview never completes, offers explicit save and block',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 840));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var saved = 0, blocked = 0;
    final completed = <int>[];
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: GalleryReader(
        work: WorkEntry.create(workId: '1234567'),
        archive: _PreviewPage(), diskCacheEnabled: false,
        previewMode: true,
        settings: const ReaderSettings(hideReaderUiOnOpen: true,
            confirmCompleteOnNext: false, preloadPages: 0),
        onPageChanged: (_) {},
        onFinishedReading: completed.add,
        onSavePreview: () async { saved++; return true; },
        onBlockPreview: () async { blocked++; },
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byKey(const Key('preview-save-to-library')), findsOneWidget);
    expect(completed, isEmpty);
    await tester.tap(find.byKey(const Key('preview-save-to-library')));
    await tester.pumpAndSettle();
    expect(saved, 1);
    expect(find.byIcon(Icons.bookmark_added), findsOneWidget);
    expect(completed, isEmpty);
    await tester.tap(find.byKey(const Key('preview-blacklist')));
    await tester.pumpAndSettle();
    expect(blocked, 1);
    expect(completed, isEmpty);
  });
}
