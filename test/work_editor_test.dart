import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('not found new number requires an extra confirmation',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
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
