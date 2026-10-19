import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/windows_dpi.dart';

void main() {
  test('DPI is off by default and user must opt in', () {
    const prefs = WindowsDpiPreferences();
    expect(prefs.enabled, false);
    expect(prefs.autoStart, false);
    expect(prefs.arguments, ['-9']);
  });

  test('presets and preferences persist without changing library schema', () {
    for (final preset in WindowsDpiPreferences.presets) {
      final prefs = WindowsDpiPreferences(
        preset: preset, autoStart: true, enabled: true,
        custom: '-5 --dns-addr 1.1.1.1 --dns-port 53',
      );
      final parsed = WindowsDpiPreferences.fromJson(prefs.toJson());
      expect(parsed.preset, preset);
      expect(parsed.arguments, isNotEmpty);
    }
    expect(WindowsDpiPreferences.fromJson({}).enabled, false);
    expect(WindowsDpiPreferences.fromJson({}).autoStart, false);
  });

  test('custom args prohibit shell injection, paths and unsupported switches', () {
    expect(WindowsDpiPreferences.parseCustom(
        '-9 --dns-addr 1.1.1.1 --dns-port 53'),
        ['-9', '--dns-addr', '1.1.1.1', '--dns-port', '53']);
    expect(WindowsDpiPreferences.parseCustom(
        '-1 --blacklist russia-blacklist.txt'),
        ['-1', '--blacklist', 'russia-blacklist.txt']);
    for (final bad in [
      '', '; calc.exe', '-9 && calc.exe', '-9 | command',
      '-9 --blacklist ../../bad.txt',
      '-9 --blacklist C:/windows/a.txt',
      '-9 --dns-addr bad.host', '-9 --dns-addr 999.999.999.999',
      '-9 --dns-port abc', '-9 --fake-from-hex abc',
      '-9 --blacklist', '-9 -e nope',
    ]) {
      expect(() => WindowsDpiPreferences.parseCustom(bad),
        throwsFormatException, reason: 'reject $bad');
    }
  });

  test('each manager launch uses a random opaque session ID', () {
    final a = WindowsDpiManager.createSessionId();
    final b = WindowsDpiManager.createSessionId();
    expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(a), true);
    expect(a, isNot(b));
  });

  test('Windows supervisor startup distinguishes three timeout causes', () {
    final classify = WindowsDpiManager.classifyStartupTimeout;
    expect(classify('starting', const Duration(seconds: 5)), isNull);
    expect(classify('starting', const Duration(seconds: 9)),
        'supervisor-no-start');
    expect(classify('elevation-requested', const Duration(seconds: 30)),
        isNull);
    expect(classify('elevation-requested', const Duration(seconds: 51)),
        'elevation-approval-timeout');
    expect(classify('engine-starting', const Duration(seconds: 51)),
        'engine-start-timeout');
    expect(classify('supervisor-elevated', const Duration(seconds: 51)),
        'engine-start-timeout');
    expect(classify('supervisor-started', const Duration(seconds: 51)),
        'supervisor-start-timeout');
  });

  test('Windows engine forwards explicit session path and captures launch exit',
      () async {
    final supervisor = await File('scripts/windows_dpi_supervisor.ps1')
        .readAsString();
    final manager = await File('lib/core/windows_dpi.dart').readAsString();
    final windowsTest = await File('scripts/test_windows_dpi_supervisor.ps1')
        .readAsString();
    final workflow = await File('.github/workflows/verify.yml')
        .readAsString();

    expect(supervisor, contains('[string] $SessionPath'));
    expect(supervisor, contains('Status \'supervisor-started\''));
    expect(supervisor, contains('Status \'elevation-requested\''));
    expect(supervisor, contains('Status \'supervisor-elevated\''));
    expect(supervisor, contains('Status \'engine-starting\''));
    expect(supervisor, contains('Status \'diagnostic-ready\''));
    expect(supervisor, contains('supervisor-error.txt'));
    expect(supervisor, contains('Stop-Process -Id $child.Id'));
    expect(manager, contains("'-SessionPath', folder.path"));
    expect(manager, contains('ProcessStartMode.normal'));
    expect(manager, contains('process.exitCode'));
    expect(manager, contains('launcher-log.txt'));
    expect(manager, contains('supervisor-not-started'));
    expect(manager, isNot(contains("'elevation-timeout'")));
    expect(windowsTest, contains('-DiagnosticProbe'));
    expect(workflow, contains('scripts/test_windows_dpi_supervisor.ps1'));
  });

}
