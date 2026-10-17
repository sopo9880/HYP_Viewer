import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/reader_settings.dart';
import 'package:hyp_viewer/core/work.dart';
import 'package:hyp_viewer/core/work_edition_service.dart';
import 'package:hyp_viewer/core/work_grouping.dart';

void main() {
  test('v0.4.7 defaults and legacy backups retain safe settings', () {
    final old = ReaderSettings.fromJson({'languageCode': 'ko'});
    expect(old.deleteLocalFilesByDefault, isTrue);
    expect(old.closeWindowExitsApp, isFalse);
    final changed = old.copyWith(
      deleteLocalFilesByDefault: false, closeWindowExitsApp: true);
    final restored = ReaderSettings.fromJson(changed.toJson());
    expect(restored.deleteLocalFilesByDefault, isFalse);
    expect(restored.closeWindowExitsApp, isTrue);
  });

  test('Petunia and after story are proposed in correct order', () {
    final a = WorkEntry.create(workId: '2441018',
        title: 'Petunia', author: 'danimaru');
    final b = WorkEntry.create(workId: '2528782',
        title: 'Petunia ~after story~', author: 'danimaru');
    expect(WorkGrouping.normalizedSeries(a.title),
        WorkGrouping.normalizedSeries(b.title));
    final suggestions = WorkGrouping.suggest([b, a]);
    expect(suggestions, hasLength(1));
    expect(suggestions.first.workIds, ['2441018', '2528782']);
    expect(WorkGrouping.compareChapters(a, b), lessThan(0));
  });

  test('moving series chapter keeps all language editions and progress', () {
    final ja = WorkEntry.create(workId: '101', title: 'Story 2')
        .copyWith(groupId: 'source', groupTitle: 'Original',
          groupOrder: 2, editionGroupId: 'edition2',
          currentPage: 22, completed: true);
    final ko = WorkEntry.create(workId: '102', title: 'Story 2')
        .copyWith(groupId: 'source', groupTitle: 'Original',
          groupOrder: 2, editionGroupId: 'edition2', currentPage: 9);
    final first = WorkEntry.create(workId: '100', title: 'Story 1')
        .copyWith(groupId: 'source', groupTitle: 'Original', groupOrder: 1);
    final dest1 = WorkEntry.create(workId: '201', title: 'Dest 1')
        .copyWith(groupId: 'target', groupTitle: 'Target', groupOrder: 1);
    final dest2 = WorkEntry.create(workId: '202', title: 'Dest 2')
        .copyWith(groupId: 'target', groupTitle: 'Target', groupOrder: 2);
    final source = LibraryBackup(
      works: [ja, ko, first, dest1, dest2], collections: const []);
    final moved = WorkEditionService.moveBetweenSeries(
        source, 'source', 'target', ['101']);
    expect(moved.works[0].groupId, 'target');
    expect(moved.works[1].groupId, 'target');
    expect(moved.works[0].groupOrder, moved.works[1].groupOrder);
    expect(moved.works[0].currentPage, 22);
    expect(moved.works[0].completed, isTrue);
    expect(moved.works[2].groupId, isEmpty);
    expect(source.works[0].groupId, 'source');
  });
}
