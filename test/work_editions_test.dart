import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/work.dart';
import 'package:hyp_viewer/core/work_editions.dart';

void main() {
  WorkEntry work(String code, String title, String language, {
    String author = 'Creator', int pages = 20, String series = 'Book',
  }) => WorkEntry.create(workId: code, title: title, author: author)
      .copyWith(sourceLanguage: language, totalPages: pages,
        sourceSeries: series);
  test('same original chapter with a translated subtitle links', () {
    final japanese = work('111111', 'A Title | 日本語訳', 'japanese');
    final korean = work('222222', 'A Title | 한국어', 'korean');
    expect(WorkEditions.compare(japanese, korean).autoLink, true);
  });
  test('later chapter is never mixed with first chapter', () {
    final a = work('111111', 'A Title 1화', 'japanese');
    final b = work('222222', 'A Title 2화', 'korean');
    expect(WorkEditions.compare(a, b).score, 0);
  });
  test('same series with a different original cannot silently link', () {
    final a = work('111111', 'First Story', 'japanese');
    final b = work('222222', 'Other Story', 'korean');
    expect(WorkEditions.compare(a, b).autoLink, false);
  });
  test('manual complete/uncomplete does not lose progress or sibling editions', () {
    final a=work('111111','A Title','japanese')
        .copyWith(editionGroupId:'edition_111111',currentPage:9);
    final b=work('222222','A Title | 한국어','korean')
        .copyWith(editionGroupId:'edition_111111',currentPage:2);
    final original=LibraryBackup(works:[a,b],collections:const []);
    final completed=original.withCompleted('111111',true);
    expect(completed.works[0].completed,true);
    expect(completed.works[1].completed,false);
    final undone=completed.withCompleted('111111',false);
    expect(undone.works[0].currentPage,9);
    expect(undone.works[0].editionGroupId,'edition_111111');
    expect(undone.works[1].currentPage,2);
  });
  test('edition group survives JSON backup and preserves separate progress', () {
    final a = work('111111','A Title','japanese')
        .copyWith(editionGroupId: 'edition_111111', currentPage: 12);
    final b = work('222222','A Title | 한국어','korean')
        .copyWith(editionGroupId: 'edition_111111', currentPage: 3);
    final backup = LibraryBackup(works: [a,b], collections: const []);
    final recovered = LibraryBackup.decode(backup.encode());
    expect(WorkEditions.versions(recovered.works, recovered.works[0]).length, 2);
    expect(recovered.works[0].currentPage, 12);
    expect(recovered.works[1].currentPage, 3);
  });
}
