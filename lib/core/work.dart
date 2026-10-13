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
    );
  }

  String get key => videoId.isNotEmpty ? 'video:$videoId' : 'work:$workId';

  WorkEntry copyWith({
    String? workId,
    String? title,
    String? author,
    String? originalComment,
    bool? favorite,
    bool? completed,
    int? currentPage,
    List<String>? collections,
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
    );
  }
}

class LibraryBackup {
  static const int currentSchemaVersion = 1;
  final List<WorkEntry> works;
  final List<String> collections;
  const LibraryBackup({required this.works, required this.collections});

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
        updatedAt: recent.updatedAt,
      );
    }
    return LibraryBackup(
      works: merged.values.toList(),
      collections: {...local.collections, ...imported.collections}.toList(),
    );
  }
}
