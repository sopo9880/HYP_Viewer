import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/storage.dart';
import 'package:hyp_viewer/core/work.dart';

void main() {
  test('serializes rapid saves and keeps a previous valid backup', () async {
    final dir = await Directory.systemTemp.createTemp('hyp-library-');
    addTearDown(() => dir.delete(recursive: true));
    final store = LibraryStorage(baseDirectory: dir);
    LibraryBackup atPage(int page) => LibraryBackup(
      works: [WorkEntry.create(workId: '123456').copyWith(currentPage: page)],
      collections: const [],
    );
    await store.save(atPage(1));
    // Rapid fire simulates slider changes while the previous file save is in
    // progress. Every task must complete and the last one must win.
    await Future.wait([
      for (var page = 2; page <= 18; page++) store.save(atPage(page)),
    ]);
    expect((await store.load()).works.single.currentPage, 18);
    final previous = File((await store.file).path + '.previous');
    expect(await previous.exists(), true);
    expect(LibraryBackup.decode(await previous.readAsString())
        .works.single.currentPage, 17);

    final names = await dir.list().map((e) => e.path).toList();
    expect(names.where((name) => name.contains('.tmp.')), isEmpty);
  });

  test('recovers previous JSON if live file is absent', () async {
    final dir = await Directory.systemTemp.createTemp('hyp-library-prev-');
    addTearDown(() => dir.delete(recursive: true));
    final store = LibraryStorage(baseDirectory: dir);
    await store.save(LibraryBackup(
      works: [WorkEntry.create(workId: '321')],
      collections: const [],
    ));
    final path = (await store.file).path;
    await File(path).rename(path + '.previous');
    expect((await store.load()).works.single.workId, '321');
  });
}
