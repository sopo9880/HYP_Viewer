import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A persisted queue entry may carry a user-approved, one-work size retry.
/// This affects configurable *soft* limits only, not absolute safety bounds.
class DownloadJob {
  final String source;
  final bool allowSizeOverride;
  const DownloadJob(this.source, {this.allowSizeOverride = false});
}

/// Persistent, user-authorized downloads. Library JSON never stores job state.
/// The queue is independent of the current screen and survives app restarts.
class DownloadQueueStore {
  final Directory? baseDirectory;
  DownloadQueueStore({this.baseDirectory});

  Future<Map<String, DownloadJob>>? _loaded;
  Future<void> _pendingWrite = Future<void>.value();

  Future<File> get _file async {
    final root = baseDirectory ?? await getApplicationSupportDirectory();
    await root.create(recursive: true);
    return File(root.path + Platform.pathSeparator + 'hyp_download_jobs.json');
  }

  /// Backward compatible caller API: work ID to provider source.
  Future<Map<String, String>> load() async {
    final jobs = await (_loaded ??= _read());
    return {for (final entry in jobs.entries) entry.key: entry.value.source};
  }

  Future<Set<String>> loadSizeOverrides() async {
    final jobs = await (_loaded ??= _read());
    return jobs.entries
        .where((entry) => entry.value.allowSizeOverride)
        .map((entry) => entry.key)
        .toSet();
  }

  Future<Map<String, DownloadJob>> _read() async {
    final file = await _file;
    var found = false;
    Object? lastError;
    for (final path in [file.path, file.path + '.previous']) {
      final candidate = File(path);
      if (!await candidate.exists()) continue;
      found = true;
      try {
        final parsed = jsonDecode(await candidate.readAsString());
        if (parsed is! Map || parsed['version'] != 1 ||
            parsed['jobs'] is! List) {
          throw const FormatException('다운로드 대기열이 손상됐어.');
        }
        final pending = <String, DownloadJob>{};
        for (final item in (parsed['jobs'] as List).take(5000)) {
          if (item is! Map) continue;
          final id = item['id'];
          final source = item['source'];
          if (id is String && RegExp(r'^\d{1,12}$').hasMatch(id) &&
              (source == 'hitomi' || source == 'json')) {
            pending[id] = DownloadJob(source as String,
                allowSizeOverride: item['allowSizeOverride'] == true);
          }
        }
        return pending;
      } catch (error) {
        lastError = error;
      }
    }
    if (found) {
      throw StateError('다운로드 대기열 복구 실패: ' + lastError.toString());
    }
    return <String, DownloadJob>{};
  }

  static void _checkId(String workId) {
    if (!RegExp(r'^\d{1,12}$').hasMatch(workId)) {
      throw const FormatException('잘못된 다운로드 작업 번호야.');
    }
  }

  static void _checkSource(String source) {
    if (source != 'hitomi' && source != 'json') {
      throw ArgumentError.value(source, 'source');
    }
  }

  /// Subsequent add() calls during transfer must never revoke an existing
  /// size exemption granted by the user on Retry.
  Future<void> add(String workId, {String source = 'hitomi',
      bool allowSizeOverride = false}) {
    _checkId(workId);
    _checkSource(source);
    return _mutate((jobs) {
      final existing = jobs[workId];
      jobs[workId] = DownloadJob(source, allowSizeOverride:
          allowSizeOverride || (existing?.allowSizeOverride ?? false));
    });
  }

  Future<void> addAll(Iterable<String> workIds, {String source = 'hitomi',
      bool allowSizeOverride = false}) {
    final ids = workIds.toSet();
    for (final id in ids) { _checkId(id); }
    _checkSource(source);
    return _mutate((jobs) {
      for (final id in ids) {
        final existing = jobs[id];
        jobs[id] = DownloadJob(existing?.source ?? source,
            allowSizeOverride:
                allowSizeOverride || (existing?.allowSizeOverride ?? false));
      }
    });
  }

  Future<void> remove(String workId) {
    _checkId(workId);
    return _mutate((jobs) => jobs.remove(workId));
  }

  Future<void> clear() => _mutate((jobs) => jobs.clear());

  Future<void> _mutate(void Function(Map<String, DownloadJob>) edit) {
    final write = _pendingWrite.then((_) async {
      final current = await (_loaded ??= _read());
      final updated = Map<String, DownloadJob>.from(current);
      edit(updated);
      final file = await _file;
      final staged = File(file.path + '.tmp');
      final previous = File(file.path + '.previous');
      await staged.writeAsString(jsonEncode({
        'version': 1,
        'jobs': [
          for (final entry in updated.entries)
            {
              'id': entry.key,
              'source': entry.value.source,
              'allowSizeOverride': entry.value.allowSizeOverride,
            },
        ],
      }), flush: true);
      var moved = false;
      try {
        if (await file.exists()) {
          if (await previous.exists()) await previous.delete();
          await file.rename(previous.path);
          moved = true;
        }
        await staged.rename(file.path);
      } catch (_) {
        if (moved && !await file.exists() && await previous.exists()) {
          await previous.rename(file.path);
        }
        rethrow;
      } finally {
        if (await staged.exists()) await staged.delete();
      }
      _loaded = Future.value(updated);
    });
    _pendingWrite = write.then<void>((_) {},
        onError: (Object _, StackTrace __) {});
    return write;
  }
}
