import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/online_reader_failure.dart';
import 'package:hyp_viewer/l10n/app_localizations.dart';
import 'package:hyp_viewer/ui/online_reader_error_dialog.dart';

void main() {
  testWidgets('dialog shows accurate metadata failure and copies safe report',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null));
    final failure = OnlineReaderFailure(
      code: 'META_FILES_MISSING', stage: OnlineReaderStage.metadata,
      workId: '2711759', httpStatus: 200,
      host: 'ltn.gold-usergeneratedcontent.net',
      description: 'SECRET_NOT_ALLOWED',
    );
    OnlineReaderErrorAction? result;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Builder(builder: (context) => Center(
        child: FilledButton(
          onPressed: () async {
            result = await showOnlineReaderErrorDialog(context, failure);
          },
          child: const Text('Open'),
        ),
      ))),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('online-reader-failure-dialog')), findsOneWidget);
    expect(find.textContaining('META_FILES_MISSING'), findsOneWidget);
    expect(find.textContaining('HTTP 200'), findsOneWidget);
    expect(find.textContaining('이미지 목록'), findsOneWidget);
    await tester.tap(find.byKey(const Key('online-reader-copy-diagnostic')));
    await tester.pumpAndSettle();
    expect(copied, contains('META_FILES_MISSING'));
    expect(copied, contains('2711759'));
    expect(copied, isNot(contains('SECRET_NOT_ALLOWED')));
    await tester.tap(find.byKey(const Key('online-reader-retry')));
    await tester.pumpAndSettle();
    expect(result, OnlineReaderErrorAction.retry);
  });

  testWidgets('web reader action is distinguishable from retry',
      (tester) async {
    final failure = OnlineReaderFailure(
      code: 'META_ID_MISMATCH', stage: OnlineReaderStage.metadata,
      workId: '2711759', httpStatus: 200,
      description: 'ID mismatch',
    );
    OnlineReaderErrorAction? result;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () async {
          result = await showOnlineReaderErrorDialog(context, failure);
        },
        child: const Text('Open'),
      ))),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('online-reader-open-web')));
    await tester.pumpAndSettle();
    expect(result, OnlineReaderErrorAction.web);
  });
}
