import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/title_alias_index.dart';
import 'package:hyp_viewer/core/work.dart';
import 'package:hyp_viewer/core/work_editions.dart';

void main() {
  final japanese = WorkEntry.create(
    workId: '111111', title: 'Kaze no Sora 3話',
    author: 'Maker',
    titleAliases: ['風の空 第3話'],
  ).copyWith(
    sourceLanguage: 'japanese',
    sourceSeries: 'Sora', sourceGroup: 'Circle',
    editionGroupId: 'edition_sora_3', totalPages: 24,
    currentPage: 14,
  );
  final korean = WorkEntry.create(
    workId: '222222', title: '하늘의 바람 3화',
    author: 'Maker',
    titleAliases: ['The Sky Wind 3'],
  ).copyWith(
    sourceLanguage: 'korean',
    sourceSeries: 'Sora', sourceGroup: 'Circle',
    editionGroupId: 'edition_sora_3', totalPages: 24,
    currentPage: 3,
  );

  test('known language editions produce a public title alias index', () {
    final index = TitleAliasIndex.fromLibrary([japanese, korean]);
    final q = index.queriesFor(japanese, entered: 'Kaze no Sora 3話');
    expect(q, contains('하늘의 바람 3화'));
    expect(q, contains('風の空 第3話'));
    expect(q, contains('The Sky Wind 3'));
    expect(q, contains('artist:Maker'));
    expect(q.length, lessThanOrEqualTo(12));
    expect(index.sharesKnownAlias(japanese, korean), true);
  });

  test('unlinking translations stops inherited discovery aliases', () {
    final unlinked = korean.copyWith(editionGroupId: '');
    final index = TitleAliasIndex.fromLibrary([japanese, unlinked]);
    expect(index.sharesKnownAlias(japanese, unlinked), false);
    expect(index.queriesFor(japanese), isNot(contains('하늘의 바람 3화')));
  });

  test('independently verified remote title aliases can match a translation', () {
    final candidate = WorkEntry.create(
      workId: '333333',
      title: '風の空 第3話',
      author: 'Maker',
      titleAliases: ['Kaze no Sora 3話'],
    ).copyWith(
      sourceLanguage: 'english',
      sourceSeries: 'Sora', sourceGroup: 'Circle',
      totalPages: 24,
    );
    expect(WorkEditions.compare(japanese, candidate).autoLink, true);
    expect(WorkEditions.visibleOnShelf([japanese,korean],false).length,2);
    expect(japanese.currentPage,14);
    expect(korean.currentPage,3);
  });

  test('different chapters never auto link despite matching franchise alias', () {
    final wrong = WorkEntry.create(
      workId: '444444', title: 'Kaze no Sora 4話',
      author: 'Maker', titleAliases: ['Kaze no Sora'],
    ).copyWith(
      sourceLanguage: 'english', sourceSeries: 'Sora',
      totalPages: 24,
    );
    expect(WorkEditions.compare(japanese, wrong).autoLink, false);
  });
}
