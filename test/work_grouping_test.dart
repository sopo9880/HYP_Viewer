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
    expect(groups.first.workIds, ['2900756', '3172801']);
    expect(three.groupId, 'existing');
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
}
