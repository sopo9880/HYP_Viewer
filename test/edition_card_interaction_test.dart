import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/work.dart';
import 'package:hyp_viewer/l10n/app_localizations.dart';
import 'package:hyp_viewer/ui/work_edition_card.dart';

void main() {
  testWidgets('stack cover resumes; title is inert; chooser remains accessible',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var read = 0;
    var choose = 0;
    final editions = [
      WorkEntry.create(workId: '111111', title: 'Sample')
          .copyWith(sourceLanguage: 'japanese',
              editionGroupId: 'edition_test'),
      WorkEntry.create(workId: '222222', title: 'Sample')
          .copyWith(sourceLanguage: 'korean',
              editionGroupId: 'edition_test'),
    ];
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(
        child: SizedBox(width: 280, height: 380,
          child: HypWorkEditionCard(
            editions: editions,
            coverImages: const {},
            onOpenCover: () => read++,
            onOpen: () => choose++,
          ),
        ),
      )),
    ));
    await tester.tap(find.byKey(const Key('edition-cover-edition_test')));
    await tester.pump();
    expect(read, 1);
    expect(choose, 0);
    // The title tap is reserved for showing the full text, not navigating.
    await tester.tap(find.byKey(const Key('edition-title-edition_test')));
    await tester.pump();
    expect(choose, 0);
    expect(read, 1);
    // The previous language picker stays available as its own target.
    await tester.tap(find.byKey(const Key('edition-choose-edition_test')));
    await tester.pump();
    expect(choose, 1);
    expect(read, 1);
  });
}
