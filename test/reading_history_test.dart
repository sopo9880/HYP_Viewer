import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/reading_history.dart';
import 'package:hyp_viewer/core/work.dart';

void main() {
  test('activity tracker caps idle gaps, pauses in background', () {
    final start = DateTime.utc(2026, 10, 15, 1);
    final tracker = ReadingActivityTracker('12', 1, now: start);
    tracker.pageChanged(2, now: start.add(const Duration(minutes: 6)));
    tracker.pause(now: start.add(const Duration(minutes: 7)));
    tracker.resume(now: start.add(const Duration(hours: 3)));
    final session = tracker.finish(now: start.add(const Duration(hours: 3, seconds: 20)));
    expect(session.activeSeconds, 200);
    expect(session.startPage, 1);
    expect(session.endPage, 2);
  });

  test('history round-trip survives restart and clear', () async {
    final dir = await Directory.systemTemp.createTemp('hyp_sessions_');
    addTearDown(() => dir.delete(recursive: true));
    final store = ReadingHistoryStore(baseDirectory: dir);
    final now = DateTime.utc(2026, 10, 15);
    final session = ReadingSession(workId: '321',
      startedAt: now, endedAt: now.add(const Duration(minutes: 1)),
      startPage: 1, endPage: 12, activeSeconds: 60, completed: false);
    await store.save([session]);
    final restored = await store.load();
    expect(restored.single.workId, '321');
    expect(restored.single.activeSeconds, 60);
    await store.clear();
    expect(await store.load(), isEmpty);
  });

  test('insights use real saved reads/tags instead of guessing', () {
    final a = WorkEntry.create(workId: '1').copyWith(
      tags: ['romance', 'romance', 'slice_of_life'], openCount: 5,
      favorite: true, completed: true);
    final b = WorkEntry.create(workId: '2').copyWith(
      tags: ['romance'], openCount: 1);
    final tags = ReadingInsights.tagStats([a,b]);
    expect(tags.first.name, 'romance');
    expect(tags.first.works, 2);
    expect(tags.first.reads, 6);
    expect(tags.first.favorites, 1);
  });
}
