import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/cover_store.dart';
import 'package:hyp_viewer/core/gallery.dart';
import 'package:hyp_viewer/core/storage.dart';
import 'package:hyp_viewer/core/work.dart';

void main() {
  test('remove one of two Shorts works without deleting the other', () {
    final first = WorkEntry.create(workId: '2711759',
        videoId: 'cY9STsWLA-Y').copyWith(
          favorite: true, currentPage: 37, collections: ['A']);
    final second = WorkEntry.create(workId: '2951072',
        videoId: 'cY9STsWLA-Y').copyWith(
          favorite: true, currentPage: 9);
    final library = LibraryBackup(
      works: [first, second], collections: const ['A', 'B'],
    );
    final remaining = library.withoutWork('2711759');
    expect(remaining.works, hasLength(1));
    expect(remaining.works.single.workId, '2951072');
    expect(remaining.works.single.currentPage, 9);
    expect(remaining.works.single.favorite, true);
    expect(remaining.collections, ['A', 'B']);
    expect(library.works, hasLength(2));
    expect(LibraryBackup.decode(remaining.encode()).works.single.workId,
        '2951072');
    expect(remaining.withoutWork('2711759').works, hasLength(1));
  });

  test('library deletion survives disk reload but local files remain',
      () async {
    final dir = await Directory.systemTemp.createTemp('hyp-delete-entry-');
    addTearDown(() => dir.delete(recursive: true));
    final storage = LibraryStorage(baseDirectory: dir);
    final book = WorkEntry.create(workId: '1234567');
    await storage.save(LibraryBackup(works: [book], collections: const []));
    final cbzDir = Directory('${dir.path}${Platform.pathSeparator}galleries');
    await cbzDir.create(recursive: true);
    final cbz = File('${cbzDir.path}${Platform.pathSeparator}1234567.cbz');
    await cbz.writeAsBytes([1, 2, 3]);
    await storage.save((await storage.load()).withoutWork('1234567'));
    expect((await storage.load()).works, isEmpty);
    expect(await GalleryStore(baseDirectory: dir).exists('1234567'), true);
    expect(await cbz.exists(), true);
  });

  test('local file deletion cleans only targeted gallery and cover files',
      () async {
    final dir = await Directory.systemTemp.createTemp('hyp-delete-files-');
    addTearDown(() => dir.delete(recursive: true));
    final galleries = Directory('${dir.path}${Platform.pathSeparator}galleries');
    final covers = Directory('${dir.path}${Platform.pathSeparator}covers');
    await galleries.create(recursive: true);
    await covers.create(recursive: true);
    final ownCbz = File('${galleries.path}${Platform.pathSeparator}123.cbz');
    final anotherCbz = File('${galleries.path}${Platform.pathSeparator}1234.cbz');
    await ownCbz.writeAsBytes([1]);
    await anotherCbz.writeAsBytes([2]);
    final removeNames = ['123_auto.png','123_custom.png','123_page_7.png'];
    for (final name in [...removeNames, '1234_auto.png','123_page_7.jpg']) {
      await File('${covers.path}${Platform.pathSeparator}$name').writeAsBytes([1]);
    }
    await GalleryStore(baseDirectory: dir).delete('123');
    await CoverStore(baseDirectory: dir).deleteAllForWork('123');
    expect(await ownCbz.exists(), false);
    expect(await anotherCbz.exists(), true);
    for (final name in removeNames) {
      expect(await File('${covers.path}${Platform.pathSeparator}$name').exists(), false);
    }
    expect(await File('${covers.path}${Platform.pathSeparator}1234_auto.png').exists(), true);
    expect(await File('${covers.path}${Platform.pathSeparator}123_page_7.jpg').exists(), true);
    await expectLater(CoverStore(baseDirectory: dir).deleteAllForWork('../123'),
        throwsFormatException);
  });
}
