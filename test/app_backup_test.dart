import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/app_backup.dart';
import 'package:hyp_viewer/core/reading_history.dart';
import 'package:hyp_viewer/core/reader_settings.dart';
import 'package:hyp_viewer/core/work.dart';

void main() {
  test('JSON backup round-trips real on-device reading sessions', () {
    final now = DateTime.utc(2026, 10, 15);
    final item = ReadingSession(workId: '100', startedAt: now,
        endedAt: now.add(const Duration(seconds: 15)), startPage: 1,
        endPage: 2, activeSeconds: 15, completed: false);
    final backup = AppBackup(library: LibraryBackup(
      works: [WorkEntry.create(workId: '100')], collections: const []),
      readingSessions: [item], includesReadingHistory: true);
    final imported = AppBackup.decode(utf8.decode(backup.encode()));
    expect(imported.includesReadingHistory, true);
    expect(imported.readingSessions.single.activeSeconds, 15);
  });

  final pc = LibraryBackup(
    works: [WorkEntry.create(workId: '1111111', title: 'PC')
        .copyWith(favorite: true, currentPage: 18)],
    collections: const ['PC collection'],
  );
  final phone = LibraryBackup(
    works: [WorkEntry.create(workId: '2222222', title: 'Phone')],
    collections: const ['Phone collection'],
  );
  final pcSettings = const ReaderSettings(languageCode: 'ko');
  final phoneSettings = const ReaderSettings(
    languageCode: 'ja',
    tapNavigation: true, webtoonMode: true,
    preloadPages: -1, autoDownloadOnSave: true,
    receiveAnnouncements: true,
  );

  test('new JSON includes all reader settings and works; accepts old JSON', () {
    final file = AppBackup(library: phone, settings: phoneSettings);
    final parsed = AppBackup.decode(utf8.decode(file.encode()));
    expect(parsed.library.works.single.workId, '2222222');
    expect(parsed.settings!.languageCode, 'ja');
    expect(parsed.settings!.preloadPages, -1);
    expect(parsed.settings!.webtoonMode, true);
    expect(parsed.settings!.tapNavigation, true);
    final legacy = AppBackup.decode(phone.encode());
    expect(legacy.includesLibrary, true);
    expect(legacy.hasSettings, false);
    expect(() => AppRestorePlan.build(pc, pcSettings, legacy,
        AppRestoreMode.replaceSettings), throwsFormatException);
  });

  test('add works preserves both device shelves and destination settings', () {
    final incoming = AppBackup(library: phone, settings: phoneSettings);
    final plan = AppRestorePlan.build(
        pc, pcSettings, incoming, AppRestoreMode.addWorks);
    expect(plan.library.works.map((w) => w.workId).toSet(),
        {'1111111', '2222222'});
    expect(plan.settings, isNull);
    expect(plan.library.works.first.favorite, true);
  });

  test('settings-only keeps works and resets permission based toggles', () {
    final incoming = AppBackup(library: phone, settings: phoneSettings);
    final plan = AppRestorePlan.build(
        pc, pcSettings, incoming, AppRestoreMode.replaceSettings);
    expect(plan.library.works.single.workId, '1111111');
    expect(plan.changesLibrary, false);
    expect(plan.settings!.languageCode, 'ja');
    expect(plan.settings!.autoDownloadOnSave, false);
    expect(plan.settings!.receiveAnnouncements, false);
  });

  test('full replacement requires both settings and library', () {
    final incoming = AppBackup(library: phone, settings: phoneSettings);
    final plan = AppRestorePlan.build(
        pc, pcSettings, incoming, AppRestoreMode.replaceEverything);
    expect(plan.library.works.single.workId, '2222222');
    expect(plan.settings!.languageCode, 'ja');
    final settingsOnly = AppBackup(
      library: const LibraryBackup(works: [], collections: []),
      settings: phoneSettings, includesLibrary: false,
    );
    expect(() => AppRestorePlan.build(pc, pcSettings, settingsOnly,
        AppRestoreMode.replaceEverything), throwsFormatException);
  });

  test('cover and banner images can optionally be embedded', () {
    final cover = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10,
        1, 2, 3, 4, 5, 6, 7, 8]);
    final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff,
        0, 0, 0, 0, 0, 0, 0, 0, 0]);
    final bundle = AppBackup(
      library: phone, settings: phoneSettings,
      bannerImage: jpeg,
      covers: [BackupCover(workId: '2222222',
          mode: 'custom', page: 1, bytes: cover)],
    );
    final parsed = AppBackup.decode(utf8.decode(bundle.encode()));
    expect(parsed.bannerImage, jpeg);
    expect(parsed.covers.single.bytes, cover);
  });

  test('v0.3-era JSON without edition fields remains compatible', () {
    final legacy = LibraryBackup(
      works: [WorkEntry.create(workId: '1111111', title: 'Legacy')
          .copyWith(currentPage: 14, favorite: true,
              collections: ['Old Shelf'])],
      collections: const ['Old Shelf'],
    ).toJson();
    final oldWorks = (legacy['works'] as List).cast<Map<String, Object?>>();
    for (final entry in oldWorks) {
      entry.remove('editionGroupId');
      entry.remove('sourceLanguage');
      entry.remove('groupOrder');
      entry.remove('lastOpenedAt');
    }
    final restored = AppBackup.decode(jsonEncode(legacy));
    final work = restored.library.works.single;
    expect(work.editionGroupId, isEmpty);
    expect(work.currentPage, 14);
    expect(work.favorite, true);
    expect(work.collections, ['Old Shelf']);
    expect(restored.library.collections, ['Old Shelf']);
    expect(AppBackup.decode(utf8.decode(
        AppBackup(library: restored.library).encode()))
        .library.works.single.currentPage, 14);
  });

  test('unknown schema and malicious cover path fail before import', () {
    final raw = AppBackup(library: phone, settings: phoneSettings).toJson();
    raw['schemaVersion'] = 999;
    expect(() => AppBackup.decode(jsonEncode(raw)), throwsFormatException);
    final bad = AppBackup(
      library: phone, settings: phoneSettings,
      covers: [BackupCover(
        workId: '../2222222', mode: 'custom', page: 1,
        bytes: Uint8List.fromList([1, 2, 3]))],
    );
    expect(bad.encode, throwsFormatException);
  });
}
