import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/work.dart';
import 'package:hyp_viewer/l10n/app_localizations.dart';
import 'package:hyp_viewer/ui/work_group_card.dart';

void main() {
  testWidgets('whole group is selectable without opening its contents',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var opens = 0, selections = 0, longPresses = 0;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: SizedBox(width: 240, height: 330,
        child: HypWorkGroupCard(
          title: 'Combined',
          members: [
            WorkEntry.create(workId: '1234567').copyWith(
                groupId: 'g', groupTitle: 'Combined'),
            WorkEntry.create(workId: '1234568').copyWith(
                groupId: 'g', groupTitle: 'Combined'),
          ],
          coverImages: const {},
          onOpen: () => opens++,
          onAction: (_) {},
          selectionMode: true,
          selected: false,
          onSelect: () => selections++,
          onLongPress: () => longPresses++,
        ),
      ))),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('group-selection-checkbox')), findsOneWidget);
    await tester.tap(find.byKey(const Key('group-selection-checkbox')));
    await tester.pumpAndSettle();
    expect(selections, 1);
    expect(opens, 0);
  });
}
