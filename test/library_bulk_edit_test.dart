import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/work.dart';

void main() {
  test('bulk deletion removes only selected IDs, retaining all other data', () {
    final a = WorkEntry.create(workId: '1000001').copyWith(favorite: true);
    final b = WorkEntry.create(workId: '1000002');
    final c = WorkEntry.create(workId: '1000003').copyWith(currentPage: 79);
    final shelf = LibraryBackup(
      works: [a, b, c], collections: const ['favorites', 'reading']);
    final trimmed = shelf.withoutWorks({'1000001', '1000002'});
    expect(trimmed.works.map((w) => w.workId), ['1000003']);
    expect(trimmed.works.single.currentPage, 79);
    expect(trimmed.collections, ['favorites', 'reading']);
    expect(shelf.works.length, 3);
    expect(shelf.withoutWorks({}).works.length, 3);
  });

  test('rekey preserves progress and forbids duplicates without permission', () {
    final original = WorkEntry.create(workId: '23172801', title: 'Incorrect')
        .copyWith(favorite: true, currentPage: 22,
        collections: ['recent'], completed: true);
    final target = WorkEntry.create(workId: '3172801', title: 'Existing')
        .copyWith(currentPage: 35, coverMode: 'custom');
    final backup = LibraryBackup(works: [original, target],
        collections: const ['recent']);
    final corrected = original.copyWith(
        workId: '3172801', title: 'Corrected', author: 'Artist');
    expect(() => backup.editWork(originalWorkId: original.workId,
        edited: corrected), throwsStateError);
    final combined = backup.editWork(
        originalWorkId: original.workId, edited: corrected,
        mergeDuplicate: true);
    expect(combined.works, hasLength(1));
    expect(combined.works.single.workId, '3172801');
    expect(combined.works.single.favorite, true);
    expect(combined.works.single.completed, true);
    expect(combined.works.single.currentPage, 35);
    expect(combined.works.single.coverMode, 'custom');
    expect(combined.works.single.collections, contains('recent'));
  });

  test('rekey to free ID retains all editing fields', () {
    final source = WorkEntry.create(workId: '23172801', title: 'Before')
        .copyWith(currentPage: 12, favorite: true, coverMode: 'custom');
    final library = LibraryBackup(works: [source], collections: const []);
    final changed = library.editWork(originalWorkId: source.workId,
        edited: source.copyWith(workId: '3172801', title: 'After'));
    expect(changed.works.single.workId, '3172801');
    expect(changed.works.single.title, 'After');
    expect(changed.works.single.currentPage, 12);
    expect(changed.works.single.favorite, true);
    // Presentation layer resets custom cover on ID change; rekey itself does
    // not migrate CBZ/cover files as those are keyed by workId on disk.
  });
}
