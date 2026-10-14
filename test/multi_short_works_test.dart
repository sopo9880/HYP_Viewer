import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/number_extractor.dart';
import 'package:hyp_viewer/core/work.dart';

void main() {
  test('two gallery codes from the same Shorts survive a library merge', () {
    const video = 'cY9STsWLA-Y';
    final first = WorkEntry.create(
      workId: '2711759', videoId: video,
      videoUrl: 'https://www.youtube.com/shorts/$video',
      title: '1편',
    );
    final second = WorkEntry.create(
      workId: '2951072', videoId: video,
      videoUrl: 'https://www.youtube.com/shorts/$video',
      title: '2편',
    );
    expect(first.key, isNot(second.key));
    final saved = LibraryBackup.merge(
      const LibraryBackup(works: [], collections: []),
      LibraryBackup(works: [first, second], collections: const []),
    );
    expect(saved.works.map((w) => w.workId).toSet(),
        {'2711759', '2951072'});
    final restored = LibraryBackup.decode(saved.encode());
    expect(restored.works.length, 2);
    final edited = LibraryBackup.merge(restored,
        LibraryBackup(works: [second.copyWith(favorite: true)],
            collections: const []));
    expect(edited.works.length, 2);
    expect(edited.works.singleWhere((w) => w.workId == '2951072').favorite,
        isTrue);
  });

  test('part 1 and part 2 codes on a single line remain distinct', () {
    final codes = NumberExtractor.extract(
      '1편 작품번호 2711759 / 2편 작품번호 2951072',
    ).map((e) => e.code).toSet();
    expect(codes, {'2711759', '2951072'});
  });

  test('multiple thousand-unit phrases and gallery links are supported', () {
    final shorthand = NumberExtractor.extract(
      '1편 271만 1759시간, 2편 295만 1072시간',
    ).map((e) => e.code).toSet();
    expect(shorthand.containsAll(['2711759', '2951072']), true);
    final links = NumberExtractor.extract(
      '1편 https://hitomi.la/reader/2711759.html '
      '2편 https://hitomi.la/reader/2951072.html',
    ).map((e) => e.code).toSet();
    expect(links, {'2711759', '2951072'});
  });
}
