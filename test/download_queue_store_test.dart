import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/download_queue_store.dart';

void main() {
  test('persisted queue survives a different store instance', () async {
    final dir = await Directory.systemTemp.createTemp('hyp-download-queue');
    addTearDown(() => dir.delete(recursive: true));
    final first = DownloadQueueStore(baseDirectory: dir);
    await first.addAll(['12', '34']);
    await first.add('56', source: 'json');
    final restored = DownloadQueueStore(baseDirectory: dir);
    expect(await restored.load(), {
      '12': 'hitomi', '34': 'hitomi', '56': 'json',
    });
    await restored.remove('34');
    final later = DownloadQueueStore(baseDirectory: dir);
    expect(await later.load(), {'12': 'hitomi', '56': 'json'});
    await later.clear();
    expect(await DownloadQueueStore(baseDirectory: dir).load(), isEmpty);
  });

  test('rejects bad IDs and never executes an unrecognized source', () async {
    final dir = await Directory.systemTemp.createTemp('hyp-download-guard');
    addTearDown(() => dir.delete(recursive: true));
    final queue = DownloadQueueStore(baseDirectory: dir);
    await expectLater(queue.add('../evil'), throwsFormatException);
    await expectLater(queue.add('123', source: 'external'),
        throwsArgumentError);
    expect(await queue.load(), isEmpty);
  });
}
