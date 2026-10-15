import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hyp_viewer/l10n/app_localizations.dart';
import 'package:hyp_viewer/core/number_extractor.dart';
import 'package:hyp_viewer/ui/shorts_finder_panel.dart';

void main() {
  testWidgets('numeric search quick-add bypasses YouTube and shows mobile IDs',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final url = TextEditingController();
    final apiKey = TextEditingController();
    final comment = TextEditingController();
    final code = TextEditingController();
    final title = TextEditingController();
    final author = TextEditingController();
    addTearDown(() {
      url.dispose(); apiKey.dispose(); comment.dispose();
      code.dispose(); title.dispose(); author.dispose();
    });
    String? added;
    var fetchCount = 0;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko'), Locale('en'), Locale('ja')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: SingleChildScrollView(
        child: ShortsFinderPanel(
          url: url, apiKey: apiKey, comment: comment,
          workId: code, title: title, author: author,
          candidates: const [
            NumberCandidate(code: '2711759', evidence: '1편',
                source: 'comment', score: 90),
            NumberCandidate(code: '2951072', evidence: '2편',
                source: 'comment', score: 90),
          ],
          busy: false,
          onAnalyze: () {},
          onFetch: () async { fetchCount++; },
          onQuickAddNumber: (value) async { added = value; },
          onOpenYoutube: () async {},
          onSave: () async {},
          onSaveSelectedWorks: (_) async {},
        ),
      )),
    ));
    await tester.pumpAndSettle();
    final quick = find.byKey(const Key('shorts-quick-candidate-2951072'));
    expect(quick, findsOneWidget);
    await tester.ensureVisible(quick);
    await tester.tap(quick);
    await tester.pumpAndSettle();
    expect(code.text, '2951072');
    await tester.ensureVisible(find.byKey(const Key('shorts-url-input')));
    await tester.enterText(find.byKey(const Key('shorts-url-input')), '2951072');
    await tester.ensureVisible(find.byKey(const Key('shorts-search-button')));
    await tester.tap(find.byKey(const Key('shorts-search-button')));
    await tester.pump();
    expect(added, '2951072');
    expect(fetchCount, 0);
  });

  testWidgets('two Shorts candidates can be selected and saved together',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1120, 1050));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final url = TextEditingController();
    final apiKey = TextEditingController();
    final comment = TextEditingController();
    final code = TextEditingController();
    final title = TextEditingController();
    final author = TextEditingController();
    addTearDown(() {
      url.dispose(); apiKey.dispose(); comment.dispose();
      code.dispose(); title.dispose(); author.dispose();
    });
    var saved = <String>[];
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko'), Locale('en'), Locale('ja')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: SingleChildScrollView(child: ShortsFinderPanel(
          url: url, apiKey: apiKey, comment: comment,
          workId: code, title: title, author: author,
          candidates: const [
            NumberCandidate(code: '2711759', evidence: '1편',
                source: 'comment', score: 90),
            NumberCandidate(code: '2951072', evidence: '2편',
                source: 'comment', score: 90),
          ],
          busy: false,
          onAnalyze: () {},
          onFetch: () async {},
          onOpenYoutube: () async {},
          onSave: () async {},
          onSaveSelectedWorks: (codes) async { saved = codes; },
        )),
      ),
    ));
    await tester.pumpAndSettle();
    final save = find.byKey(const Key('save-selected-works'));
    expect(save, findsOneWidget);
    // Having candidates must never prevent the user from collapsing details.
    await tester.ensureVisible(find.text('댓글·번호 입력 접기'));
    await tester.tap(find.text('댓글·번호 입력 접기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('candidate-editor')), findsNothing);
    await tester.ensureVisible(find.text('댓글 직접 입력 · 번호 확정'));
    await tester.tap(find.text('댓글 직접 입력 · 번호 확정'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('candidate-editor')), findsOneWidget);
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump();
    expect(saved, ['2711759', '2951072']);
    await tester.tap(find.byKey(const Key('shorts-candidate-2951072')));
    await tester.pump();
    await tester.tap(save);
    await tester.pump();
    expect(saved, ['2711759']);
  });
}
