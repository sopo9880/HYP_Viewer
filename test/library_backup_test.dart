import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/work.dart';

void main() {
  test('JSON backup preserves reading fields', () {
    final original = WorkEntry.create(
      workId: '2711759',
      videoId: '-MK_XG2aflo',
      videoUrl: 'https://www.youtube.com/shorts/-MK_XG2aflo',
      title: 'Urahara',
      originalComment: '271만 1759시간',
    ).copyWith(
      favorite: true,
      currentPage: 12,
      collections: ['나중에 볼 작품'],
    );
    final backup = LibraryBackup(
      works: [original],
      collections: const ['나중에 볼 작품'],
    );
    final restored = LibraryBackup.decode(backup.encode());
    expect(restored.works.single.toJson(), original.toJson());
    expect(restored.collections, ['나중에 볼 작품']);
  });

  test('merge retains favorites and highest reading page', () {
    final base = WorkEntry.create(workId: '123456', videoId: 'abcdefghi12')
        .copyWith(currentPage: 33);
    final incoming = WorkEntry.create(workId: '123456', videoId: 'abcdefghi12')
        .copyWith(favorite: true, currentPage: 2);
    final result = LibraryBackup.merge(
      LibraryBackup(works: [base], collections: const []),
      LibraryBackup(works: [incoming], collections: const []),
    );
    expect(result.works.length, 1);
    expect(result.works.single.favorite, true);
    expect(result.works.single.currentPage, 33);
  });

  test('rejects unsupported JSON', () {
    expect(() => LibraryBackup.decode('{"works": []}'), throwsFormatException);
  });

  test('reading history survives JSON export and import', () {
    final opened = WorkEntry.create(
      workId: '2711759',
      title: '개인 서재 작품',
    ).copyWith(
      currentPage: 7,
      lastOpenedAt: '2026-10-14T01:00:00Z',
    );
    final backup = LibraryBackup(works: [opened], collections: const []);
    final restored = LibraryBackup.decode(backup.encode());
    expect(restored.works.single.lastOpenedAt, '2026-10-14T01:00:00.000Z');
    expect(restored.works.single.currentPage, 7);
  });

  test('backups preserve chosen cover and older imports use defaults', () {
    final chosen = WorkEntry.create(workId: '2711759').copyWith(
        coverMode: 'page', coverPage: 12, coverPreset: 3);
    final encoded = LibraryBackup(
        works: [chosen], collections: const []).encode();
    final restored = LibraryBackup.decode(encoded).works.single;
    expect(restored.coverMode, 'page');
    expect(restored.coverPage, 12);
    expect(restored.coverPreset, 3);

    final old = WorkEntry.fromJson(WorkEntry.create(workId: '123').toJson());
    expect(old.coverMode, 'auto');
    expect(old.coverPage, 1);
    final merged = LibraryBackup.merge(
      LibraryBackup(works: [chosen], collections: const []),
      LibraryBackup(works: [chosen.copyWith(coverMode: 'preset')],
          collections: const []),
    );
    expect(merged.works.single.coverMode, 'preset');
  });

  test('older v1 backup without lastOpenedAt remains compatible', () {
    final oldWork = WorkEntry.create(workId: '1234567');
    final restored = LibraryBackup.decode(
      LibraryBackup(works: [oldWork], collections: const []).encode(),
    );
    expect(restored.works.single.lastOpenedAt, isNull);
  });

  test('merging retains the most recent actual reading timestamp', () {
    final older = WorkEntry.create(workId: '1234567')
        .copyWith(lastOpenedAt: '2026-10-01T00:00:00Z');
    final newer = WorkEntry.create(workId: '1234567')
        .copyWith(lastOpenedAt: '2026-10-14T00:00:00Z');
    final merged = LibraryBackup.merge(
      LibraryBackup(works: [older], collections: const []),
      LibraryBackup(works: [newer], collections: const []),
    );
    expect(
      merged.works.single.lastOpenedAt, '2026-10-14T00:00:00Z',
    );
  });

}
