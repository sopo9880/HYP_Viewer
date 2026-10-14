import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import 'gallery.dart';
import 'work.dart';

class CbzExportSummary {
  final int saved;
  final int failed;
  final bool cancelled;
  const CbzExportSummary(this.saved, this.failed, {this.cancelled = false});
}

/// Exports only existing offline CBZ files. Never downloads a work, never
/// removes the original, and never overwrites an existing Windows file.
class SelectedCbzExporter {
  static const MethodChannel _android =
      MethodChannel('hyp_viewer/export_cbz');

  static String safeName(WorkEntry work) {
    final name = work.title.replaceAll(
      RegExp(r'[^a-zA-Z0-9가-힣ㄱ-ㅎぁ-んァ-ン一-龯 _-]'), '_')
        .trim();
    final shortened = name.length > 60 ? name.substring(0, 60) : name;
    return work.workId + (shortened.isEmpty ? '' : '_' + shortened) + '.cbz';
  }

  static Future<CbzExportSummary> export(
      GalleryStore store, List<WorkEntry> selected) async {
    final items = <Map<String, String>>[];
    for (final work in selected.take(500)) {
      if (!await store.exists(work.workId)) continue;
      final source = await store.existingCbzFile(work.workId);
      items.add({
        'path': source.path,
        // Android output names intentionally use ASCII IDs only to prevent
        // locale-specific DocumentsProvider filename restrictions.
        'name': work.workId + '.cbz',
      });
    }
    if (items.isEmpty) return const CbzExportSummary(0, 0);
    if (!kIsWeb && Platform.isAndroid) {
      final response = await _android.invokeMapMethod<String, dynamic>(
        'exportToFolder', {'files': items});
      if (response == null) return const CbzExportSummary(0, 0, cancelled: true);
      return CbzExportSummary((response['saved'] as num?)?.toInt() ?? 0,
          (response['failed'] as num?)?.toInt() ?? 0,
          cancelled: response.isEmpty);
    }
    final directory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '다운로드한 CBZ를 내보낼 폴더 선택');
    if (directory == null) return const CbzExportSummary(0, 0, cancelled: true);
    var saved = 0, failed = 0;
    for (final work in selected) {
      if (!await store.exists(work.workId)) continue;
      try {
        final src = await store.existingCbzFile(work.workId);
        final baseName = safeName(work);
        var destination = File(directory + Platform.pathSeparator + baseName);
        var suffix = 1;
        while (await destination.exists()) {
          destination = File(directory + Platform.pathSeparator +
            baseName.substring(0, baseName.length - 4) +
            '_' + (suffix++).toString() + '.cbz');
        }
        await src.copy(destination.path);
        saved++;
      } catch (_) {
        failed++;
      }
    }
    return CbzExportSummary(saved, failed);
  }
}
