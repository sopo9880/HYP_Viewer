import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/work.dart';
import 'package:hyp_viewer/ui/work_cards.dart';

void main() {
  testWidgets('work card distinguishes library entry deletion from CBZ deletion',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? action;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 260, height: 370,
          child: HypWorkCard(
            work: WorkEntry.create(workId: '2711759', title: '샘플'),
            isOffline: true,
            totalPages: 12,
            coverBytes: null,
            onOpen: () {},
            onAction: (value) => action = value,
          ),
        ),
      ),
    ));
    await tester.tap(find.byTooltip('작품 메뉴'));
    await tester.pumpAndSettle();
    expect(find.text('오프라인 파일 삭제'), findsOneWidget);
    expect(find.text('서재에서 작품 삭제'), findsOneWidget);
    await tester.tap(find.text('서재에서 작품 삭제'));
    await tester.pumpAndSettle();
    expect(action, 'delete_work');
  });
}
