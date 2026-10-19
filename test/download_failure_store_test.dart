import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/download_failure_store.dart';
import 'package:hyp_viewer/core/download_queue_store.dart';

void main() {
  test('terminal failures persist separately from queued jobs', () async {
    final dir = await Directory.systemTemp.createTemp('hyp-failed-downloads');
    addTearDown(() => dir.delete(recursive: true));
    final queue = DownloadQueueStore(baseDirectory: dir);
    final failures = DownloadFailureStore(baseDirectory: dir);
    await queue.addAll(['3538281', '3603632']);
    await failures.record('3538281', source: 'hitomi',
        code: 'META_ID_MISMATCH');
    // Queue processing discards only the failed work, not the next one.
    await queue.remove('3538281');
    final persisted = await DownloadFailureStore(baseDirectory: dir).load();
    expect(persisted.keys, {'3538281'});
    expect(persisted['3538281']!.code, 'META_ID_MISMATCH');
    expect(persisted['3538281']!.source, 'hitomi');
    expect(await DownloadQueueStore(baseDirectory: dir).load(),
        {'3603632': 'hitomi'});
    await failures.remove('3538281');
    expect(await DownloadFailureStore(baseDirectory: dir).load(), isEmpty);
  });

  test('manual JSON source retries retain the original source', () async {
    final dir = await Directory.systemTemp.createTemp('hyp-failed-json');
    addTearDown(() => dir.delete(recursive: true));
    final failures = DownloadFailureStore(baseDirectory: dir);
    await failures.record('2711759', source: 'json',
        code: 'DOWNLOAD_NETWORK_FAILED');
    final restored = await DownloadFailureStore(baseDirectory: dir).load();
    expect(restored['2711759']!.source, 'json');
    await failures.remove('2711759');
    await DownloadQueueStore(baseDirectory: dir).add(
        '2711759', source: restored['2711759']!.source);
    expect(await DownloadQueueStore(baseDirectory: dir).load(),
        {'2711759': 'json'});
  });

  test('never store unsafe IDs, arbitrary sources or raw exception text',
      () async {
    final dir = await Directory.systemTemp.createTemp('hyp-failed-safe');
    addTearDown(() => dir.delete(recursive: true));
    final failures = DownloadFailureStore(baseDirectory: dir);
    expect(() => failures.record('../bad', source: 'hitomi',
        code: 'META_ID_MISMATCH'), throwsFormatException);
    expect(() => failures.record('3538281', source: 'external',
        code: 'META_ID_MISMATCH'), throwsArgumentError);
    expect(() => failures.record('3538281', source: 'hitomi',
        code: 'https://private.example.com'), throwsArgumentError);
    expect(await failures.load(), isEmpty);
  });

  test('clearing all failures persists across restart but keeps queue and files',
      () async {
    final dir = await Directory.systemTemp.createTemp('hyp-failed-clear');
    addTearDown(() => dir.delete(recursive: true));
    final failures = DownloadFailureStore(baseDirectory: dir);
    final jobs = DownloadQueueStore(baseDirectory: dir);
    final existingArchive = File(dir.path + '/already-downloaded.cbz');
    await existingArchive.writeAsBytes([80, 75, 3, 4], flush: true);

    await failures.record('3538281', source: 'hitomi',
        code: 'META_ID_MISMATCH');
    await failures.record('2711759', source: 'json',
        code: 'DOWNLOAD_NETWORK_FAILED');
    await jobs.add('1234567');
    expect((await failures.load()).length, 2);

    await failures.clear();

    expect(await DownloadFailureStore(baseDirectory: dir).load(), isEmpty);
    expect(await DownloadQueueStore(baseDirectory: dir).load(),
        {'1234567': 'hitomi'});
    expect(await existingArchive.readAsBytes(), [80, 75, 3, 4]);

    // Dismissal does not permanently ban a gallery. A *new* explicit
    // download that fails can create a new record.
    await failures.record('3538281', source: 'hitomi',
        code: 'DOWNLOAD_TIMEOUT');
    expect((await DownloadFailureStore(baseDirectory: dir).load()).keys,
        {'3538281'});
  });

  test('record, dismiss, clear and later record stay serialized', () async {
    final dir = await Directory.systemTemp.createTemp('hyp-failed-race');
    addTearDown(() => dir.delete(recursive: true));
    final failures = DownloadFailureStore(baseDirectory: dir);

    await Future.wait([
      failures.record('11', source: 'hitomi', code: 'DOWNLOAD_TIMEOUT'),
      failures.record('22', source: 'json', code: 'DOWNLOAD_FAILED'),
      failures.remove('11'),
      failures.clear(),
      failures.record('33', source: 'hitomi', code: 'META_ID_MISMATCH'),
    ]);

    final persisted = await DownloadFailureStore(baseDirectory: dir).load();
    expect(persisted.keys, {'33'});
    expect(persisted['33']!.code, 'META_ID_MISMATCH');
  });

  test('corrupt failure record is not silently wiped by clear', () async {
    final dir = await Directory.systemTemp.createTemp('hyp-failed-corrupt');
    addTearDown(() => dir.delete(recursive: true));
    final journal = File(dir.path + '/hyp_download_failures.json');
    await journal.writeAsString('not valid JSON');
    final failures = DownloadFailureStore(baseDirectory: dir);

    await expectLater(failures.clear(), throwsStateError);
    expect(await journal.readAsString(), 'not valid JSON');
  });


  test('repeated blocked retry warning is quiet until blocked IDs change',
      () {
    final policy = TerminalFailureNoticePolicy();
    expect(policy.shouldNotify(const <String>[]), isFalse);
    expect(policy.shouldNotify(['3538281', '2711759']), isTrue);
    expect(policy.shouldNotify(['2711759', '3538281']), isFalse);
    expect(policy.shouldNotify(['3538281', '2711759', '2711759']), isFalse);
    expect(policy.shouldNotify(['3538281']), isTrue);
    expect(policy.shouldNotify(['3538281']), isFalse);
    policy.reset();
    expect(policy.shouldNotify(['3538281']), isTrue);
    expect(policy.shouldNotify(const <String>[]), isFalse);
  });

}
