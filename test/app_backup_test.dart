import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/app_backup.dart';
import 'package:hyp_viewer/core/reader_settings.dart';
import 'package:hyp_viewer/core/work.dart';

void main() {
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
