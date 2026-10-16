import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/finder_reset_policy.dart';

void main() {
  test('only a successfully saved unchanged finder clears on leaving Home', () {
    final reset = FinderResetPolicy();
    const fields = ['https://youtube.com/shorts/demo', 'comment',
      '123', 'title', 'author', '123|456'];
    expect(reset.consumeOnLeave(fields), false); // never saved
    reset.recordSuccessfulSave(fields);
    expect(reset.consumeOnLeave(fields), true);
    expect(reset.consumeOnLeave(fields), false); // one-time cleanup
  });

  test('new user input and edits must not be cleared', () {
    final reset = FinderResetPolicy();
    reset.recordSuccessfulSave(['old link', 'old candidate']);
    expect(reset.consumeOnLeave(['new link', 'old candidate']), false);
    reset.recordSuccessfulSave(['link', '123']);
    expect(reset.consumeOnLeave(['link', '456']), false);
  });

  test('manual clear discards an old pending save and never includes API key', () {
    final reset = FinderResetPolicy();
    reset.recordSuccessfulSave(['saved link']);
    reset.reset();
    expect(reset.consumeOnLeave(['saved link']), false);
  });
}
