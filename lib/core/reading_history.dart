import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'work.dart';

/// A private on-device reading session. Time is estimated active time:
/// time between actions is capped to prevent overnight/background inflation.
class ReadingSession {
  final String workId;
  final DateTime startedAt;
  final DateTime endedAt;
  final int startPage;
  final int endPage;
  final int activeSeconds;
  final bool completed;

  const ReadingSession({
    required this.workId, required this.startedAt, required this.endedAt,
    required this.startPage, required this.endPage,
    required this.activeSeconds, required this.completed,
  });

  Map<String, Object> toJson() => {
    'workId': workId,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'endedAt': endedAt.toUtc().toIso8601String(),
    'startPage': startPage,
    'endPage': endPage,
    'activeSeconds': activeSeconds,
    'completed': completed,
  };

  factory ReadingSession.fromJson(Map<String, dynamic> raw) {
    final id = raw['workId'];
    final started = DateTime.tryParse(raw['startedAt'] is String
        ? raw['startedAt'] as String : '');
    final ended = DateTime.tryParse(raw['endedAt'] is String
        ? raw['endedAt'] as String : '');
    if (id is! String || !RegExp(r'^\d{1,12}$').hasMatch(id) ||
        started == null || ended == null || ended.isBefore(started)) {
      throw const FormatException('열람 기록 항목이 손상됐어.');
    }
    int safeInt(String key, int min, int max) => raw[key] is num
        ? (raw[key] as num).toInt().clamp(min, max).toInt() : min;
    return ReadingSession(
      workId: id, startedAt: started.toUtc(), endedAt: ended.toUtc(),
      startPage: safeInt('startPage', 1, 1000000),
      endPage: safeInt('endPage', 1, 1000000),
      activeSeconds: safeInt('activeSeconds', 0, 24 * 3600),
      completed: raw['completed'] == true,
    );
  }

  String get id => workId + ':' + startedAt.toIso8601String() +
      ':' + endedAt.toIso8601String();
}

/// Tracks a single active reader route, stopping the clock while backgrounded.
class ReadingActivityTracker {
  final String workId;
  final DateTime startedAt;
  final int startPage;
  int endPage;
  int _activeSeconds = 0;
  DateTime _last;
  bool _paused = false;
  bool completed = false;

  ReadingActivityTracker(this.workId, int page, {DateTime? now})
      : startedAt = (now ?? DateTime.now()).toUtc(),
        startPage = page,
        endPage = page,
        _last = (now ?? DateTime.now()).toUtc();

  void _credit(DateTime now) {
    if (!_paused) {
      final elapsed = now.difference(_last).inSeconds;
      if (elapsed > 0) _activeSeconds += elapsed.clamp(0, 120).toInt();
    }
    _last = now;
  }

  void pageChanged(int page, {DateTime? now}) {
    _credit((now ?? DateTime.now()).toUtc());
    endPage = page;
  }

  void pause({DateTime? now}) {
    _credit((now ?? DateTime.now()).toUtc());
    _paused = true;
  }

  void resume({DateTime? now}) {
    _last = (now ?? DateTime.now()).toUtc();
    _paused = false;
  }

  ReadingSession finish({DateTime? now}) {
    final ended = (now ?? DateTime.now()).toUtc();
    _credit(ended);
    return ReadingSession(
      workId: workId, startedAt: startedAt, endedAt: ended,
      startPage: startPage, endPage: endPage,
      activeSeconds: _activeSeconds.clamp(0, 24 * 3600).toInt(),
      completed: completed,
    );
  }
}

/// Separate from the schema-1 library file so frequent sessions don't
/// overwrite work metadata. JSON backups may optionally embed these records.
class ReadingHistoryStore {
  static const maxSessions = 10000;
  final Directory? baseDirectory;
  const ReadingHistoryStore({this.baseDirectory});

  Future<File> get file async {
    final root = baseDirectory ?? await getApplicationSupportDirectory();
    await root.create(recursive: true);
    return File(root.path + Platform.pathSeparator + 'hyp_reading_sessions.json');
  }

  static List<ReadingSession> decode(String content) {
    if (utf8.encode(content).length > 4 * 1024 * 1024) {
      throw const FormatException('열람 기록 JSON이 너무 커.');
    }
    final raw = jsonDecode(content);
    if (raw is! Map || raw['sessions'] is! List ||
        (raw['sessions'] as List).length > maxSessions) {
      throw const FormatException('열람 기록 JSON이 유효하지 않아.');
    }
    return (raw['sessions'] as List).map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('열람 기록 항목이 유효하지 않아.');
      }
      return ReadingSession.fromJson(item);
    }).toList();
  }

  static String encode(Iterable<ReadingSession> sessions) {
    final recent = sessions.toList();
    if (recent.length > maxSessions) {
      recent.removeRange(0, recent.length - maxSessions);
    }
    return jsonEncode({
      'schemaVersion': 1,
      'sessions': recent.map((session) => session.toJson()).toList(),
    });
  }

  Future<List<ReadingSession>> load() async {
    final location = await file;
    if (!await location.exists()) return const [];
    return decode(await location.readAsString());
  }

  Future<void> save(List<ReadingSession> sessions) async {
    final location = await file;
    final next = File(location.path + '.new');
    await next.writeAsString(encode(sessions), flush: true);
    // Keep a recovery copy before a replacement.
    if (await location.exists()) {
      final old = File(location.path + '.previous');
      await location.copy(old.path);
      await location.delete();
    }
    await next.rename(location.path);
  }

  Future<void> clear() async => save(const []);
}

class InsightTag {
  final String name;
  final int works;
  final int reads;
  final int favorites;
  final int completed;
  const InsightTag(this.name, this.works, this.reads,
      this.favorites, this.completed);
}

class ReadingInsights {
  static List<InsightTag> tagStats(Iterable<WorkEntry> works) {
    final counts = <String, List<int>>{};
    for (final work in works) {
      for (final tag in work.tags
          .map((s) => s.toLowerCase().trim())
          .where((s) => s.isNotEmpty).toSet()) {
        final count = counts.putIfAbsent(tag, () => [0, 0, 0, 0]);
        count[0]++;
        count[1] += work.openCount;
        if (work.favorite) count[2]++;
        if (work.completed) count[3]++;
      }
    }
    final stats = [for (final entry in counts.entries)
      InsightTag(entry.key, entry.value[0], entry.value[1],
          entry.value[2], entry.value[3])];
    stats.sort((a,b) {
      final difference = b.reads.compareTo(a.reads);
      return difference != 0 ? difference : b.works.compareTo(a.works);
    });
    return stats;
  }

  static Map<String, int> activityByDay(Iterable<ReadingSession> sessions) {
    final counts = <String, int>{};
    for (final item in sessions) {
      final key = item.startedAt.toLocal().toIso8601String().substring(0, 10);
      counts.update(key, (v) => v + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  static int activeSeconds(Iterable<ReadingSession> sessions) =>
      sessions.fold<int>(0, (sum, session) => sum + session.activeSeconds);

  static int streakDays(Iterable<ReadingSession> sessions, {DateTime? now}) {
    final days = activityByDay(sessions);
    final today = (now ?? DateTime.now()).toLocal();
    var day = DateTime(today.year, today.month, today.day);
    var count = 0;
    if (!days.containsKey(day.toIso8601String().substring(0, 10))) {
      day = day.subtract(const Duration(days: 1));
    }
    while (days.containsKey(day.toIso8601String().substring(0, 10))) {
      count++;
      day = day.subtract(const Duration(days: 1));
    }
    return count;
  }

  static List<(String, int)> topCreators(Iterable<WorkEntry> works,
      {bool circle = false}) {
    final count = <String, int>{};
    for (final work in works) {
      final raw = circle ? work.sourceGroup : work.author;
      for (final creator in raw.split(',').map((s) => s.trim())
          .where((s) => s.isNotEmpty).toSet()) {
        count.update(creator, (v) => v + work.openCount,
            ifAbsent: () => work.openCount);
      }
    }
    final entries = count.entries.toList()
      ..sort((a,b) => b.value.compareTo(a.value));
    return entries.map((entry) => (entry.key, entry.value)).toList();
  }

  static Map<String, List<WorkEntry>> series(Iterable<WorkEntry> works) {
    final grouped = <String, List<WorkEntry>>{};
    for (final work in works.where((w) => w.groupId.isNotEmpty)) {
      grouped.putIfAbsent(work.groupId, () => []).add(work);
    }
    return grouped;
  }
}
