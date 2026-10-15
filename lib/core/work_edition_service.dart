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
    if (anchor.first.groupId.isNotEmpty &&
        edition.first.groupId.isNotEmpty &&
        anchor.first.groupId != edition.first.groupId) {
      throw StateError('다른 시리즈에 있는 판본이야. 먼저 시리즈를 분리해줘.');
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

  /// All translations share one series chapter/order while maintaining their
  /// separate records and offline file identifiers.
  static Map<String, int> _chapterPositions(
      List<WorkEntry> works, List<String> orderedIds,
      {int offset = 0}) {
    final byId = {for (final work in works) work.workId: work};
    final positions = <String, int>{};
    final seen = <String>{};
    var position = offset;
    for (final id in orderedIds) {
      final work = byId[id];
      if (work == null) throw StateError('선택한 작품을 찾지 못했어.');
      final logical = WorkEditions.groupKey(work);
      if (!seen.add(logical)) continue;
      position++;
      for (final peer in works) {
        if (WorkEditions.groupKey(peer) == logical) {
          positions[peer.workId] = position;
        }
      }
    }
    return positions;
  }

  static LibraryBackup createSeries(
      LibraryBackup original, List<String> orderedIds,
      String seriesId, String title) {
    final positions = _chapterPositions(original.works, orderedIds);
    if (positions.values.toSet().length < 2) {
      throw StateError('서로 다른 회차 2개 이상이어야 시리즈를 만들 수 있어.');
    }
    final members = original.works.where((w) =>
        positions.containsKey(w.workId)).toList();
    if (members.any((w) => w.groupId.isNotEmpty)) {
      throw StateError('이미 시리즈에 속한 언어판이 있어.');
    }
    return LibraryBackup(
      works: original.works.map((w) {
        final position = positions[w.workId];
        return position == null ? w : w.copyWith(
          groupId: seriesId, groupTitle: title, groupOrder: position);
      }).toList(),
      collections: original.collections);
  }

  static LibraryBackup appendSeries(
      LibraryBackup original, String seriesId, List<String> orderedIds) {
    final previous = original.works.where((w) =>
        w.groupId == seriesId).toList();
    if (previous.isEmpty) throw StateError('기존 시리즈를 찾지 못했어.');
    final maxOrder = previous.fold<int>(0, (max, w) =>
        w.groupOrder > max ? w.groupOrder : max);
    final positions = _chapterPositions(
        original.works, orderedIds, offset: maxOrder);
    if (original.works.any((w) => positions.containsKey(w.workId) &&
        w.groupId.isNotEmpty && w.groupId != seriesId)) {
      throw StateError('다른 시리즈에 속한 언어판이 있어.');
    }
    return LibraryBackup(
      works: original.works.map((w) {
        final position = positions[w.workId];
        return position == null ? w : w.copyWith(
          groupId: seriesId, groupTitle: previous.first.groupTitle,
          groupOrder: position);
      }).toList(),
      collections: original.collections);
  }

  static LibraryBackup reorderSeries(
      LibraryBackup original, String seriesId, List<String> orderedIds) {
    final positions = _chapterPositions(
      original.works.where((w) => w.groupId == seriesId).toList(), orderedIds);
    return LibraryBackup(
      works: original.works.map((w) {
        final position = positions[w.workId];
        if (w.groupId != seriesId || position == null) return w;
        return w.copyWith(groupOrder: position);
      }).toList(),
      collections: original.collections);
  }

  static LibraryBackup unlink(LibraryBackup original, String editionId) {
    return LibraryBackup(
      works: original.works.map((work) => work.workId == editionId
        ? work.copyWith(editionGroupId: '') : work).toList(),
      collections: original.collections);
  }
}
