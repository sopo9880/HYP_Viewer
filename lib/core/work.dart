import 'dart:convert';

class WorkEntry {
  final String videoId;
  final String videoUrl;
  final String workId;
  final String title;
  final String author;
  final String originalComment;
  final bool favorite;
  final bool completed;
  final int currentPage;
  final List<String> collections;
  final String updatedAt;
  // Optional: absent in older schemaVersion 1 JSON backups.
  final String? lastOpenedAt;
  /// The original add date is independent from updatedAt/read progress.
  final String addedAt;
  final int openCount;
  final int totalPages;
  final List<String> tags;
  final String sourceLanguage;
  final String sourceType;
  final String sourceSeries;
  final String sourceGroup;
  final String sourceDate;
  /// User-controlled series group. Empty ID means ungrouped.
  final String groupId;
  final String groupTitle;
  final int groupOrder;
  /// Translated editions of the SAME chapter. groupId remains the series.
  final String editionGroupId;
  /// 'auto', 'preset', 'page' or 'custom' (cropped/uploaded image).
  final String coverMode;
  final int coverPreset;
  final int coverPage;

  const WorkEntry({
    required this.videoId,
    required this.videoUrl,
    required this.workId,
    required this.title,
    required this.author,
    required this.originalComment,
    required this.favorite,
    required this.completed,
    required this.currentPage,
    required this.collections,
    required this.updatedAt,
    this.lastOpenedAt,
    this.addedAt = '',
    this.openCount = 0,
    this.totalPages = 0,
    this.tags = const [],
    this.sourceLanguage = '',
    this.sourceType = '',
    this.sourceSeries = '',
    this.sourceGroup = '',
    this.sourceDate = '',
    this.groupId = '',
    this.groupTitle = '',
    this.groupOrder = 0,
    this.editionGroupId = '',
    this.coverMode = 'auto',
    this.coverPreset = 0,
    this.coverPage = 1,
  });

  factory WorkEntry.create({
    required String workId,
    String videoId = '',
    String videoUrl = '',
    String title = '',
    String author = '',
    String originalComment = '',
  }) {
    return WorkEntry(
      videoId: videoId.trim(),
      videoUrl: videoUrl.trim(),
      workId: workId.trim(),
      title: title.trim(),
      author: author.trim(),
      originalComment: originalComment,
      favorite: false,
      completed: false,
      currentPage: 1,
      collections: const [],
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      addedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  // Each work has its own shelf entry even when several share one Shorts URL.
  // Covers, downloads and progress are also indexed by the work identifier.
  String get key => 'work:$workId';

  WorkEntry copyWith({
    String? workId,
    String? title,
    String? author,
    String? originalComment,
    bool? favorite,
    bool? completed,
    int? currentPage,
    List<String>? collections,
    String? lastOpenedAt,
    String? addedAt,
    int? openCount,
    int? totalPages,
    List<String>? tags,
    String? sourceLanguage,
    String? sourceType,
    String? sourceSeries,
    String? sourceGroup,
    String? sourceDate,
    String? groupId,
    String? groupTitle,
    int? groupOrder,
    String? editionGroupId,
    String? coverMode,
    int? coverPreset,
    int? coverPage,
  }) {
    return WorkEntry(
      videoId: videoId,
      videoUrl: videoUrl,
      workId: workId ?? this.workId,
      title: title ?? this.title,
      author: author ?? this.author,
      originalComment: originalComment ?? this.originalComment,
      favorite: favorite ?? this.favorite,
      completed: completed ?? this.completed,
      currentPage: currentPage ?? this.currentPage,
      collections: collections ?? this.collections,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      addedAt: addedAt ?? this.addedAt,
      openCount: openCount ?? this.openCount,
      totalPages: totalPages ?? this.totalPages,
      tags: tags ?? this.tags,
      sourceLanguage: sourceLanguage ?? this.sourceLanguage,
      sourceType: sourceType ?? this.sourceType,
      sourceSeries: sourceSeries ?? this.sourceSeries,
      sourceGroup: sourceGroup ?? this.sourceGroup,
      sourceDate: sourceDate ?? this.sourceDate,
      groupId: groupId ?? this.groupId,
      groupTitle: groupTitle ?? this.groupTitle,
      groupOrder: groupOrder ?? this.groupOrder,
      editionGroupId: editionGroupId ?? this.editionGroupId,
      coverMode: coverMode ?? this.coverMode,
      coverPreset: coverPreset ?? this.coverPreset,
      coverPage: coverPage ?? this.coverPage,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  Map<String, Object?> toJson() => {
    'videoId': videoId,
    'videoUrl': videoUrl,
    'workId': workId,
    'title': title,
    'author': author,
    'originalComment': originalComment,
    'favorite': favorite,
    'completed': completed,
    'currentPage': currentPage,
    'collections': collections,
    'updatedAt': updatedAt,
    if (lastOpenedAt != null) 'lastOpenedAt': lastOpenedAt,
    if (addedAt.isNotEmpty) 'addedAt': addedAt,
    if (openCount > 0) 'openCount': openCount,
    if (totalPages > 0) 'totalPages': totalPages,
    if (tags.isNotEmpty) 'tags': tags,
    if (sourceLanguage.isNotEmpty) 'sourceLanguage': sourceLanguage,
    if (sourceType.isNotEmpty) 'sourceType': sourceType,
    if (sourceSeries.isNotEmpty) 'sourceSeries': sourceSeries,
    if (sourceGroup.isNotEmpty) 'sourceGroup': sourceGroup,
    if (sourceDate.isNotEmpty) 'sourceDate': sourceDate,
    if (groupId.isNotEmpty) 'groupId': groupId,
    if (groupTitle.isNotEmpty) 'groupTitle': groupTitle,
    if (groupOrder > 0) 'groupOrder': groupOrder,
    if (editionGroupId.isNotEmpty) 'editionGroupId': editionGroupId,
    if (coverMode != 'auto') 'coverMode': coverMode,
    if (coverPreset != 0) 'coverPreset': coverPreset,
    if (coverPage != 1) 'coverPage': coverPage,
  };

  factory WorkEntry.fromJson(Map<String, dynamic> data) {
    String text(String key) => data[key] is String ? data[key] as String : '';
    final code = text('workId').trim();
    if (!RegExp(r'^\d{1,12}$').hasMatch(code)) {
      throw const FormatException('Invalid workId in backup');
    }
    final rawCollections = data['collections'];
    return WorkEntry(
      videoId: text('videoId'),
      videoUrl: text('videoUrl'),
      workId: code,
      title: text('title'),
      author: text('author'),
      originalComment: text('originalComment'),
      favorite: data['favorite'] == true,
      completed: data['completed'] == true,
      currentPage: (data['currentPage'] is num)
          ? (data['currentPage'] as num).toInt().clamp(1, 1000000).toInt()
          : 1,
      collections: rawCollections is List
          ? rawCollections.whereType<String>().take(100).toSet().toList()
          : <String>[],
      updatedAt: DateTime.tryParse(text('updatedAt'))?.toUtc().toIso8601String() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toIso8601String(),
      lastOpenedAt: DateTime.tryParse(text('lastOpenedAt'))
          ?.toUtc().toIso8601String(),
      addedAt: DateTime.tryParse(text('addedAt'))
          ?.toUtc().toIso8601String() ??
          (DateTime.tryParse(text('updatedAt'))?.toUtc().toIso8601String() ?? ''),
      openCount: data['openCount'] is num
          ? (data['openCount'] as num).toInt().clamp(0, 100000000).toInt() : 0,
      totalPages: data['totalPages'] is num
          ? (data['totalPages'] as num).toInt().clamp(0, 1000000).toInt() : 0,
      tags: data['tags'] is List
          ? (data['tags'] as List).whereType<String>().take(150).toSet().toList()
          : const [],
      sourceLanguage: text('sourceLanguage'),
      sourceType: text('sourceType'),
      sourceSeries: text('sourceSeries'),
      sourceGroup: text('sourceGroup'),
      sourceDate: text('sourceDate'),
      groupId: text('groupId').length <= 120 ? text('groupId') : '',
      groupTitle: text('groupTitle').length <= 200 ? text('groupTitle') : '',
      editionGroupId: text('editionGroupId').length <= 120 ? text('editionGroupId') : '',
      groupOrder: data['groupOrder'] is num
          ? (data['groupOrder'] as num).toInt().clamp(0, 10000).toInt() : 0,
      coverMode: const {'auto', 'preset', 'page', 'custom'}.contains(text('coverMode'))
          ? text('coverMode') : 'auto',
      coverPreset: data['coverPreset'] is num
          ? (data['coverPreset'] as num).toInt().clamp(0, 5).toInt()
          : 0,
      coverPage: data['coverPage'] is num
          ? (data['coverPage'] as num).toInt().clamp(1, 1000000).toInt()
          : 1,
    );
  }
}

class LibraryBackup {
  static const int currentSchemaVersion = 1;
  final List<WorkEntry> works;
  final List<String> collections;
  const LibraryBackup({required this.works, required this.collections});

  /// Remove only the requested work from the saved library. Other entries,
  /// their reading progress, favorites and collection definitions stay intact.
  LibraryBackup withoutWork(String workId) => withoutWorks({workId});

  /// Delete many shelf entries in one transaction; other works are untouched.
  LibraryBackup withoutWorks(Set<String> workIds) => LibraryBackup(
    works: works.where((work) => !workIds.contains(work.workId)).toList(),
    collections: collections,
  );

  /// Never silently overwrite an existing destination work ID.
  /// A duplicate destination is merged only after explicit user approval.
  LibraryBackup editWork({
    required String originalWorkId,
    required WorkEntry edited,
    bool mergeDuplicate = false,
  }) {
    if (!RegExp(r'^\d{1,12}$').hasMatch(edited.workId)) {
      throw const FormatException('작품 번호는 숫자 1~12자리여야 해.');
    }
    if (!works.any((w) => w.workId == originalWorkId)) {
      throw StateError('수정할 작품을 현재 서재에서 찾지 못했어.');
    }
    final duplicate = edited.workId != originalWorkId &&
        works.any((w) => w.workId == edited.workId);
    if (duplicate && !mergeDuplicate) {
      throw StateError('새 작품 번호가 이미 서재에 있어. 병합 확인이 필요해.');
    }
    if (!duplicate) {
      return LibraryBackup(
        works: works.map((w) =>
            w.workId == originalWorkId ? edited : w).toList(),
        collections: collections,
      );
    }
    final target = works.firstWhere((w) => w.workId == edited.workId);
    // When merging into an existing ID, retain its local cover preferences.
    // An older ID's CBZ and cover files must not be attached to a new work.
    final corrected = edited.copyWith(
      coverMode: target.coverMode,
      coverPreset: target.coverPreset,
      coverPage: target.coverPage,
    );
    return LibraryBackup.merge(
      withoutWork(originalWorkId),
      LibraryBackup(works: [corrected], collections: const []),
    );
  }

  Map<String, Object?> toJson() => {
    'app': 'HYP Viewer',
    'schemaVersion': currentSchemaVersion,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'works': works.map((e) => e.toJson()).toList(),
    'collections': collections,
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  static LibraryBackup decode(String text) {
    if (utf8.encode(text).length > 10 * 1024 * 1024) {
      throw const FormatException('Backup exceeds 10 MB');
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic> ||
        decoded['app'] != 'HYP Viewer' ||
        decoded['schemaVersion'] != currentSchemaVersion ||
        decoded['works'] is! List) {
      throw const FormatException('Unsupported or invalid HYP library JSON');
    }
    final raw = decoded['works'] as List;
    if (raw.length > 10000) {
      throw const FormatException('Too many works in backup');
    }
    final works = raw.map((e) {
      if (e is! Map<String, dynamic>) {
        throw const FormatException('Invalid work item');
      }
      return WorkEntry.fromJson(e);
    }).toList();
    final rawCollections = decoded['collections'];
    return LibraryBackup(
      works: works,
      collections: rawCollections is List
          ? rawCollections.whereType<String>().take(500).toSet().toList()
          : const [],
    );
  }

  /// Merge preserves user reading progress and favorites in both backups.
  /// For conflicting work IDs the most recent edit takes precedence.
  static LibraryBackup merge(LibraryBackup local, LibraryBackup imported) {
    final merged = <String, WorkEntry>{for (final w in local.works) w.key: w};
    for (final incoming in imported.works) {
      final existing = merged[incoming.key];
      if (existing == null) {
        merged[incoming.key] = incoming;
        continue;
      }
      final useIncoming = incoming.updatedAt.compareTo(existing.updatedAt) >= 0;
      final recent = useIncoming ? incoming : existing;
      merged[incoming.key] = WorkEntry(
        videoId: recent.videoId,
        videoUrl: recent.videoUrl.isNotEmpty
            ? recent.videoUrl
            : (useIncoming ? existing.videoUrl : incoming.videoUrl),
        workId: recent.workId,
        title: recent.title.isNotEmpty
            ? recent.title
            : (useIncoming ? existing.title : incoming.title),
        author: recent.author.isNotEmpty
            ? recent.author
            : (useIncoming ? existing.author : incoming.author),
        originalComment: recent.originalComment.isNotEmpty
            ? recent.originalComment
            : (useIncoming ? existing.originalComment : incoming.originalComment),
        favorite: existing.favorite || incoming.favorite,
        completed: existing.completed || incoming.completed,
        currentPage: existing.currentPage > incoming.currentPage
            ? existing.currentPage
            : incoming.currentPage,
        collections: {...existing.collections, ...incoming.collections}.toList(),
        coverMode: recent.coverMode,
        coverPreset: recent.coverPreset,
        coverPage: recent.coverPage,
        updatedAt: recent.updatedAt,
        lastOpenedAt: (existing.lastOpenedAt ?? '').compareTo(
            incoming.lastOpenedAt ?? '') >= 0
            ? existing.lastOpenedAt : incoming.lastOpenedAt,
        addedAt: [existing.addedAt, incoming.addedAt]
            .where((v) => v.isNotEmpty).fold<String>('', (best, next) =>
                best.isEmpty || next.compareTo(best) < 0 ? next : best),
        openCount: existing.openCount > incoming.openCount
            ? existing.openCount : incoming.openCount,
        totalPages: recent.totalPages > 0 ? recent.totalPages :
            (existing.totalPages > incoming.totalPages
                ? existing.totalPages : incoming.totalPages),
        tags: recent.tags.isNotEmpty ? recent.tags :
            (existing.tags.isNotEmpty ? existing.tags : incoming.tags),
        sourceLanguage: recent.sourceLanguage.isNotEmpty
            ? recent.sourceLanguage : (useIncoming
                ? existing.sourceLanguage : incoming.sourceLanguage),
        sourceType: recent.sourceType.isNotEmpty
            ? recent.sourceType : (useIncoming
                ? existing.sourceType : incoming.sourceType),
        sourceSeries: recent.sourceSeries.isNotEmpty
            ? recent.sourceSeries : (useIncoming
                ? existing.sourceSeries : incoming.sourceSeries),
        sourceGroup: recent.sourceGroup.isNotEmpty
            ? recent.sourceGroup : (useIncoming
                ? existing.sourceGroup : incoming.sourceGroup),
        sourceDate: recent.sourceDate.isNotEmpty
            ? recent.sourceDate : (useIncoming
                ? existing.sourceDate : incoming.sourceDate),
        // Imported group IDs must not silently replace an existing local
        // grouping; user-created groups stay stable across JSON merging.
        groupId: existing.groupId.isNotEmpty
            ? existing.groupId : incoming.groupId,
        groupTitle: existing.groupId.isNotEmpty
            ? existing.groupTitle : incoming.groupTitle,
        groupOrder: existing.groupId.isNotEmpty
            ? existing.groupOrder : incoming.groupOrder,
        editionGroupId: existing.editionGroupId.isNotEmpty
            ? existing.editionGroupId : incoming.editionGroupId,
      );
    }
    return LibraryBackup(
      works: merged.values.toList(),
      collections: {...local.collections, ...imported.collections}.toList(),
    );
  }
}
