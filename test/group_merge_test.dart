import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/work.dart';
import 'package:hyp_viewer/core/work_edition_service.dart';
import 'package:hyp_viewer/core/work_grouping.dart';

void main() {
  test('flatten two groups and a work, preserving progress and order', () {
    final a = WorkEntry.create(workId: '100001', title: 'Series 1')
        .copyWith(groupId: 'a', groupTitle: 'A', groupOrder: 1,
            currentPage: 9, completed: true);
    final b = WorkEntry.create(workId: '100002', title: 'Series 2')
        .copyWith(groupId: 'a', groupTitle: 'A', groupOrder: 2);
    final c = WorkEntry.create(workId: '100003', title: 'Series 3')
        .copyWith(groupId: 'b', groupTitle: 'B', groupOrder: 1);
    final d = WorkEntry.create(workId: '100004', title: 'Series 4')
        .copyWith(groupId: 'b', groupTitle: 'B', groupOrder: 2);
    final e = WorkEntry.create(workId: '100005', title: 'Series 5');
    final merged = WorkEditionService.mergeSeries(
      LibraryBackup(works: [a, b, c, d, e], collections: const ['keep']),
      [a.workId, b.workId, c.workId, d.workId, e.workId], 'merged', 'All');
    expect(merged.works.map((w) => w.groupId).toSet(), {'merged'});
    expect(merged.works.map((w) => w.groupOrder).toList(), [1, 2, 3, 4, 5]);
    expect(merged.works.first.currentPage, 9);
    expect(merged.works.first.completed, isTrue);
    expect(merged.collections, ['keep']);
  });

  test('partial existing group merge is rejected before mutation', () {
    final a = WorkEntry.create(workId: '100001')
        .copyWith(groupId: 'a', groupTitle: 'A');
    final b = WorkEntry.create(workId: '100002')
        .copyWith(groupId: 'a', groupTitle: 'A');
    final c = WorkEntry.create(workId: '100003');
    final input = LibraryBackup(works: [a, b, c], collections: const []);
    expect(() => WorkEditionService.mergeSeries(
        input, [a.workId, c.workId], 'new', 'New'), throwsStateError);
    expect(input.works.first.groupId, 'a');
  });

  test('preserves language editions as a logical chapter', () {
    final ja = WorkEntry.create(workId: '100001')
        .copyWith(editionGroupId: 'ed1', groupId: 'a', groupTitle: 'A');
    final ko = WorkEntry.create(workId: '100002')
        .copyWith(editionGroupId: 'ed1', groupId: 'a', groupTitle: 'A');
    final another = WorkEntry.create(workId: '100003')
        .copyWith(groupId: 'a', groupTitle: 'A');
    final loose = WorkEntry.create(workId: '100004');
    final result = WorkEditionService.mergeSeries(
      LibraryBackup(works: [ja, ko, another, loose], collections: const []),
      ['100001', '100003', '100004'], 'unified', 'One');
    expect(result.works[0].groupOrder, result.works[1].groupOrder);
    expect(result.works[1].editionGroupId, 'ed1');
    expect(result.works.every((w) => w.groupId == 'unified'), true);
  });

  test('different-language same chapters are not false series suggestions', () {
    final a = WorkEntry.create(workId: '100001',
        title: 'Same Story', author: 'Author')
        .copyWith(sourceLanguage: 'japanese', totalPages: 35);
    final b = WorkEntry.create(workId: '100002',
        title: 'Same Story', author: 'Author')
        .copyWith(sourceLanguage: 'korean', totalPages: 36);
    expect(WorkGrouping.suggest([a, b]), isEmpty);
  });
}
