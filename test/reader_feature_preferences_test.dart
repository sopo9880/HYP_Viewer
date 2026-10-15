import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/reader_settings.dart';
import 'package:hyp_viewer/core/work.dart';

void main() {
  test('opt-in reader settings default to privacy and system keys', () {
    const defaults = ReaderSettings();
    expect(defaults.autoCoverEnabled, false);
    expect(defaults.volumeKeyNavigation, false);
    expect(defaults.forceLandscapeForSpreads, false);
    expect(defaults.receiveAnnouncements, false);
    expect(defaults.completedHidden, false);

    final restored = ReaderSettings.fromJson(
        defaults.copyWith(autoCoverEnabled: true,
            volumeKeyNavigation: true,
            forceLandscapeForSpreads: true,
            receiveAnnouncements: true).toJson());
    expect(restored.autoCoverEnabled, true);
    expect(restored.volumeKeyNavigation, true);
    expect(restored.forceLandscapeForSpreads, true);
    expect(restored.receiveAnnouncements, true);
    expect(ReaderSettings.fromJson(defaults.copyWith(completedHidden: true).toJson()).completedHidden, true);
  });

  test('custom cover metadata survives JSON backup', () {
    final work = WorkEntry.create(workId: '2711759').copyWith(
        coverMode: 'custom', coverPage: 7);
    final backup = LibraryBackup(
      works: [work], collections: const []);
    final parsed = LibraryBackup.decode(backup.encode()).works.single;
    expect(parsed.coverMode, 'custom');
    expect(parsed.coverPage, 7);
  });
}
