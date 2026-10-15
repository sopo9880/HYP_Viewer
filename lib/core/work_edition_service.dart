import 'work.dart';
import 'work_editions.dart';

/// Keep each edition's own workId, currentPage, cover and offline files.
/// Only visual relationships are changed; schemaVersion 1 backups remain readable.
abstract final class WorkEditionService {
  static LibraryBackup autoLink(LibraryBackup original, Iterable<String> newIds) {
    var entries = original.works.toList();
    for (final id in newIds.toSet()) {
      final index = entries.indexWhere((work) => work.workId == id);
      if (index < 0) continue;
      final incoming = entries[index];
      if (incoming.editionGroupId.isNotEmpty ||
          incoming.sourceLanguage.isEmpty) continue;
      final found = entries.where((old) =>
          old.workId != id && old.sourceLanguage.isNotEmpty &&
          old.sourceLanguage.toLowerCase() !=
              incoming.sourceLanguage.toLowerCase() &&
          WorkEditions.compare(old, incoming).autoLink).toList();
      if (found.isEmpty) continue;
      final anchor = found.first;
      entries = _join(entries, anchor, incoming);
    }
    return LibraryBackup(works: entries, collections: original.collections);
  }

  static LibraryBackup link(LibraryBackup original,
      String anchorId, String editionId) {
    final entries = original.works;
    final anchor = entries.where((w) => w.workId == anchorId).toList();
    final edition = entries.where((w) => w.workId == editionId).toList();
    if (anchor.isEmpty || edition.isEmpty || anchorId == editionId) {
      throw StateError('서재에 존재하는 서로 다른 작품 두 개를 선택해줘.');
    }
    return LibraryBackup(
      works: _join(entries, anchor.first, edition.first),
      collections: original.collections);
  }

  static List<WorkEntry> _join(List<WorkEntry> works,
      WorkEntry anchor, WorkEntry incoming) {
    final mergedId = anchor.editionGroupId.isNotEmpty
        ? anchor.editionGroupId : 'edition_' + anchor.workId;
    final oldId = incoming.editionGroupId;
    return works.map((work) {
      final isAnchor = work.workId == anchor.workId ||
          anchor.editionGroupId.isNotEmpty &&
              work.editionGroupId == anchor.editionGroupId;
      final isIncoming = work.workId == incoming.workId ||
          oldId.isNotEmpty && work.editionGroupId == oldId;
      if (!isAnchor && !isIncoming) return work;
      return work.copyWith(
        editionGroupId: mergedId,
        groupId: anchor.groupId,
        groupTitle: anchor.groupTitle,
        groupOrder: anchor.groupOrder,
      );
    }).toList();
  }

  static LibraryBackup unlink(LibraryBackup original, String editionId) {
    return LibraryBackup(
      works: original.works.map((work) => work.workId == editionId
        ? work.copyWith(editionGroupId: '') : work).toList(),
      collections: original.collections);
  }
}
