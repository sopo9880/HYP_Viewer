import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/reader_settings.dart';
import 'package:hyp_viewer/core/update_prompt.dart';

void main() {
  test('seven days per version; newer version overrides snooze', () {
    final now = DateTime.utc(2026, 10, 16);
    final snoozed = UpdatePrompt.snooze(const ReaderSettings(), '0.4.0', now);
    expect(UpdatePrompt.shouldShow(snoozed, '0.4.0',
        now.add(const Duration(days: 6))), false);
    expect(UpdatePrompt.shouldShow(snoozed, '0.4.0',
        now.add(const Duration(days: 7))), true);
    expect(UpdatePrompt.shouldShow(snoozed, '0.4.1', now), true);
    expect(UpdatePrompt.shouldShow(snoozed, '0.4.0', now,
        automatic: false), true);
  });
  test('startup preference can disable automatic prompts', () {
    const settings=ReaderSettings(startupUpdatePrompt: false);
    expect(UpdatePrompt.shouldShow(settings,'0.4.0',DateTime.utc(2026)),false);
  });
  test('settings JSON preserves prompt fields', () {
    final s = UpdatePrompt.snooze(const ReaderSettings(), '0.4.0',
        DateTime.utc(2026, 10, 16));
    final recovered = ReaderSettings.fromJson(s.toJson());
    expect(recovered.snoozedUpdateVersion, '0.4.0');
    expect(recovered.snoozedUpdateUntil, s.snoozedUpdateUntil);
  });
}
