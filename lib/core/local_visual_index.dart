import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'cover_store.dart';
import 'gallery.dart';
import 'visual_signature.dart';
import 'work.dart';

/// Local-only, opt-in fingerprints of existing covers and a few offline pages.
class LocalVisualRecord {
  final String workId, title, author, origin;
  final VisualSignature signature;
  const LocalVisualRecord({required this.workId, required this.title,
    required this.author, required this.origin, required this.signature});

  Map<String, Object> toJson() => {
    'workId': workId, 'title': title, 'author': author,
    'origin': origin, 'signature': signature.toJson(),
  };

  static LocalVisualRecord? fromJson(dynamic data) {
    if (data is! Map || data['workId'] is! String ||
        !RegExp(r'^\d{1,12}$').hasMatch(data['workId'] as String) ||
        data['title'] is! String || data['author'] is! String ||
        data['origin'] is! String) return null;
    final sig = VisualSignature.fromJson(data['signature']);
    if (sig == null) return null;
    return LocalVisualRecord(workId: data['workId'] as String,
      title: data['title'] as String, author: data['author'] as String,
      origin: data['origin'] as String, signature: sig);
  }
}

class LocalVisualMatch {
  final String workId, title, author, evidence;
  final double similarity;
  const LocalVisualMatch({required this.workId, required this.title,
    required this.author, required this.evidence,
    required this.similarity});
}

class LocalVisualIndex {
  final Directory? baseDirectory;
  const LocalVisualIndex({this.baseDirectory});

  Future<File> get _file async {
    final dir = baseDirectory ?? await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File(dir.path + Platform.pathSeparator + 'hyp_visual_index.json');
  }

  Future<List<LocalVisualRecord>> load() async {
    final file = await _file;
    if (!await file.exists()) return [];
    if (await file.length() > 2 * 1024 * 1024) {
      throw const FormatException('로컬 이미지 인덱스 크기 제한을 넘었어.');
    }
    final data = jsonDecode(await file.readAsString());
    if (data is! Map || data['version'] != 1 || data['entries'] is! List) {
      throw const FormatException('이미지 인덱스 형식이 유효하지 않아.');
    }
    return (data['entries'] as List).take(2500)
        .map(LocalVisualRecord.fromJson)
        .whereType<LocalVisualRecord>().toList();
  }

  /// Scanning is explicitly initiated by the user. Original images are never
  /// embedded in the index, uploaded, modified or deleted.
  Future<int> rebuild(Iterable<WorkEntry> works, {
    required CoverStore covers,
    required GalleryStore galleries,
    void Function(int completed, int total)? onProgress,
  }) async {
    final entries = <LocalVisualRecord>[];
    final selected = works.take(500).toList();
    for (var i = 0; i < selected.length; i++) {
      final work = selected[i];
      Future<void> add(Uint8List? image, String origin) async {
        if (image == null || image.length > 16 * 1024 * 1024) return;
        final sig = await VisualSignature.fromImage(image);
        if (sig == null) return;
        entries.add(LocalVisualRecord(workId: work.workId,
          title: work.title, author: work.author,
          origin: origin, signature: sig));
      }
      try {
        if (work.coverMode != 'preset') {
          await add(await covers.read(work.workId, mode: work.coverMode,
            page: work.coverMode == 'page' ? work.coverPage : 1), '표지');
        }
        if (await galleries.exists(work.workId)) {
          final archive = await galleries.read(work.workId);
          if (archive.pageCount > 0) {
            final pages = <int>{0, archive.pageCount ~/ 2,
                archive.pageCount - 1};
            for (final page in pages) {
              await add(archive.pageBytes(page),
                  '오프라인 ' + (page + 1).toString() + '페이지');
            }
          }
        }
      } catch (_) {
        // Damaged/offline files are not changed by indexing.
      }
      onProgress?.call(i + 1, selected.length);
    }
    final file = await _file;
    final next = File(file.path + '.tmp');
    await next.writeAsString(jsonEncode({
      'version': 1,
      'entries': entries.map((entry) => entry.toJson()).toList(),
    }), flush: true);
    if (await file.exists()) await file.delete();
    await next.rename(file.path);
    return entries.length;
  }

  Future<List<LocalVisualMatch>> search(List<Uint8List> images, {
    double threshold = 0.62, int limit = 12,
  }) async {
    final known = await load();
    final queries = <VisualSignature>[];
    for (final image in images.take(12)) {
      final sig = await VisualSignature.fromImage(image);
      if (sig != null) queries.add(sig);
    }
    if (known.isEmpty || queries.isEmpty) return [];
    final best = <String, LocalVisualMatch>{};
    for (final record in known) {
      var score = 0.0;
      for (final q in queries) {
        final similarity = q.similarity(record.signature);
        if (similarity > score) score = similarity;
      }
      if (score < threshold) continue;
      if (best[record.workId] == null ||
          best[record.workId]!.similarity < score) {
        best[record.workId] = LocalVisualMatch(workId: record.workId,
          title: record.title, author: record.author,
          evidence: record.origin, similarity: score);
      }
    }
    return (best.values.toList()
      ..sort((a, b) => b.similarity.compareTo(a.similarity)))
        .take(limit.clamp(1, 30)).toList();
  }
}
