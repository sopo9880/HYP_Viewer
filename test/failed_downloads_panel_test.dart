import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/download_failure_store.dart';
import 'package:hyp_viewer/l10n/app_localizations.dart';
import 'package:hyp_viewer/ui/failed_downloads_panel.dart';

void main() {
  testWidgets('individual X hides only the selected failure, Retry stays intact',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Map<String, FailedDownload> failures = {
      '3538281': const FailedDownload('3538281', 'hitomi', 'META_ID_MISMATCH'),
      '2711759': const FailedDownload('2711759', 'json', 'DOWNLOAD_FAILED'),
    };
    String? retried;
    String? dismissed;

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ko'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: SingleChildScrollView(child: StatefulBuilder(
        builder: (context, refresh) => FailedDownloadsPanel(
          failedDownloads: failures,
          onRetry: (id) async { retried = id; },
          onDismiss: (id) async {
            dismissed = id;
            refresh(() { failures = {...failures}..remove(id); });
          },
        ),
      ))),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('toggle-failed-downloads')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('failed-download-3538281')), findsOneWidget);
    expect(find.byKey(const Key('failed-download-2711759')), findsOneWidget);
    await tester.tap(find.byKey(const Key('retry-failed-3538281')));
    await tester.pump();
    expect(retried, '3538281');
    expect(dismissed, isNull);

    await tester.tap(find.byKey(const Key('dismiss-failed-3538281')));
    await tester.pumpAndSettle();
    expect(dismissed, '3538281');
    expect(find.byKey(const Key('failed-download-3538281')), findsNothing);
    expect(find.byKey(const Key('failed-download-2711759')), findsOneWidget);
  });

  testWidgets('Clear all requires confirmation and hides the whole panel',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Map<String, FailedDownload> failures = {
      '3538281': const FailedDownload('3538281', 'hitomi', 'META_ID_MISMATCH'),
      '2711759': const FailedDownload('2711759', 'json', 'DOWNLOAD_FAILED'),
    };
    var clearCount = 0;

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ko'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: SingleChildScrollView(child: StatefulBuilder(
        builder: (context, refresh) => FailedDownloadsPanel(
          failedDownloads: failures,
          onClearAll: () async {
            clearCount++;
            refresh(() { failures = {}; });
          },
        ),
      ))),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('failed-download-3538281')), findsOneWidget);

    await tester.tap(find.byKey(const Key('clear-all-failed-downloads')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(clearCount, 0);

    await tester.binding.handlePopRoute(); // Cancel via Android Back.
    await tester.pumpAndSettle();
    expect(clearCount, 0);
    expect(find.byKey(const Key('failed-download-3538281')), findsOneWidget);

    await tester.tap(find.byKey(const Key('clear-all-failed-downloads')));
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const Key('confirm-clear-all-failed-downloads')));
    await tester.pumpAndSettle();
    expect(clearCount, 1);
    expect(find.byKey(const Key('failed-download-3538281')), findsNothing);
    expect(find.byKey(const Key('failed-download-2711759')), findsNothing);
    expect(find.byKey(const Key('clear-all-failed-downloads')), findsNothing);
  });
}
