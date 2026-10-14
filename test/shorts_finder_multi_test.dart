import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/number_extractor.dart';
import 'package:hyp_viewer/ui/shorts_finder_panel.dart';

void main() {
  testWidgets('two Shorts candidates can be selected and saved together',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1120, 1050));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final url = TextEditingController();
    final apiKey = TextEditingController();
    final comment = TextEditingController();
    final code = TextEditingController();
    final title = TextEditingController();
    final author = TextEditingController();
    addTearDown(() {
      url.dispose(); apiKey.dispose(); comment.dispose();
      code.dispose(); title.dispose(); author.dispose();
    });
    var saved = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: ShortsFinderPanel(
          url: url, apiKey: apiKey, comment: comment,
          workId: code, title: title, author: author,
          candidates: const [
            NumberCandidate(code: '2711759', evidence: '1편',
                source: 'comment', score: 90),
            NumberCandidate(code: '2951072', evidence: '2편',
                source: 'comment', score: 90),
          ],
          busy: false,
          onAnalyze: () {},
          onFetch: () async {},
          onOpenYoutube: () async {},
          onSave: () async {},
          onSaveSelectedWorks: (codes) async { saved = codes; },
        )),
      ),
    ));
    await tester.pumpAndSettle();
    final save = find.byKey(const Key('save-selected-works'));
    expect(save, findsOneWidget);
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump();
    expect(saved, ['2711759', '2951072']);
    await tester.tap(find.byKey(const Key('shorts-candidate-2951072')));
    await tester.pump();
    await tester.tap(save);
    await tester.pump();
    expect(saved, ['2711759']);
  });
}
