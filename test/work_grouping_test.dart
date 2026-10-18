import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/work.dart';
import 'package:hyp_viewer/core/work_grouping.dart';

void main() {
  test('new optional fields survive storage and preserve original add date', () {
    final input = WorkEntry.create(workId: '1234567')
        .copyWith(addedAt: '2026-01-01T00:00:00.000Z',
          openCount: 6, totalPages: 100, tags: ['tag'], groupId: 'grp',
          groupTitle: 'Collection', groupOrder: 2);
    final result = WorkEntry.fromJson(input.toJson());
    expect(result.addedAt, '2026-01-01T00:00:00.000Z');
    expect(result.openCount, 6);
    expect(result.totalPages, 100);
    expect(result.groupTitle, 'Collection');
    expect(result.copyWith(title: 'Edited').groupId, 'grp');
    expect(LibraryBackup.decode(LibraryBackup(
        works: [result], collections: []).encode()).works.first.tags, ['tag']);
  });

  test('auto group proposes numbered works, never existing groups', () {
    final one = WorkEntry.create(workId: '2900756',
      videoId: 'sharedshort', title: '멋대로 눌러앉은 유령 1편',
      originalComment: '1편 - 2900년 7월 56일');
    final two = WorkEntry.create(workId: '3172801',
      videoId: 'sharedshort', title: '멋대로 눌러앉은 유령 2편',
      originalComment: '2편 - 317시간 28분 01초');
    final three = WorkEntry.create(workId: '3419120',
      videoId: 'sharedshort', title: '멋대로 눌러앉은 유령 3편',
      originalComment: '3편 - 341/912/0',).copyWith(groupId: 'existing');
    final groups = WorkGrouping.suggest([one, two, three]);
    expect(groups, hasLength(1));
    expect(groups.first.existingGroupId, 'existing');
    expect(groups.first.workIds, ['2900756', '3172801']);
    expect(three.groupId, 'existing');
  });

  test('original title with a distinct Korean translation groups its sequel', () {
    final first = WorkEntry.create(workId: '50001',
      title: 'Yarasete Yarutte Ittenno! | 하게 해주겠다고 말했어!');
    final second = WorkEntry.create(workId: '50002',
      title: 'Yarasete Yarutte Ittenno! 2 | 하게 해준다니까! 2');
    expect(WorkGrouping.normalizedSeries(first.title),
      WorkGrouping.normalizedSeries(second.title));
    expect(WorkGrouping.episodeNumber(first), isNull);
    expect(WorkGrouping.episodeNumber(second), 2);
    final grouped = WorkGrouping.suggest([second, first]);
    expect(grouped, hasLength(1));
    expect(grouped.single.workIds, ['50001', '50002']);
  });

  test('custom chapter sort preserves group order', () {
    final a = WorkEntry.create(workId:'123456', title:'Story 2').copyWith(groupOrder: 2);
    final b = WorkEntry.create(workId:'123457', title:'Story 1').copyWith(groupOrder: 1);
    expect(WorkSorting.sort([a,b],LibrarySort.chapter).first.workId, '123457');
    expect(WorkSorting.sort([a,b],LibrarySort.chapter,descending:true).first.workId, '123456');
  });
  test('same chapter translations never create a false series suggestion', () {
    final ja = WorkEntry.create(workId:'201101',title:'Story One')
        .copyWith(sourceLanguage:'japanese',editionGroupId:'ed1');
    final ko = WorkEntry.create(workId:'201102',title:'Story One | 한국어')
        .copyWith(sourceLanguage:'korean',editionGroupId:'ed1');
    expect(WorkGrouping.suggest([ja,ko]),isEmpty);
  });

  test('sorting uses added date not read-update date and numeric ids', () {
    final a = WorkEntry.create(workId: '100').copyWith(
        addedAt: '2025-01-01T00:00:00Z', openCount: 5);
    final b = WorkEntry.create(workId: '99').copyWith(
        addedAt: '2026-01-01T00:00:00Z', openCount: 1);
    expect(WorkSorting.sort([a,b], LibrarySort.newest).first.workId, '99');
    expect(WorkSorting.sort([a,b], LibrarySort.mostRead).first.workId, '100');
    expect(WorkSorting.sort([a,b], LibrarySort.number).first.workId, '99');
  });
  test('publication and ranked popularity keep unknown works last', () {
    final older = WorkEntry.create(workId: '42')
        .copyWith(sourceDate: '2025-01-01');
    final newer = WorkEntry.create(workId: '256')
        .copyWith(sourceDate: '2026-01-01');
    final unknown = WorkEntry.create(workId: '19');
    expect(WorkSorting.sort([older, unknown, newer],
        LibrarySort.published).map((w) => w.workId),
        ['256', '42', '19']);
    final list = WorkSorting.sort([older, unknown, newer],
        LibrarySort.hitomiPopular,
        popularityRanks: {'42': 1, '256': 2});
    expect(list.map((w) => w.workId), ['42', '256', '19']);
    expect(WorkSorting.sort([older, unknown, newer],
        LibrarySort.hitomiPopular, descending: true,
        popularityRanks: {'42': 1, '256': 2})
        .last.workId, '19');
  });

  test('episode number wins over gallery date; fallback uses numeric ID', () {
    final ep2 = WorkEntry.create(workId: '5', title: 'Story 2편')
        .copyWith(sourceDate: '2020-01-01');
    final ep1 = WorkEntry.create(workId: '20', title: 'Story 1편')
        .copyWith(sourceDate: '2026-01-01');
    expect(WorkGrouping.compareChapters(ep1, ep2), lessThan(0));
    final x = WorkEntry.create(workId: '20');
    final y = WorkEntry.create(workId: '5');
    expect(WorkGrouping.compareChapters(y, x), lessThan(0));
  });
  test('Auto grouping uses title-specific episodes, not shared Shorts comments', () {
    const comments = '1편 - 2900년 7월 56일\n2편 - 317시간 28분 01초';
    final a = WorkEntry.create(workId: '2900756', videoId: 'short',
        title: '멋대로 눌러앉은 유령 1편', originalComment: comments);
    final b = WorkEntry.create(workId: '3172801', videoId: 'short',
        title: '멋대로 눌러앉은 유령 2편', originalComment: comments);
    expect(WorkGrouping.episodeNumber(a), 1);
    expect(WorkGrouping.episodeNumber(b), 2);
    final proposals = WorkGrouping.suggest([b, a]);
    expect(proposals.single.workIds, ['2900756', '3172801']);
  });

  test('different series in a Shorts are never grouped merely by videoId', () {
    final a = WorkEntry.create(workId: '100001', videoId: 'shared',
        title: '기차 여행 1편');
    final b = WorkEntry.create(workId: '100002', videoId: 'shared',
        title: '비행기 여행 2편');
    expect(WorkGrouping.suggest([a, b]), isEmpty);
  });

  test('same series across Shorts without episode numbers is suggested', () {
    final a = WorkEntry.create(workId: '100001', videoId: 'short1',
        title: '내가 생각한 최강의 수학여행', author: 'kakuninii');
    final b = WorkEntry.create(workId: '100002', videoId: 'short2',
        title: '내가 생각한 최강의 수학여행', author: 'kakuninii');
    final proposals = WorkGrouping.suggest([a, b]);
    expect(proposals, hasLength(1));
    expect(proposals.single.workIds.toSet(), {'100001','100002'});
    expect(proposals.single.confidence, greaterThan(75));
  });

  test('new work can be proposed for an existing group without altering it', () {
    final a = WorkEntry.create(workId: '100001',
        title: '수학여행 1편').copyWith(groupId: 'series_one',
        groupTitle: '수학여행 모음', groupOrder: 1);
    final b = WorkEntry.create(workId: '100002', title: '수학여행 2편');
    final suggestions = WorkGrouping.suggest([a, b]);
    expect(suggestions.single.existingGroupId, 'series_one');
    expect(suggestions.single.workIds, ['100002']);
    expect(suggestions.single.title, '수학여행 모음');
  });

  test('compilation range is not mistaken for a single episode', () {
    final combined = WorkEntry.create(workId: '600003',
        title: '모험 이야기 (1~3화 합본 + 번외편)');
    final first = WorkEntry.create(workId: '600001',
        title: '모험 이야기 1화');
    expect(WorkGrouping.episodeNumber(combined), isNull);
    expect(WorkGrouping.episodeRange(combined.title)?.start, 1);
    expect(WorkGrouping.episodeRange(combined.title)?.end, 3);
    expect(WorkGrouping.baseTitle(combined.title),
        WorkGrouping.baseTitle(first.title));
    final suggestions = WorkGrouping.suggest([first, combined]);
    expect(suggestions, hasLength(1));
    expect(suggestions.single.workIds.toSet(), {'600001', '600003'});
    expect(suggestions.single.reason, contains('파생'));
  });

  test('same creator does not cause unrelated title chain grouping', () {
    final a = WorkEntry.create(workId: '700001',
        title: '첫번째 세계 이야기 1화', author: 'Maker');
    final b = WorkEntry.create(workId: '700002',
        title: '첫번째 세계 이야기 2화', author: 'Maker');
    final c = WorkEntry.create(workId: '700003',
        title: '완전히 다른 만화', author: 'Maker');
    final groups = WorkGrouping.suggest([a, b, c]);
    expect(groups.single.workIds.toSet(), {'700001', '700002'});
  });

  test('comment episode is used only on its own work-id line', () {
    const comments = '1편 - 2900년 7월 56일\n2편 - 317시간 28분 01초';
    final a = WorkEntry.create(workId: '2900756',
        title: '수학여행', originalComment: comments);
    final b = WorkEntry.create(workId: '3172801',
        title: '수학여행', originalComment: comments);
    final c = WorkEntry.create(workId: '888888',
        title: '다른 작품', originalComment: comments);
    expect(WorkGrouping.episodeNumber(a), 1);
    expect(WorkGrouping.episodeNumber(b), 2);
    expect(WorkGrouping.episodeNumber(c), isNull);
  });


  test('fuzzy titles need no creator metadata', () {
    final a = WorkEntry.create(workId: '800001',
        title: '내가 생각한 최강의 수학여행');
    final b = WorkEntry.create(workId: '800002',
        title: '내가 생각한 최강 수학여행');
    final proposals = WorkGrouping.suggest([a, b]);
    expect(proposals, hasLength(1));
    expect(proposals.single.workIds.toSet(), {'800001', '800002'});
  });

  test('shortened title plus special edition is suggested for review', () {
    final a = WorkEntry.create(workId: '800011',
        title: '내가 생각한 최강의 수학여행');
    final b = WorkEntry.create(workId: '800012',
        title: '최강의 수학여행 특별편');
    final proposals = WorkGrouping.suggest([a, b]);
    expect(proposals, hasLength(1));
    expect(proposals.single.workIds.toSet(), {'800011', '800012'});
    expect(proposals.single.reason, contains('파생'));
  });

  test('60 to 70 percent title match passes with creator evidence', () {
    final a = WorkEntry.create(workId: '800021',
        title: '가상의 세계 모험담', author: 'Maker');
    final b = WorkEntry.create(workId: '800022',
        title: '가상의 세계 이야기', author: 'Maker');
    expect(WorkGrouping.suggest([a, b]), hasLength(1));
  });

  test('two substantive shared title words create a broad suggestion', () {
    final a = WorkEntry.create(workId: '800031',
        title: '별빛공원 조용한 사계절 휴가');
    final b = WorkEntry.create(workId: '800032',
        title: '별빛공원 조용한 추억의 이야기');
    final proposals = WorkGrouping.suggest([a, b]);
    expect(proposals, hasLength(1));
    expect(proposals.single.confidence, lessThan(70));
    expect(proposals.single.reason, contains('폭넓게'));
  });

  test('unnumbered different language copies do not become series', () {
    final a = WorkEntry.create(workId: '800041',
        title: 'Summer Memory').copyWith(sourceLanguage: 'japanese');
    final b = WorkEntry.create(workId: '800042',
        title: 'Summer Memory | 여름의 추억')
        .copyWith(sourceLanguage: 'korean');
    expect(WorkGrouping.suggest([a, b]), isEmpty);
  });

  test('different-numbered chapters remain eligible across languages', () {
    final a = WorkEntry.create(workId: '800051',
        title: 'Summer Memory 1').copyWith(sourceLanguage: 'japanese');
    final b = WorkEntry.create(workId: '800052',
        title: 'Summer Memory 2').copyWith(sourceLanguage: 'korean');
    expect(WorkGrouping.suggest([a, b]), hasLength(1));
  });

  test('similarity chains cannot absorb unrelated endpoints', () {
    final a = WorkEntry.create(workId: '800061',
        title: '바닷가에서 즐긴 여름방학');
    final bridge = WorkEntry.create(workId: '800062',
        title: '바닷가에서 즐긴 겨울방학');
    final c = WorkEntry.create(workId: '800063',
        title: '산속에서 즐긴 겨울방학');
    final proposals = WorkGrouping.suggest([a, bridge, c]);
    expect(proposals, hasLength(1));
    expect(proposals.single.workIds.toSet(), {'800061', '800062'});
  });

  test('same creator with unrelated titles is not suggested', () {
    final a = WorkEntry.create(workId: '800071',
        title: '푸른 별과 여름 바다', author: 'Same');
    final b = WorkEntry.create(workId: '800072',
        title: '기차를 타고 떠난 우주', author: 'Same');
    expect(WorkGrouping.suggest([a, b]), isEmpty);
  });

}
