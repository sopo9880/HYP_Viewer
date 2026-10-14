import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/candidate_verifier.dart';
import 'package:hyp_viewer/core/number_extractor.dart';
import 'package:hyp_viewer/ui/candidate_editor.dart';

void main() {
  testWidgets('candidate count, selection and numbers can all be edited',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(640, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    List<String> saved = [];
    final requested = <List<String>>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: CandidateEditor(
        suggestions: const [
          NumberCandidate(code: '2900756', episode: '1편',
            evidence: '1편 - 2900년 7월 56일',
            source: 'comment', rule: 'split-number', score: 92),
          NumberCandidate(code: '3172801', episode: '2편',
            evidence: '2편 - 317시간 28분 01초',
            source: 'comment', rule: 'split-number', score: 92),
        ],
        busy: false,
        onVerify: (codes) async {
          requested.add(codes);
          return {for (final code in codes)
            code: CandidateVerification(
              code == '3172801'
                  ? CandidateCheck.notFound : CandidateCheck.verified,
              title: 'Test Title ' + code,
            )};
        },
        onSave: (codes) async { saved = codes; },
      ))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Test Title 2900756'), findsOneWidget);
    expect(find.text('작품 미존재 (404)'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('candidate-input-1')), '3419120');
    await tester.pump();
    expect(find.text('존재 여부 미검증'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('candidate-add')));
    await tester.tap(find.byKey(const Key('candidate-add')));
    await tester.pump();
    expect(find.byKey(const Key('candidate-input-2')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('candidate-input-2')), '1234567');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('candidate-remove-2')));
    await tester.tap(find.byKey(const Key('candidate-remove-2')));
    await tester.pump();
    expect(find.byKey(const Key('candidate-input-2')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('candidate-verify-all')));
    await tester.tap(find.byKey(const Key('candidate-verify-all')));
    await tester.pumpAndSettle();
    expect(requested.last.toSet(), {'2900756', '3419120'});
    await tester.ensureVisible(find.byKey(const Key('save-selected-works')));
    await tester.tap(find.byKey(const Key('save-selected-works')));
    await tester.pump();
    expect(saved, ['2900756', '3419120']);
  });

  testWidgets('a manual candidate can be saved without auto suggestions',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var saved = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: CandidateEditor(
        suggestions: const [], busy: false,
        onSave: (codes) async { saved = codes; },
      ))),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const Key('candidate-add')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('candidate-input-0')), '2900756');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('save-selected-works')));
    await tester.tap(find.byKey(const Key('save-selected-works')));
    await tester.pump();
    expect(saved, ['2900756']);
  });
  testWidgets('second-pass adjacent-line checks run only after 404',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var fallbackCalls = 0;
    final checked = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: CandidateEditor(
        busy: false,
        suggestions: const [
          NumberCandidate(code: '623112', source: 'comment',
              evidence: '초6~중2 중3 고1 12시간',
              score: 60, rule: 'line-window'),
        ],
        onCrossLineFallback: () {
          fallbackCalls++;
          return const [NumberCandidate(code: '4036355',
              evidence: '4036년\n3월 55일',
              rule: 'cross-line', source: 'comment', score: 30)];
        },
        onVerify: (codes) async {
          checked.addAll(codes);
          return {
            for (final code in codes)
              code: CandidateVerification(
                code == '4036355'
                    ? CandidateCheck.verified : CandidateCheck.notFound,
                title: 'Test work',
              )
          };
        },
        onSave: (_) async {},
      ))),
    ));
    await tester.pumpAndSettle();
    expect(fallbackCalls, 1);
    expect(checked, ['623112', '4036355']);
    expect(find.text('Test work'), findsOneWidget);
  });

  testWidgets('an unavailable server never triggers cross-line fallback',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var fallbackCalls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: CandidateEditor(
        busy: false,
        suggestions: const [
          NumberCandidate(code: '623112', source: 'comment',
              evidence: 'numbers', score: 40, rule: 'line-window'),
        ],
        onCrossLineFallback: () {
          fallbackCalls++;
          return const [];
        },
        onVerify: (codes) async => {
          for (final code in codes)
            code: const CandidateVerification(CandidateCheck.unavailable),
        },
        onSave: (_) async {},
      ))),
    ));
    await tester.pumpAndSettle();
    expect(fallbackCalls, 0);
    expect(find.textContaining('2차 확장은 보류'), findsOneWidget);
  });

}
