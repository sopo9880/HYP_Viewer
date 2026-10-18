import 'work.dart';
import 'online_search.dart';
import 'work_editions.dart';
import 'work_grouping.dart';

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
          WorkEditions.canonicalLanguage(old.sourceLanguage) !=
              WorkEditions.canonicalLanguage(incoming.sourceLanguage) &&
          WorkEditions.compare(old, incoming).autoLink).toList();
      if (found.isEmpty) continue;
      // Multiple competing chapter groups are ambiguous: never pick the
      // first arbitrary work and silently merge unrelated editions.
      if (found.map(WorkEditions.groupKey).toSet().length != 1) continue;
      final anchor = found.first;
      try {
        entries = _join(entries, anchor, incoming);
      } on StateError {
        // Incompatible existing series must never block adding a new work.
        continue;
      }
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
    final leftChapter = WorkGrouping.episodeNumber(anchor.first);
    final rightChapter = WorkGrouping.episodeNumber(edition.first);
    if (leftChapter != null && rightChapter != null &&
        leftChapter != rightChapter) {
      throw StateError('서로 다른 회차는 언어판으로 묶을 수 없어.');
    }
    if (anchor.first.sourceLanguage.trim().isNotEmpty &&
        edition.first.sourceLanguage.trim().isNotEmpty &&
        WorkEditions.canonicalLanguage(anchor.first.sourceLanguage) ==
            WorkEditions.canonicalLanguage(edition.first.sourceLanguage)) {
      throw StateError('같은 언어끼리는 언어판 묶음으로 만들 수 없어.');
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
    bool related(WorkEntry work) =>
        work.workId == anchor.workId ||
        work.workId == incoming.workId ||
        anchor.editionGroupId.isNotEmpty &&
          work.editionGroupId == anchor.editionGroupId ||
        oldId.isNotEmpty && work.editionGroupId == oldId;
    final linked = works.where(related).toList();
    final series = linked.where((work) => work.groupId.isNotEmpty)
        .map((work) => work.groupId).toSet();
    if (series.length > 1) {
      throw StateError('서로 다른 시리즈에 포함된 판본은 합칠 수 없어.');
    }
    final representative = linked.firstWhere(
        (work) => work.groupId.isNotEmpty, orElse: () => anchor);
    final selectedGroup = representative.groupId;
    final selectedTitle = representative.groupTitle;
    final selectedOrder = representative.groupOrder;
    return works.map((work) {
      final isAnchor = work.workId == anchor.workId ||
          anchor.editionGroupId.isNotEmpty &&
              work.editionGroupId == anchor.editionGroupId;
      final isIncoming = work.workId == incoming.workId ||
          oldId.isNotEmpty && work.editionGroupId == oldId;
      if (!isAnchor && !isIncoming) return work;
      return work.copyWith(
        editionGroupId: mergedId,
        groupId: selectedGroup,
        groupTitle: selectedTitle,
        groupOrder: selectedOrder,
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

  /// Flatten selected full series together with standalone works into exactly
  /// one series. This is a single library transaction and never changes work
  /// IDs, edition links, read progress, metadata, or offline file references.
  ///
  /// A caller cannot silently take a partial member from another series:
  /// a member already grouped must have its entire source series selected.
  static LibraryBackup mergeSelectedSeries(
    LibraryBackup original, {
    required Iterable<String> selectedGroupIds,
    required Iterable<String> selectedWorkIds,
    required String destinationGroupId,
    required String title,
  }) {
    final groupIds = selectedGroupIds.where((s) => s.isNotEmpty).toSet();
    final chosenIds = selectedWorkIds.toSet();
    final name = title.trim();
    if (destinationGroupId.isEmpty || destinationGroupId.length > 120 ||
        name.isEmpty || name.length > 200) {
      throw StateError('통합 묶음 ID와 이름이 올바르지 않아.');
    }
    final all = original.works;
    final allGroups = all.where((w) => w.groupId.isNotEmpty)
        .map((w) => w.groupId).toSet();
    if (!allGroups.containsAll(groupIds)) {
      throw StateError('선택한 기존 묶음을 찾을 수 없어.');
    }
    final existingIds = all.map((w) => w.workId).toSet();
    if (!existingIds.containsAll(chosenIds)) {
      throw StateError('선택한 작품이 서재에 없어.');
    }
    final selected = <String>{
      ...chosenIds,
      for (final work in all)
        if (groupIds.contains(work.groupId)) work.workId,
    };
    // All linked language editions of the same chapter travel together.
    final editionIds = all.where((w) => selected.contains(w.workId) &&
        w.editionGroupId.isNotEmpty).map((w) => w.editionGroupId).toSet();
    for (final work in all) {
      if (editionIds.contains(work.editionGroupId) &&
          work.editionGroupId.isNotEmpty) selected.add(work.workId);
    }
    for (final work in all.where((w) => selected.contains(w.workId))) {
      if (work.groupId.isNotEmpty && !groupIds.contains(work.groupId)) {
        throw StateError('선택하지 않은 묶음의 일부 작품을 이동할 수 없어.');
      }
    }
    final selectedWorks = all.where((w) => selected.contains(w.workId)).toList();
    final logicalCount = selectedWorks.map(WorkEditions.groupKey).toSet().length;
    if (logicalCount < 2) {
      throw StateError('서로 다른 회차 2개 이상이 필요해.');
    }
    // Keep existing chapter order inside each source group; selected groups
    // come first, standalone works after. Ties have stable work identifiers.
    final groupRanks = <String, int>{};
    var i = 0;
    for (final id in groupIds) { groupRanks[id] = i++; }
    selectedWorks.sort((a,b) {
      final ag = groupRanks[a.groupId] ?? groupRanks.length;
      final bg = groupRanks[b.groupId] ?? groupRanks.length;
      if (ag != bg) return ag.compareTo(bg);
      if (a.groupId.isNotEmpty && b.groupId == a.groupId) {
        final n = a.groupOrder.compareTo(b.groupOrder);
        if (n != 0) return n;
      }
      return WorkGrouping.compareChapters(a, b);
    });
    final positions = _chapterPositions(all,
        selectedWorks.map((w) => w.workId).toList());
    return LibraryBackup(
      works: all.map((w) => selected.contains(w.workId)
          ? w.copyWith(groupId: destinationGroupId,
              groupTitle: name, groupOrder: positions[w.workId] ?? 0)
          : w).toList(),
      collections: original.collections,
    );
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

  /// Remove whole logical chapters (all translations), never the work files.
  /// If the source has fewer than two chapters remaining, dissolve it.
  static LibraryBackup removeFromSeries(
      LibraryBackup original, String seriesId, List<String> selectedIds) {
    final members = original.works.where((w) => w.groupId == seriesId).toList();
    if (members.isEmpty || selectedIds.isEmpty) {
      throw StateError('시리즈 또는 제외할 작품이 없어.');
    }
    final byId = {for (final w in members) w.workId: w};
    if (selectedIds.any((id) => !byId.containsKey(id))) {
      throw StateError('해당 시리즈에 없는 회차는 제외할 수 없어.');
    }
    final selectedKeys = selectedIds.map((id) =>
        WorkEditions.groupKey(byId[id]!)).toSet();
    final remainingKeys = members.map(WorkEditions.groupKey)
        .toSet().difference(selectedKeys);
    final dissolve = remainingKeys.length < 2;
    return LibraryBackup(
      works: original.works.map((w) {
        if (w.groupId != seriesId) return w;
        if (dissolve || selectedKeys.contains(WorkEditions.groupKey(w))) {
          return w.copyWith(groupId: '', groupTitle: '', groupOrder: 0);
        }
        return w;
      }).toList(),
      collections: original.collections,
    );
  }

  /// A single in-memory transaction: remove a chapter from its old series
  /// and append all language editions to an existing destination series.
  static LibraryBackup moveBetweenSeries(
      LibraryBackup original, String sourceId, String targetId,
      List<String> selectedIds) {
    if (sourceId == targetId || targetId.isEmpty) {
      throw StateError('서로 다른 대상 묶음을 선택해줘.');
    }
    if (!original.works.any((w) => w.groupId == targetId)) {
      throw StateError('이동할 대상 묶음을 찾지 못했어.');
    }
    final removed = removeFromSeries(original, sourceId, selectedIds);
    return appendSeries(removed, targetId, selectedIds);
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


  /// Build all user-approved links in memory. The caller persists the
  /// returned backup only when every chapter/series guard succeeds.
  static LibraryBackup linkMany(
      LibraryBackup original,
      String anchorId,
      Iterable<String> localIds,
      Iterable<OnlineSearchWork> remoteWorks) {
    final targets = <String>{...localIds};
    final entries = original.works.toList();
    for (final remote in remoteWorks) {
      if (!RegExp(r'^\d{1,12}$').hasMatch(remote.workId)) {
        throw StateError('잘못된 언어판 작품 번호야.');
      }
      targets.add(remote.workId);
      final index = entries.indexWhere((w) => w.workId == remote.workId);
      if (index >= 0) {
        // Preserve the existing reading position, cover, tags and metadata.
        entries[index] = entries[index].withEvidence(
            aliases: [remote.title, ...remote.titleAliases]);
      } else {
        entries.add(WorkEntry.create(
          workId: remote.workId,
          title: remote.title,
          author: remote.artists.join(', '),
          titleAliases: remote.titleAliases,
        ).copyWith(
          sourceLanguage: remote.language,
          sourceSeries: remote.series.join(', '),
          sourceGroup: remote.groups.join(', '),
          tags: remote.tags,
          sourceType: remote.type,
          sourceDate: remote.date,
        ));
      }
    }
    if (targets.isEmpty || targets.contains(anchorId)) {
      throw StateError('서로 다른 언어판을 한 개 이상 선택해줘.');
    }
    var draft = LibraryBackup(
        works: entries, collections: original.collections);
    for (final id in targets) {
      draft = link(draft, anchorId, id);
    }
    return draft;
  }

  static LibraryBackup unlink(LibraryBackup original, String editionId) {
    return LibraryBackup(
      works: original.works.map((work) => work.workId == editionId
        ? work.copyWith(editionGroupId: '') : work).toList(),
      collections: original.collections);
  }
}
