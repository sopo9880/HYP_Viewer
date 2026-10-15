import 'reader_settings.dart';

abstract final class UpdatePrompt {
  static bool shouldShow(ReaderSettings settings,
      String availableVersion, DateTime now, {bool automatic = true,
      bool dismissedThisLaunch = false}) {
    if (!automatic) return true;
    if (!settings.startupUpdatePrompt || dismissedThisLaunch) return false;
    if (settings.snoozedUpdateVersion != availableVersion) return true;
    final until = DateTime.tryParse(settings.snoozedUpdateUntil);
    return until == null || !now.toUtc().isBefore(until.toUtc());
  }

  static ReaderSettings snooze(ReaderSettings current,
      String version, DateTime now) => current.copyWith(
    snoozedUpdateVersion: version,
    snoozedUpdateUntil: now.toUtc()
        .add(const Duration(days: 7)).toIso8601String(),
  );
}
