import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/work.dart';
import 'package:hyp_viewer/core/work_grouping.dart';
import 'package:hyp_viewer/ui/auto_group_wizard.dart';

void main() {
  testWidgets('Auto wizard lets user inspect, exclude, rename and reorder',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1050));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    List<AutoGroupReview>? chosen;
    final a = WorkEntry.create(workId: '2900756',
        title: '멋대로 눌러앉은 유령 1편');
    final b = WorkEntry.create(workId: '3172801',
        title: '멋대로 눌러앉은 유령 2편');
    final c = WorkEntry.create(workId: '3419120',
        title: '멋대로 눌러앉은 유령 3편');
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Center(child: TextButton(
        onPressed: () async {
          chosen = await showDialog<List<AutoGroupReview>>(
            context: tester.element(find.byType(TextButton).first),
            builder: (context) => AutoGroupWizard(
              suggestions: const [
                WorkGroupSuggestion('멋대로 눌러앉은 유령',
                    ['2900756', '3172801', '3419120'], '동일 제목'),
              ],
              works: [a, b, c],
            ),
          );
        },
        child: const Text('Open'),
      )),
    )));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('멋대로 눌러앉은 유령 1편'), findsOneWidget);
    expect(find.byKey(const Key('auto-group-work-0-3172801')), findsOneWidget);
    await tester.tap(find.byKey(const Key('auto-group-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auto-group-work-0-3419120')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('auto-group-title-0')),
        '다시 이름 붙인 시리즈');
    await tester.pump();
    await tester.tap(find.byKey(const Key('auto-group-down-0-2900756')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auto-group-confirm')));
    await tester.pumpAndSettle();
    expect(chosen, isNotNull);
    expect(chosen!.single.title, '다시 이름 붙인 시리즈');
    expect(chosen!.single.workIds, ['3172801', '2900756']);
  });

  testWidgets('existing series can add one work without new group creation',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(850, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final existing = WorkEntry.create(workId: '100001',
        title: '수학여행 1편').copyWith(
        groupId: 'group1', groupTitle: '수학여행', groupOrder: 1);
    final next = WorkEntry.create(workId: '100002',
        title: '수학여행 2편');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
      child: AutoGroupWizard(
        suggestions: const [WorkGroupSuggestion(
          '수학여행', ['100002'], '기존 시리즈',
          existingGroupId: 'group1',
        )],
        works: [existing, next],
      ),
    ))));
    await tester.pumpAndSettle();
    expect(find.textContaining('기존 1개 작품은 유지돼'), findsOneWidget);
    expect(find.byKey(const Key('auto-group-work-0-100002')),
        findsOneWidget);
  });
}
