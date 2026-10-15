import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/ui/reader_navigation_focus.dart';

void main() {
  testWidgets('returning from reader does not reopen the search keyboard',
      (tester) async {
    final searchFocus = FocusNode(debugLabel: 'library-search');
    final dashboardFocus = FocusNode(debugLabel: 'dashboard-shortcuts');
    final searchController = TextEditingController();
    addTearDown(() {
      searchFocus.dispose();
      dashboardFocus.dispose();
      searchController.dispose();
    });

    await tester.pumpWidget(MaterialApp(home: Focus(
      focusNode: dashboardFocus,
      autofocus: true,
      child: Builder(builder: (dashboardContext) => Scaffold(
        body: Column(children: [
          TextField(
            key: const Key('library-search-input'),
            controller: searchController,
            focusNode: searchFocus,
          ),
          FilledButton(
            key: const Key('open-reader'),
            onPressed: () => ReaderNavigationFocus.show(
              returnFocus: dashboardFocus,
              isMounted: () => dashboardContext.mounted,
              openReader: () => Navigator.of(dashboardContext).push<void>(
                MaterialPageRoute(builder: (readerContext) => Scaffold(
                  body: Center(child: FilledButton(
                    key: const Key('reader-back'),
                    onPressed: () => Navigator.of(readerContext).pop(),
                    child: const Text('Back'),
                  )),
                )),
              ),
            ),
            child: const Text('Open'),
          ),
        ]),
      )),
    )));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('library-search-input')), 'Pochi');
    await tester.pump();
    expect(searchFocus.hasPrimaryFocus, isTrue);

    await tester.tap(find.byKey(const Key('open-reader')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-back')), findsOneWidget);
    expect(searchFocus.hasFocus, isFalse);
    await tester.tap(find.byKey(const Key('reader-back')));
    await tester.pumpAndSettle();

    expect(searchController.text, 'Pochi');
    expect(searchFocus.hasFocus, isFalse,
        reason: 'Returning from the reader must not reopen the mobile keyboard');
    expect(dashboardFocus.hasPrimaryFocus, isTrue);

    // Tapping Search manually must still open input as normal.
    await tester.tap(find.byKey(const Key('library-search-input')));
    await tester.pump();
    expect(searchFocus.hasPrimaryFocus, isTrue);
  });

  testWidgets('hardware back after reader also leaves the search unfocused',
      (tester) async {
    final dashboardFocus = FocusNode();
    final searchFocus = FocusNode();
    addTearDown(() {
      dashboardFocus.dispose();
      searchFocus.dispose();
    });
    late BuildContext dashboardContext;
    await tester.pumpWidget(MaterialApp(home: Focus(
      focusNode: dashboardFocus,
      child: Builder(builder: (context) {
        dashboardContext = context;
        return Scaffold(body: Column(children: [
          TextField(key: const Key('search'), focusNode: searchFocus),
          FilledButton(
            key: const Key('open'),
            onPressed: () => ReaderNavigationFocus.show(
              returnFocus: dashboardFocus,
              isMounted: () => dashboardContext.mounted,
              openReader: () => Navigator.of(dashboardContext).push<void>(
                  MaterialPageRoute(builder: (_) =>
                      const Scaffold(body: Text('Reading')))),
            ),
            child: const Text('Open'),
          ),
        ]));
      }),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search')));
    await tester.pump();
    expect(searchFocus.hasFocus, isTrue);
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    expect(find.text('Reading'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Reading'), findsNothing);
    expect(searchFocus.hasFocus, isFalse);
    expect(dashboardFocus.hasPrimaryFocus, isTrue);
  });
}
