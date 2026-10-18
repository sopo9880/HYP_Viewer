import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Optional Windows-wide network compatibility mode. Disabled by default.
class WindowsDpiPreferences {
  final bool enabled;
  final bool autoStart;
  final String preset;
  final String custom;

  const WindowsDpiPreferences({
    this.enabled = false,
    this.autoStart = false,
    this.preset = 'recommended',
    this.custom = '-9',
  });

  static const presets = <String>[
    'recommended', 'russia_blacklist', 'russia_blacklist_dnsredir',
    'all', 'all_dnsredir', 'all_dnsredir_hardcore', 'custom',
  ];

  WindowsDpiPreferences copyWith({
    bool? enabled, bool? autoStart, String? preset, String? custom,
  }) => WindowsDpiPreferences(
    enabled: enabled ?? this.enabled,
    autoStart: autoStart ?? this.autoStart,
    preset: preset ?? this.preset,
    custom: custom ?? this.custom,
  );

  Map<String, Object> toJson() => {
    'enabled': enabled, 'autoStart': autoStart,
    'preset': preset, 'custom': custom,
  };

  factory WindowsDpiPreferences.fromJson(Map<String, dynamic> data) {
    final selected = data['preset'] is String &&
        presets.contains(data['preset']) ? data['preset'] as String
        : 'recommended';
    final raw = data['custom'] is String &&
        (data['custom'] as String).length <= 240
        ? data['custom'] as String : '-9';
    return WindowsDpiPreferences(
      enabled: data['enabled'] == true,
      autoStart: data['autoStart'] == true,
      preset: selected, custom: raw,
    );
  }

  List<String> get arguments => switch (preset) {
    'recommended' => const ['-9'],
    'russia_blacklist' =>
      const ['-9', '--blacklist', 'russia-blacklist.txt'],
    'russia_blacklist_dnsredir' =>
      const ['-9', '--blacklist', 'russia-blacklist.txt',
        '--dns-addr', '77.88.8.8', '--dns-port', '1253'],
    'all' => const ['-1'],
    'all_dnsredir' =>
      const ['-1', '--dns-addr', '77.88.8.8', '--dns-port', '1253'],
    'all_dnsredir_hardcore' =>
      const ['-1', '-a', '-m', '--dns-addr', '77.88.8.8',
        '--dns-port', '1253'],
    'custom' => parseCustom(custom),
    _ => const ['-9'],
  };

  /// No shell, quoting, subcommands, paths or unbounded numeric payloads.
  /// The elevated supervisor independently validates again.
  static List<String> parseCustom(String input) {
    if (input.trim().length < 2 || input.length > 240) {
      throw const FormatException('Invalid custom argument length');
    }
    final tokens = input.trim().split(RegExp(r'\s+'));
    if (tokens.length > 30) {
      throw const FormatException('Too many custom options');
    }
    const switches = {
      '-1', '-2', '-3', '-4', '-5', '-6', '-7', '-8', '-9',
      '-p', '-q', '-r', '-s', '-m', '-n', '-a',
      '--reverse-frag', '--wrong-seq', '--wrong-chksum', '--auto-ttl',
    };
    const integers = {
      '-f', '-k', '-e', '--dns-port', '--max-payload', '--set-ttl', '--min-ttl',
    };
    for (var i = 0; i < tokens.length; i++) {
      final flag = tokens[i];
      if (switches.contains(flag)) continue;
      if (!integers.contains(flag) && flag != '--dns-addr' &&
          flag != '--blacklist') {
        throw FormatException('Unsupported GoodbyeDPI flag: $flag');
      }
      if (++i >= tokens.length) {
        throw FormatException('Missing value after $flag');
      }
      final value = tokens[i];
      if (integers.contains(flag)) {
        if (!RegExp(r'^\d{1,5}$').hasMatch(value)) {
          throw FormatException('Invalid numeric value for $flag');
        }
      } else if (flag == '--dns-addr') {
        if (!RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(value) ||
            InternetAddress.tryParse(value)?.type !=
                InternetAddressType.IPv4) {
          throw const FormatException('Expected IPv4 DNS address');
        }
      } else {
        if (!RegExp(r'^[A-Za-z0-9_-]{1,50}\.txt$').hasMatch(value)) {
          throw const FormatException('Expected relative *.txt blacklist');
        }
      }
    }
    return tokens;
  }
}

enum WindowsDpiPhase { stopped, starting, running, stopping, failed, unavailable }

/// Supervises one app-owned elevated GoodbyeDPI engine, never any other
/// processes. The Windows supervisor exits when the parent app exits.
class WindowsDpiManager extends ChangeNotifier {
  WindowsDpiManager._();
  static final WindowsDpiManager instance = WindowsDpiManager._();

  WindowsDpiPreferences preferences = const WindowsDpiPreferences();
  WindowsDpiPhase phase = WindowsDpiPhase.stopped;
  String diagnostic = '';
  bool initialized = false;

  Future<void>? _initialization;
  Directory? _session;
  Timer? _monitor;
  DateTime? _launchAt;

  Future<File> get _settingsFile async {
    final home = await getApplicationSupportDirectory();
    await home.create(recursive: true);
    return File(home.path + Platform.pathSeparator + 'hyp_windows_dpi.json');
  }

  Future<void> initialize() => _initialization ??= _initialize();
  Future<void> _initialize() async {
    if (!Platform.isWindows) {
      phase = WindowsDpiPhase.unavailable;
      initialized = true;
      notifyListeners();
      return;
    }
    try {
      final file = await _settingsFile;
      if (await file.exists()) {
        final raw = jsonDecode(await file.readAsString());
        if (raw is Map<String, dynamic>) {
          preferences = WindowsDpiPreferences.fromJson(raw);
        }
      }
    } catch (_) {
      diagnostic = 'settings-load-failed';
    }
    initialized = true;
    notifyListeners();
    if (preferences.enabled && preferences.autoStart) {
      unawaited(start());
    }
  }

  Future<void> _save() async {
    final file = await _settingsFile;
    await file.writeAsString(jsonEncode(preferences.toJson()), flush: true);
  }

  Future<void> updatePreferences(WindowsDpiPreferences updated) async {
    if (updated.arguments.isEmpty) {
      throw const FormatException('GoodbyeDPI arguments must not be empty');
    }
    final previous = preferences;
    preferences = updated;
    notifyListeners();
    try {
      await _save();
    } catch (_) {
      preferences = previous;
      diagnostic = 'settings-save-failed';
      notifyListeners();
      rethrow;
    }
    if (phase == WindowsDpiPhase.running &&
        (previous.preset != updated.preset ||
         previous.custom != updated.custom)) {
      await restart();
    }
  }

  Future<void> setEnabled(bool enabled) async {
    if (enabled) {
      await updatePreferences(preferences.copyWith(enabled: true));
      await start();
    } else {
      await updatePreferences(preferences.copyWith(enabled: false));
      await stop();
    }
  }

  Future<void> setAutoStart(bool selected) =>
      updatePreferences(preferences.copyWith(autoStart: selected));

  static String createSessionId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  void _setPhase(WindowsDpiPhase next, [String message = '']) {
    if (phase == next && diagnostic == message) return;
    phase = next;
    diagnostic = message;
    notifyListeners();
  }

  Future<void> start() async {
    if (!Platform.isWindows) {
      _setPhase(WindowsDpiPhase.unavailable, 'windows-only');
      return;
    }
    if (phase == WindowsDpiPhase.running ||
        phase == WindowsDpiPhase.starting) return;
    try {
      if (preferences.arguments.isEmpty) {
        throw const FormatException('GoodbyeDPI arguments must not be empty');
      }
      final toolsDir = Directory(File(Platform.resolvedExecutable).parent.path +
          Platform.pathSeparator + 'tools');
      final supervisor = File(toolsDir.path + Platform.pathSeparator +
          'hyp_dpi_supervisor.ps1');
      for (final name in <String>['hyp_dpi_supervisor.ps1',
          'goodbyedpi.exe', 'WinDivert.dll', 'WinDivert64.sys']) {
        if (!await File(toolsDir.path + Platform.pathSeparator + name)
            .exists()) {
          throw const FileSystemException('bundled-engine-missing');
        }
      }
      final appData = Platform.environment['APPDATA'];
      if (appData == null || appData.isEmpty) {
        throw const FileSystemException('appdata-unavailable');
      }
      final id = createSessionId();
      final folder = Directory(appData + Platform.pathSeparator +
          'HYP Viewer' + Platform.pathSeparator + 'dpi_runtime' +
          Platform.pathSeparator + id);
      await folder.create(recursive: true);
      _session = folder;
      await File(folder.path + Platform.pathSeparator + 'arguments.json')
          .writeAsString(jsonEncode({
            'preset': preferences.preset, 'custom': preferences.custom,
          }), flush: true);
      await File(folder.path + Platform.pathSeparator + 'status.txt')
          .writeAsString('starting', flush: true);
      _launchAt = DateTime.now();
      _setPhase(WindowsDpiPhase.starting);
      await Process.start('powershell.exe', [
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-WindowStyle', 'Hidden', '-File', supervisor.path,
        '-SessionId', id, '-ParentPid', pid.toString(),
      ], mode: ProcessStartMode.detached, runInShell: false);
      _monitor?.cancel();
      _monitor = Timer.periodic(const Duration(milliseconds: 500), (_) {
        unawaited(refreshStatus());
      });
    } on FormatException {
      _setPhase(WindowsDpiPhase.failed, 'invalid-arguments');
    } catch (error) {
      _setPhase(WindowsDpiPhase.failed, error is FileSystemException
          ? 'bundled-engine-missing' : 'launcher-failed');
    }
  }

  Future<void> refreshStatus() async {
    final dir = _session;
    if (dir == null) return;
    final status = File(dir.path + Platform.pathSeparator + 'status.txt');
    try {
      if (!await status.exists()) return;
      final value = (await status.readAsString()).trim();
      if (phase == WindowsDpiPhase.starting && value == 'starting' &&
          _launchAt != null &&
          DateTime.now().difference(_launchAt!) > const Duration(seconds: 50)) {
        await File(dir.path + Platform.pathSeparator + 'stop.signal')
            .writeAsString('stop', flush: true);
        _setPhase(WindowsDpiPhase.failed, 'elevation-timeout');
        _monitor?.cancel();
        return;
      }
      if (value.startsWith('running:')) {
        _setPhase(WindowsDpiPhase.running);
      } else if (value == 'stopped') {
        _setPhase(WindowsDpiPhase.stopped);
        _monitor?.cancel();
      } else if (value.startsWith('error:')) {
        _setPhase(WindowsDpiPhase.failed,
          RegExp(r'^error:([a-z-]{1,60})$').firstMatch(value)?.group(1) ??
              'unknown-failure');
        _monitor?.cancel();
      }
    } catch (_) {
      // A concurrently written status file is transient, not success.
    }
  }

  Future<void> stop() async {
    final folder = _session;
    if (folder == null ||
        (phase != WindowsDpiPhase.running &&
         phase != WindowsDpiPhase.starting &&
         phase != WindowsDpiPhase.stopping)) return;
    _setPhase(WindowsDpiPhase.stopping);
    try {
      await File(folder.path + Platform.pathSeparator + 'stop.signal')
          .writeAsString('stop', flush: true);
      for (var i = 0; i < 28; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await refreshStatus();
        if (phase == WindowsDpiPhase.stopped ||
            phase == WindowsDpiPhase.failed) return;
      }
      _setPhase(WindowsDpiPhase.failed, 'stop-timeout');
    } catch (_) {
      _setPhase(WindowsDpiPhase.failed, 'stop-failed');
    }
  }

  Future<void> restart() async {
    await stop();
    if (phase == WindowsDpiPhase.stopped ||
        phase == WindowsDpiPhase.failed) await start();
  }

  Future<bool> checkSite() async {
    if (!Platform.isWindows) return false;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final request = await client.getUrl(Uri.https('hitomi.la', '/'))
          .timeout(const Duration(seconds: 8));
      final response = await request.close()
          .timeout(const Duration(seconds: 8));
      await response.drain<void>();
      return response.statusCode >= 200 && response.statusCode < 500;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
