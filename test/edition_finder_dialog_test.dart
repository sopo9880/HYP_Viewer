import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/online_search.dart';
import 'package:hyp_viewer/core/work.dart';
import 'package:hyp_viewer/l10n/app_localizations.dart';
import 'package:hyp_viewer/ui/edition_finder_dialog.dart';

void main() {
  Future<void> openFinder(WidgetTester tester,
      Completer<OnlineSearchResult> results,
      Future<void> Function(List<String>, List<OnlineSearchWork>) onLink) async {
    await tester.binding.setSurfaceSize(const Size(1100, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Builder(
        builder: (ctx) => Center(child: FilledButton(
          onPressed: () => showDialog<void>(
            context: ctx,
            builder: (_) => EditionFinderDialog(
              anchor: WorkEntry.create(workId: '111111',
                  title: 'Shared Story', author: 'Maker')
                  .copyWith(sourceLanguage: 'japanese',
                      sourceSeries: 'Series'),
              library: [
                WorkEntry.create(workId: '111111',
                    title: 'Shared Story', author: 'Maker')
                    .copyWith(sourceLanguage: 'japanese',
                        sourceSeries: 'Series'),
              ],
              coverImages: const {},
              searchPage: (query, page) => results.future,
              onLinkSelected: onLink,
            ),
          ),
          child: const Text('Find'),
        )),
      )),
    ));
    await tester.tap(find.text('Find'));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('finder shows a modal before remote search has finished',
      (tester) async {
    final results = Completer<OnlineSearchResult>();
    final linked = <OnlineSearchWork>[];
    await openFinder(tester, results, (local, remote) async {
      expect(local, isEmpty);
      linked.addAll(remote);
    });
    expect(find.byKey(const Key('edition-finder-query')), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byKey(const Key('edition-finder-link')), findsOneWidget);
    results.complete(const OnlineSearchResult([
      OnlineSearchWork(workId: '222222', title: 'Shared Story',
          language: 'korean', artists: ['Maker'], series: ['Series']),
      OnlineSearchWork(workId: '333333', title: 'Shared Story',
          language: 'english', artists: ['Maker'], series: ['Series']),
    ], 2, 1));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edition-found-222222')));
    await tester.tap(find.byKey(const Key('edition-found-333333')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('edition-finder-link')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('같은 작품으로 묶기').last);
    await tester.pumpAndSettle();
    expect(linked.map((work) => work.workId).toSet(),
        {'222222', '333333'});
  });

  testWidgets('Back cancels an unfinished lookup without any library write',
      (tester) async {
    final results = Completer<OnlineSearchResult>();
    var linked = false;
    await openFinder(tester, results, (_, __) async { linked = true; });
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edition-finder-query')), findsNothing);
    results.complete(const OnlineSearchResult([
      OnlineSearchWork(workId: '222222', title: 'Shared Story',
          language: 'korean'),
    ], 1, 1));
    await tester.pump();
    expect(linked, false);
    expect(tester.takeException(), isNull);
  });
}
