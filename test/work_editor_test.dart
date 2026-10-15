import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hyp_viewer/l10n/app_localizations.dart';
import 'package:hyp_viewer/core/candidate_verifier.dart';
import 'package:hyp_viewer/core/work.dart';
import 'package:hyp_viewer/ui/work_editor.dart';

void main() {
  testWidgets('editing a mistaken ID retains typed title until explicitly changed',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 930));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    WorkEditDraft? saved;
    final work = WorkEntry.create(
        workId: '23172801', title: 'My custom title', author: 'Author');
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ko'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ko'), Locale('en'), Locale('ja')],
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () async {
          saved = await showDialog<WorkEditDraft>(
            context: context, builder: (ctx) => WorkEditorDialog(
              work: work,
              checkWorkId: (id) async => const CandidateVerification(
                  CandidateCheck.verified, title: 'Remote title'),
            ),
          );
        },
        child: const Text('edit'),
      ))),
    ));
    await tester.tap(find.text('edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('edit-work-id')), '3172801');
    await tester.tap(find.byKey(const Key('edit-work-verify')));
    await tester.pumpAndSettle();
    expect(find.text('Remote title'), findsOneWidget);
    await tester.tap(find.byKey(const Key('edit-work-submit')));
    await tester.pumpAndSettle();
    expect(saved!.workId, '3172801');
    expect(saved!.title, 'My custom title');
    expect(saved!.author, 'Author');
  });

  testWidgets('multiple source URLs are retained; unsafe URLs are rejected',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 1050));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    WorkEditDraft? saved;
    final work = WorkEntry.create(workId: '2711759', title: 'Original');
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko'), Locale('en'), Locale('ja')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () async {
          saved = await showDialog<WorkEditDraft>(
            context: context, builder: (ctx) => WorkEditorDialog(
              work: work,
              checkWorkId: (_) async =>
                  const CandidateVerification(CandidateCheck.verified),
            ),
          );
        },
        child: const Text('edit'),
      ))),
    ));
    await tester.tap(find.text('edit'));
    await tester.pumpAndSettle();
    final sourceField = find.byKey(const Key('edit-work-source-urls'));
    await tester.ensureVisible(sourceField);
    await tester.enterText(sourceField, 'http://unsafe.test/gallery');
    await tester.ensureVisible(find.byKey(const Key('edit-work-submit')));
    await tester.tap(find.byKey(const Key('edit-work-submit')));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(find.textContaining('HTTPS'), findsWidgets);

    await tester.ensureVisible(sourceField);
    await tester.enterText(sourceField,
        'https://youtube.com/post/Ugkx1234567890\n'
        'https://www.instagram.com/reel/ABC12345');
    final aliases = find.byKey(const Key('edit-work-aliases'));
    await tester.ensureVisible(aliases);
    await tester.enterText(aliases, '風の空\n하늘의 바람');
    await tester.ensureVisible(find.byKey(const Key('edit-work-submit')));
    await tester.tap(find.byKey(const Key('edit-work-submit')));
    await tester.pumpAndSettle();
    expect(saved?.sourceUrls.length, 2);
    expect(saved?.titleAliases, ['風の空', '하늘의 바람']);
  });

  testWidgets('not found new number requires an extra confirmation',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ko'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ko'), Locale('en'), Locale('ja')],
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () => showDialog<WorkEditDraft>(
          context: context, builder: (ctx) => WorkEditorDialog(
            work: WorkEntry.create(workId: '23172801'),
            checkWorkId: (_) async =>
                const CandidateVerification(CandidateCheck.notFound),
          )),
        child: const Text('edit'),
      ))),
    ));
    await tester.tap(find.text('edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('edit-work-id')), '3172801');
    await tester.tap(find.byKey(const Key('edit-work-submit')));
    await tester.pumpAndSettle();
    expect(find.text('번호 확인 필요'), findsOneWidget);
    await tester.tap(find.text('취소').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit-work-id')), findsOneWidget);
  });
}
