import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/work.dart';
import 'package:hyp_viewer/ui/work_cards.dart';

void main() {
  testWidgets('long press enters selection and tapping toggles selected cards',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(620, 750));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final works = [
      WorkEntry.create(workId: '2711759', title: 'One'),
      WorkEntry.create(workId: '2951072', title: 'Two'),
    ];
    var selectMode = false;
    final selected = <String>{};
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: StatefulBuilder(
        builder: (context, update) => SingleChildScrollView(
          child: HypWorkGrid(
            works: works,
            offlineKeys: const {},
            pageCounts: const {},
            coverImages: const {},
            selectionMode: selectMode,
            selectedWorkIds: selected,
            onOpen: (_) {},
            onAction: (action, work) {},
            onSelect: (work) => update(() {
              if (!selected.add(work.workId)) selected.remove(work.workId);
            }),
            onLongPress: (work) => update(() {
              selectMode = true;
              selected.add(work.workId);
            }),
          ),
        )),
      )),
    ));
    await tester.longPress(find.byKey(const Key('work-work:2711759')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('work-selection-2711759')), findsOneWidget);
    expect(selected, {'2711759'});
    await tester.tap(find.byKey(const Key('work-work:2951072')));
    await tester.pump();
    expect(selected, {'2711759', '2951072'});
    await tester.tap(find.byKey(const Key('work-work:2711759')));
    await tester.pump();
    expect(selected, {'2951072'});
  });

  testWidgets('normal card menu exposes direct edit action',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(540, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? action;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SizedBox(width: 260, height: 360,
        child: HypWorkCard(
          work: WorkEntry.create(workId: '2711759'),
          isOffline: false,
          totalPages: null,
          coverBytes: null,
          onOpen: () {},
          onAction: (value) => action = value,
        ),
      )),
    ));
    await tester.tap(find.byTooltip('작품 메뉴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('작품 정보 수정'));
    await tester.pumpAndSettle();
    expect(action, 'edit_details');
  });
}
