import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

enum AndroidDpiPhase { stopped, starting, running, stopping, failed, unavailable }

class AndroidDpiPreferences {
  final bool enabled;
  final bool autoStart;
  final String preset;

  const AndroidDpiPreferences({
    this.enabled = false, this.autoStart = false, this.preset = 'standard',
  });

  static const presets = ['standard', 'strong', 'sni'];
  static const options = <String, String>{
    'standard': '-s 1',
    'strong': '-s 1 -q 1',
    'sni': '-s 0+sm',
  };

  AndroidDpiPreferences copyWith({
    bool? enabled, bool? autoStart, String? preset,
  }) => AndroidDpiPreferences(
    enabled: enabled ?? this.enabled,
    autoStart: autoStart ?? this.autoStart,
    preset: preset ?? this.preset,
  );

  Map<String, Object> toJson() => {
    'enabled': enabled, 'autoStart': autoStart, 'preset': preset,
  };

  factory AndroidDpiPreferences.fromJson(Map<String, dynamic> json) =>
      AndroidDpiPreferences(
        enabled: json['enabled'] == true,
        autoStart: json['autoStart'] == true,
        preset: presets.contains(json['preset'])
            ? json['preset'] as String : 'standard',
      );
}

/// Installed globally on Android to route all Dart HttpClient requests
/// (including metadata and image downloads) through the on-device CONNECT
/// proxy. Loopback traffic always remains direct.
class AndroidDpiHttpOverrides extends HttpOverrides {
  static int? _port;

  static bool get enabled => _port != null;
  static int? get port => _port;

  static void setLocalPort(int? port) {
    if (port != null && (port < 1025 || port > 65535)) {
      throw ArgumentError.value(port, 'port');
    }
    _port = port;
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (uri) {
      final port = _port;
      if (port == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
        return 'DIRECT';
      }
      if (uri.host == 'localhost' || uri.host == '127.0.0.1' ||
          uri.host == '::1') return 'DIRECT';
      return 'PROXY 127.0.0.1:$port';
    };
    return client;
  }
}

class AndroidDpiManager extends ChangeNotifier {
  AndroidDpiManager._();
  static final instance = AndroidDpiManager._();
  static const _channel = MethodChannel('hyp_viewer/android_dpi');

  AndroidDpiPreferences preferences = const AndroidDpiPreferences();
  AndroidDpiPhase phase = AndroidDpiPhase.stopped;
  bool initialized = false;
  String diagnostic = '';
  Future<void>? _initialization;
  Timer? _monitor;
  Future<void> _pending = Future<void>.value();

  Future<File> get _settingsFile async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File(dir.path + Platform.pathSeparator + 'hyp_android_dpi.json');
  }

  void _status(AndroidDpiPhase next, [String code = '']) {
    phase = next;
    diagnostic = code;
    notifyListeners();
  }

  Future<void> initialize() => _initialization ??= _initialize();
  Future<void> _initialize() async {
    if (!Platform.isAndroid) {
      initialized = true;
      _status(AndroidDpiPhase.unavailable, 'android-only');
      return;
    }
    HttpOverrides.global ??= AndroidDpiHttpOverrides();
    try {
      final file = await _settingsFile;
      if (await file.exists()) {
        final obj = jsonDecode(await file.readAsString());
        if (obj is Map<String, dynamic>) {
          preferences = AndroidDpiPreferences.fromJson(obj);
        }
      }
    } catch (_) {
      diagnostic = 'settings-load-failed';
    }
    initialized = true;
    notifyListeners();
    try {
      final status = await _channel.invokeMapMethod<String, dynamic>('status');
      if (status?['supported'] != true) {
        _status(AndroidDpiPhase.unavailable, 'webview-proxy-unsupported');
        return;
      }
      if (preferences.enabled &&
          (status?['running'] == true || preferences.autoStart)) {
        await start();
      } else if (status?['running'] == true && !preferences.enabled) {
        await _channel.invokeMethod<void>('stop');
      }
    } catch (_) {
      _status(AndroidDpiPhase.failed, 'initialization-failed');
    }
  }

  Future<void> _save() async {
    final file = await _settingsFile;
    await file.writeAsString(jsonEncode(preferences.toJson()), flush: true);
  }

  Future<void> start() => _serialize(_start);
  Future<void> _start() async {
    if (!Platform.isAndroid) {
      _status(AndroidDpiPhase.unavailable, 'android-only');
      return;
    }
    if (phase == AndroidDpiPhase.starting || phase == AndroidDpiPhase.running) {
      return;
    }
    _status(AndroidDpiPhase.starting);
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'start', {'preset': preferences.preset},
      ).timeout(const Duration(seconds: 15));
      final port = result?['port'];
      if (result?['running'] != true || port is! int ||
          port < 1025 || port > 65535) {
        throw const FormatException('Proxy did not report a listening port');
      }
      AndroidDpiHttpOverrides.setLocalPort(port);
      preferences = preferences.copyWith(enabled: true);
      await _save();
      _status(AndroidDpiPhase.running);
      _monitor?.cancel();
      _monitor = Timer.periodic(const Duration(seconds: 8), (_) {
        unawaited(refresh());
      });
    } catch (error) {
      AndroidDpiHttpOverrides.setLocalPort(null);
      try { await _channel.invokeMethod<void>('stop'); } catch (_) {}
      _status(AndroidDpiPhase.failed, error is PlatformException
          ? error.code : 'engine-start-failed');
    }
  }

  Future<void> stop() => _serialize(_stop);
  Future<void> _stop() async {
    _monitor?.cancel();
    _monitor = null;
    _status(AndroidDpiPhase.stopping);
    try {
      await _channel.invokeMethod<void>('stop')
          .timeout(const Duration(seconds: 8));
      AndroidDpiHttpOverrides.setLocalPort(null);
      preferences = preferences.copyWith(enabled: false);
      await _save();
      _status(AndroidDpiPhase.stopped);
    } catch (error) {
      // Never claim direct networking if the proxy override was not cleared.
      _status(AndroidDpiPhase.failed, error is PlatformException
          ? error.code : 'engine-stop-failed');
    }
  }

  Future<void> setEnabled(bool enabled) async {
    await initialize();
    if (enabled) return start();
    return stop();
  }

  Future<void> setAutoStart(bool selected) async {
    preferences = preferences.copyWith(autoStart: selected);
    await _save();
    notifyListeners();
  }

  Future<void> setPreset(String preset) async {
    if (!AndroidDpiPreferences.presets.contains(preset)) {
      throw ArgumentError.value(preset, 'preset');
    }
    if (preset == preferences.preset) return;
    final wasRunning = phase == AndroidDpiPhase.running;
    if (wasRunning) {
      await stop();
      if (phase != AndroidDpiPhase.stopped) return;
    }
    preferences = preferences.copyWith(preset: preset);
    await _save();
    notifyListeners();
    if (wasRunning) await start();
  }

  Future<void> refresh() async {
    if (!Platform.isAndroid || phase != AndroidDpiPhase.running) return;
    try {
      final actual = await _channel.invokeMapMethod<String, dynamic>('status');
      if (actual?['running'] != true ||
          actual?['port'] != AndroidDpiHttpOverrides.port) {
        _monitor?.cancel();
        _monitor = null;
        // A dead proxy must produce a visible error, never a silent bypass.
        _status(AndroidDpiPhase.failed, 'proxy-disconnected');
      }
    } catch (_) {
      _status(AndroidDpiPhase.failed, 'status-check-failed');
    }
  }

  Future<bool> checkSite() async {
    if (!Platform.isAndroid || phase != AndroidDpiPhase.running) return false;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(Uri.https('hitomi.la', '/'))
          .timeout(const Duration(seconds: 10));
      final response = await request.close()
          .timeout(const Duration(seconds: 10));
      await response.drain<void>().timeout(const Duration(seconds: 10));
      return response.statusCode >= 200 && response.statusCode < 500;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _serialize(Future<void> Function() work) {
    final next = _pending.then((_) => work());
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }
}
