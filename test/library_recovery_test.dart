import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/storage.dart';
import 'package:hyp_viewer/core/work.dart';

void main() {
  test('damaged primary library falls back to intact previous copy',
      () async {
    final dir = await Directory.systemTemp.createTemp('hyp-recovery-');
    addTearDown(() => dir.delete(recursive: true));
    final store = LibraryStorage(baseDirectory: dir);
    final main = await store.file;
    final work = WorkEntry.create(workId: '2900756', title: 'preserved');
    await File(main.path + '.previous').writeAsString(
      LibraryBackup(works: [work], collections: const []).encode());
    await main.writeAsString('{corrupted-json');
    final recovered = await store.load();
    expect(recovered.works.single.workId, '2900756');
    // Loading must not destroy the damaged primary or the rollback copy.
    expect(await main.readAsString(), '{corrupted-json');
    expect(await File(main.path + '.previous').exists(), true);
    expect((await store.readPrevious())!.works.single.workId, '2900756');
  });

  test('both damaged backups fail closed rather than returning empty library',
      () async {
    final dir = await Directory.systemTemp.createTemp('hyp-fail-closed-');
    addTearDown(() => dir.delete(recursive: true));
    final store = LibraryStorage(baseDirectory: dir);
    final main = await store.file;
    await main.writeAsString('corrupt');
    await File(main.path + '.previous').writeAsString('also corrupt');
    await expectLater(store.load(), throwsStateError);
  });

  test('staged valid backup can be read after interrupted atomic save',
      () async {
    final dir = await Directory.systemTemp.createTemp('hyp-stage-');
    addTearDown(() => dir.delete(recursive: true));
    final store = LibraryStorage(baseDirectory: dir);
    final main = await store.file;
    final staged = File(main.path + '.tmp.1000000.1');
    await staged.writeAsString(LibraryBackup(
        works: [WorkEntry.create(workId: '3172801')],
        collections: const []).encode());
    expect((await store.load()).works.single.workId, '3172801');
  });
}
