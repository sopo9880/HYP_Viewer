import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/work.dart';
import 'package:hyp_viewer/ui/cover_picker.dart';

void main() {
  testWidgets('users can choose a built-in cover', (tester) async {
    CoverChoice? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) => ElevatedButton(
        onPressed: () async {
          selected = await showCoverPicker(context, WorkEntry.create(workId: '1234'));
        },
        child: const Text('편집'),
      ))),
    ));
    await tester.tap(find.text('편집'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cover-preset-3')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cover-picker-apply')));
    await tester.pumpAndSettle();
    expect(selected?.mode, 'preset');
    expect(selected?.preset, 3);
  });

  testWidgets('users can choose a page for the cover', (tester) async {
    CoverChoice? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) => ElevatedButton(
        onPressed: () async {
          selected = await showCoverPicker(context, WorkEntry.create(workId: '1234'));
        },
        child: const Text('편집'),
      ))),
    ));
    await tester.tap(find.text('편집'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cover-page-input')), '12');
    await tester.tap(find.byKey(const Key('cover-picker-apply')));
    await tester.pumpAndSettle();
    expect(selected?.mode, 'page');
    expect(selected?.page, 12);
  });
}
