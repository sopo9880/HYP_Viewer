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
}
