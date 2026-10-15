import 'dart:convert';
import 'dart:typed_data';

import 'hero_artwork_store.dart';
import 'reader_settings.dart';
import 'work.dart';
import 'reading_history.dart';

/// Schema 2 applies to portable exports only. App-local library storage
/// retains schema 1, preserving older installations and recovery snapshots.
class AppBackup {
  static const schemaVersion = 2;
  static const maxJsonBytes = 40 * 1024 * 1024;
  static const maxAssetBytes = 22 * 1024 * 1024;
  static const maxCovers = 500;

  final LibraryBackup library;
  final ReaderSettings? settings;
  final bool includesLibrary;
  final Uint8List? bannerImage;
  final List<BackupCover> covers;
  final List<ReadingSession> readingSessions;
  final bool includesReadingHistory;

  const AppBackup({
    required this.library,
    this.settings,
    this.includesLibrary = true,
    this.bannerImage,
    this.covers = const [],
    this.readingSessions = const [],
    this.includesReadingHistory = false,
  });

  bool get hasSettings => settings != null;
  bool get hasImages => bannerImage != null || covers.isNotEmpty;

  Map<String, Object?> toJson() {
    if (!includesLibrary && settings == null) {
      throw const FormatException('백업할 서재 또는 설정을 선택해야 해.');
    }
    return <String, Object?>{
      ...library.toJson(),
      'schemaVersion': schemaVersion,
      'includesLibrary': includesLibrary,
      'works': includesLibrary ? library.works.map((w) => w.toJson()).toList()
          : <Object>[],
      'collections': includesLibrary ? library.collections : <String>[],
      if (settings != null) 'settings': settings!.toJson(),
      if (includesLibrary && includesReadingHistory)
        'readingSessions': readingSessions.map((session) => session.toJson()).toList(),
      if (hasImages) 'images': {
        if (bannerImage != null) 'banner': base64Encode(bannerImage!),
        if (covers.isNotEmpty) 'covers': [
          for (final cover in covers) {
            'workId': cover.workId,
            'mode': cover.mode,
            'page': cover.page,
            'data': base64Encode(cover.bytes),
          }
        ],
      },
    };
  }

  Uint8List encode() {
    if (readingSessions.length > ReadingHistoryStore.maxSessions) {
      throw const FormatException('백업 열람 기록이 너무 많아.');
    }
    _validateImages(bannerImage, covers, library);
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(toJson())));
    if (bytes.length > maxJsonBytes) {
      throw const FormatException('JSON 백업은 최대 40MB까지 지원해.');
    }
    return bytes;
  }

  static AppBackup decode(String content) {
    if (utf8.encode(content).length > maxJsonBytes) {
      throw const FormatException('JSON 백업은 최대 40MB까지 지원해.');
    }
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic> ||
        decoded['app'] != 'HYP Viewer') {
      throw const FormatException('HYP Viewer 백업 JSON이 아니야.');
    }
    final version = decoded['schemaVersion'];
    if (version == 1) {
      // Old JSON has library metadata only. It cannot overwrite settings
      // and must never trigger an empty full restore without confirmation.
      return AppBackup(library: LibraryBackup.decode(content));
    }
    if (version != schemaVersion) {
      throw const FormatException('지원하지 않는 JSON 백업 버전이야.');
    }
    if (decoded['includesLibrary'] is! bool ||
        decoded['works'] is! List ||
        decoded['collections'] is! List) {
      throw const FormatException('서재 백업 필드가 유효하지 않아.');
    }
    final includeLibrary = decoded['includesLibrary'] as bool;
    final library = LibraryBackup.decode(jsonEncode({
      'app': 'HYP Viewer', 'schemaVersion': 1,
      'works': decoded['works'], 'collections': decoded['collections'],
    }));

    ReaderSettings? settings;
    if (decoded.containsKey('settings')) {
      final raw = decoded['settings'];
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('백업의 앱 설정이 유효하지 않아.');
      }
      settings = ReaderSettings.fromJson(raw);
    }
    if (!includeLibrary && settings == null) {
      throw const FormatException('비어 있는 백업을 가져올 수 없어.');
    }

    final images = decoded['images'];
    Uint8List? banner;
    final covers = <BackupCover>[];
    if (images != null) {
      if (images is! Map<String, dynamic>) {
        throw const FormatException('이미지 백업 구조가 유효하지 않아.');
      }
      if (images['banner'] != null) {
        if (images['banner'] is! String) {
          throw const FormatException('배너 이미지 데이터가 유효하지 않아.');
        }
        banner = _decodeImage(images['banner'] as String);
      }
      final rawCovers = images['covers'];
      if (rawCovers != null) {
        if (rawCovers is! List || rawCovers.length > maxCovers) {
          throw const FormatException('백업 표지 개수가 허용 범위를 넘었어.');
        }
        for (final entry in rawCovers) {
          if (entry is! Map<String, dynamic> ||
              entry['workId'] is! String ||
              entry['mode'] is! String ||
              entry['page'] is! int ||
              entry['data'] is! String) {
            throw const FormatException('백업 표지 정보가 유효하지 않아.');
          }
          covers.add(BackupCover(
            workId: entry['workId'] as String,
            mode: entry['mode'] as String,
            page: entry['page'] as int,
            bytes: _decodeImage(entry['data'] as String),
          ));
        }
      }
    }
    _validateImages(banner, covers, library);
    final rawSessions = decoded['readingSessions'];
    if (rawSessions != null && (rawSessions is! List ||
        rawSessions.length > ReadingHistoryStore.maxSessions)) {
      throw const FormatException('백업의 독서 기록이 유효하지 않아.');
    }
    final sessions = <ReadingSession>[];
    if (rawSessions is List && includeLibrary) {
      for (final item in rawSessions) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('백업 열람 기록 항목이 손상됐어.');
        }
        sessions.add(ReadingSession.fromJson(item));
      }
    }
    return AppBackup(
      library: library,
      settings: settings,
      includesLibrary: includeLibrary,
      bannerImage: banner,
      covers: covers,
      readingSessions: sessions,
      includesReadingHistory: rawSessions != null && includeLibrary,
    );
  }

  static Uint8List _decodeImage(String data) {
    if (data.length > (maxAssetBytes * 4 ~/ 3) + 16) {
      throw const FormatException('이미지 백업 용량 제한 초과');
    }
    try {
      return base64Decode(data);
    } on FormatException {
      throw const FormatException('백업 이미지가 Base64 형식이 아니야.');
    }
  }

  static void _validateImages(
      Uint8List? banner, List<BackupCover> covers, LibraryBackup library) {
    if (banner != null && !HeroArtworkStore.isSupportedImage(banner)) {
      throw const FormatException('배너 이미지는 PNG/JPG/WebP만 지원해.');
    }
    if (covers.length > maxCovers) {
      throw const FormatException('표지 이미지가 너무 많아.');
    }
    var total = banner?.length ?? 0;
    final seen = <String>{};
    final validWorks = library.works.map((w) => w.workId).toSet();
    for (final cover in covers) {
      if (!validWorks.contains(cover.workId) ||
          !RegExp(r'^\d{1,12}$').hasMatch(cover.workId) ||
          !const {'auto', 'custom', 'page'}.contains(cover.mode) ||
          cover.page < 1 || cover.page > 1000000 ||
          cover.bytes.isEmpty || cover.bytes.length > 3 * 1024 * 1024) {
        throw const FormatException('백업 표지의 작품 번호·이미지 정보가 유효하지 않아.');
      }
      if (cover.bytes.length < 8 ||
          !const [137, 80, 78, 71, 13, 10, 26, 10]
              .asMap().entries.every((e) => cover.bytes[e.key] == e.value)) {
        throw const FormatException('백업 표지 이미지는 PNG 형식이어야 해.');
      }
      final key = cover.workId + '|' + cover.mode + '|' + cover.page.toString();
      if (!seen.add(key)) throw const FormatException('중복된 표지 이미지야.');
      total += cover.bytes.length;
      if (total > maxAssetBytes) {
        throw const FormatException('백업 이미지 합계는 최대 22MB야.');
      }
    }
  }
}

class BackupCover {
  final String workId;
  final String mode;
  final int page;
  final Uint8List bytes;

  const BackupCover({
    required this.workId,
    required this.mode,
    required this.page,
    required this.bytes,
  });
}

/// Replace Everything always requires both a library AND settings payload.
enum AppRestoreMode { addWorks, replaceSettings, replaceEverything }

class AppRestorePlan {
  final LibraryBackup library;
  final ReaderSettings? settings;
  final bool changesLibrary;

  const AppRestorePlan({
    required this.library,
    required this.settings,
    required this.changesLibrary,
  });

  static AppRestorePlan build(
    LibraryBackup currentLibrary,
    ReaderSettings currentSettings,
    AppBackup imported,
    AppRestoreMode mode,
  ) {
    switch (mode) {
      case AppRestoreMode.addWorks:
        if (!imported.includesLibrary) {
          throw const FormatException('백업에 작품 목록이 없어.');
        }
        return AppRestorePlan(
          library: LibraryBackup.merge(currentLibrary, imported.library),
          settings: null,
          changesLibrary: true,
        );
      case AppRestoreMode.replaceSettings:
        if (imported.settings == null) {
          throw const FormatException('백업에 앱 설정이 없어.');
        }
        return AppRestorePlan(
          library: currentLibrary,
          settings: imported.settings!.copyWith(
            autoDownloadOnSave: false, receiveAnnouncements: false),
          changesLibrary: false,
        );
      case AppRestoreMode.replaceEverything:
        if (!imported.includesLibrary || imported.settings == null) {
          throw const FormatException(
            '작품과 앱 설정이 모두 들어 있는 백업이 필요해.');
        }
        return AppRestorePlan(
          library: imported.library,
          settings: imported.settings!.copyWith(
            autoDownloadOnSave: false, receiveAnnouncements: false),
          changesLibrary: true,
        );
    }
  }
}
