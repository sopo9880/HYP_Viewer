import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/work.dart';
import 'package:hyp_viewer/ui/hyp_animated_title.dart';
import 'package:hyp_viewer/ui/work_cards.dart';
import 'package:hyp_viewer/ui/work_group_card.dart';
import 'package:hyp_viewer/l10n/app_localizations.dart';

const longTitle = 'Very long sample Japanese Korean English title that '
    'must be readable from start to finish without changing the card size';

void main() {
  testWidgets('manual title stays still until tapped, then scrolls',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: SizedBox(
        width: 155,
        child: HypAnimatedTitle(
          key: Key('manual-title'), title: longTitle),
      ))),
    ));
    final title = find.byKey(const Key('manual-title'));
    expect(find.descendant(of: title, matching:
        find.byType(SingleChildScrollView)), findsNothing);
    await tester.tap(title);
    await tester.pump();
    final moving = find.descendant(of: title,
        matching: find.byType(SingleChildScrollView));
    expect(moving, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 760));
    await tester.pump(const Duration(milliseconds: 1250));
    final scroll = tester.widget<SingleChildScrollView>(moving);
    expect(scroll.controller!.offset, greaterThan(0));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });

  testWidgets('short titles never animate even when tapped', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SizedBox(
        width: 400,
        child: HypAnimatedTitle(key: Key('short-title'), title: 'Short'),
      )),
    ));
    await tester.tap(find.byKey(const Key('short-title')));
    await tester.pump();
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.text('Short'), findsOneWidget);
  });

  testWidgets('verified candidate title loops only when it overflows',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SizedBox(width: 150,
        child: HypAnimatedTitle(
          key: Key('verified-title'), title: longTitle,
          motion: HypTitleMotion.automatic),
      )),
    ));
    final moving = find.descendant(
        of: find.byKey(const Key('verified-title')),
        matching: find.byType(SingleChildScrollView));
    expect(moving, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 760));
    await tester.pump(const Duration(milliseconds: 1400));
    final scroll = tester.widget<SingleChildScrollView>(moving);
    expect(scroll.controller!.offset, greaterThan(0));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });

  testWidgets('reduced motion keeps the entire title accessible but still',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(data: MediaQueryData(disableAnimations: true),
        child: Scaffold(body: SizedBox(width: 125,
          child: HypAnimatedTitle(
            key: Key('reduced-title'), title: longTitle,
            motion: HypTitleMotion.automatic),
        )),
      ),
    ));
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.text(longTitle), findsOneWidget);
  });

  testWidgets('work card cover opens; title only reveals overflow',
      (tester) async {
    var opened = 0;
    final work = WorkEntry.create(workId: '2711759', title: longTitle);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: SizedBox(
        width: 265, height: 365,
        child: HypWorkCard(
          work: work,
          isOffline: false,
          totalPages: null,
          coverBytes: null,
          onOpen: () => opened++,
          onAction: (_) {},
        ),
      ))),
    ));
    await tester.tap(find.byKey(const Key('work-title-2711759')));
    await tester.pump();
    expect(opened, 0);
    final card = find.byKey(const Key('work-work:2711759'));
    final topLeft = tester.getTopLeft(card);
    await tester.tapAt(topLeft + const Offset(32, 30));
    await tester.pump();
    expect(opened, 1);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });

  testWidgets('series title reveals text while cover opens chapters',
      (tester) async {
    var openedGroups = 0;
    final member = WorkEntry.create(workId: '2711759', title: longTitle)
        .copyWith(groupId: 'series_test', groupTitle: longTitle);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: SizedBox(
        width: 280, height: 385,
        child: HypWorkGroupCard(
          title: longTitle,
          members: [member],
          coverImages: const {},
          onOpen: () => openedGroups++,
          onAction: (_) {},
        ),
      ))),
    ));
    await tester.tap(find.byKey(const Key('group-title-series_test')));
    await tester.pump();
    expect(openedGroups, 0);
    final group = find.byKey(const Key('open-library-group'));
    await tester.tapAt(tester.getTopLeft(group) + const Offset(25, 30));
    await tester.pump();
    expect(openedGroups, 1);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });

  testWidgets('selection mode title tap toggles selection, never animates',
      (tester) async {
    var selected = 0;
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: SizedBox(
        width: 270, height: 380,
        child: HypWorkCard(
          work: WorkEntry.create(workId: '2711759', title: longTitle),
          isOffline: false,
          totalPages: null,
          coverBytes: null,
          selectionMode: true,
          onSelect: () => selected++,
          onOpen: () => opened++,
          onAction: (_) {},
        ),
      ))),
    ));
    await tester.tap(find.byKey(const Key('work-title-2711759')));
    await tester.pump();
    expect(selected, 1);
    expect(opened, 0);
    expect(find.descendant(
        of: find.byKey(const Key('work-title-2711759')),
        matching: find.byType(SingleChildScrollView)), findsNothing);
  });

  test('native Windows right click calls popUpContextMenu explicitly', () {
    final tray = File('lib/core/background_download_runtime.dart')
        .readAsStringSync();
    final start = tray.indexOf('void onTrayIconRightMouseDown()');
    final finish = tray.indexOf('void onTrayMenuItemClick(', start);
    expect(start, greaterThan(0));
    expect(finish, greaterThan(start));
    final handler = tray.substring(start, finish);
    expect(handler, contains('unawaited(_popupContextMenu())'));
    expect(handler, contains('await trayManager.popUpContextMenu()'));
    expect(handler, contains('tray popup failed'));
  });

  test('version and source title surfaces remain consistent', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = File('lib/core/release_version.dart').readAsStringSync();
    final request = File('.github/release-request.txt').readAsStringSync().trim();
    final release = pubspec.split('version: ').last.split('+').first.trim();
    expect(release, startsWith('0.'));
    expect(version, contains("const String hypReleaseVersion = '$release';"));
    expect(request, 'v$release');
    for (final name in [
      'work_cards.dart', 'work_edition_card.dart', 'work_group_card.dart',
      'candidate_editor.dart', 'hyp_dashboard.dart', 'gallery_reader.dart',
      'reading_insights.dart', 'edition_finder_dialog.dart',
      'auto_group_wizard.dart', 'visual_source_inspector.dart',
    ]) {
      expect(File('lib/ui/$name').readAsStringSync(),
          contains('HypAnimatedTitle('), reason: name);
    }
    final candidates = File('lib/ui/candidate_editor.dart').readAsStringSync();
    expect(candidates, contains('motion: HypTitleMotion.automatic'));
  });
}
