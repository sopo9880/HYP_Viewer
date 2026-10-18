import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/blacklist.dart';

void main() {
  test('ID block does not accidentally block a different ID', () {
    final deny = const BlacklistRules().add(
      const BlacklistRule(kind: 'id', value: '1234567'));
    expect(deny.blocks(id: '1234567'), isTrue);
    expect(deny.blocks(id: '1234568'), isFalse);
  });

  test('artist, group, tag and title filters use metadata, not wrong fields', () {
    final deny = const BlacklistRules().add(
      const BlacklistRule(kind: 'artist', value: 'pochi'))
      .add(const BlacklistRule(kind: 'group', value: 'circle'))
      .add(const BlacklistRule(kind: 'tag', value: 'female:some_tag'))
      .add(const BlacklistRule(kind: 'title', value: 'unwanted'));
    expect(deny.blocks(artists: ['Pochi']), isTrue);
    expect(deny.blocks(title: 'Pochi series'), isFalse);
    expect(deny.blocks(groups: ['Super Circle']), isTrue);
    expect(deny.blocks(tags: ['female:some tag']), isTrue);
    expect(deny.blocks(title: 'An Unwanted title'), isTrue);
  });

  test('backup roundtrip and duplicate merge preserve reason', () {
    final first = const BlacklistRules().add(
      const BlacklistRule(kind: 'id', value: '1234567', reason: 'hidden'));
    expect(BlacklistRules.decode(first.encode()).rules.single.reason,
        'hidden');
    expect(first.merge(BlacklistRules.decode(first.encode())).rules, hasLength(1));
    expect(first.without('id', '1234567').rules, isEmpty);
  });

  test('invalid imported backup cannot replace current entries', () {
    expect(() => BlacklistRules.decode('{"works":[]}'), throwsFormatException);
    expect(() => BlacklistRules.decode(
        '{"app":"HYP Viewer Blacklist","schemaVersion":1,'
        '"rules":[{"kind":"bad","value":"x"}]}'), throwsFormatException);
  });
}
