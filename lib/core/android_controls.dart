import 'dart:io';

import 'package:flutter/services.dart';

/// Native volume events are consumed only while the reader is visible and
/// the user has opted in; elsewhere they retain normal system volume behavior.
class AndroidReaderControls {
  static const _channel = MethodChannel('hyp_viewer/reader_control');
  static const _security = MethodChannel('hyp_viewer/security');

  static Future<void> activate({
    required bool volumeNavigation,
    required bool forceLandscape,
    required int repeatIntervalMs,
    required void Function(bool next, bool repeating) onTurn,
  }) async {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'next') onTurn(true, false);
      if (call.method == 'previous') onTurn(false, false);
      if (call.method == 'nextRepeat') onTurn(true, true);
      if (call.method == 'previousRepeat') onTurn(false, true);
    });
    try {
      if (forceLandscape) {
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      }
      await _channel.invokeMethod<void>('setVolumeNavigation', {
        'enabled': volumeNavigation,
        'intervalMs': repeatIntervalMs,
      });
    } on MissingPluginException {
      // Older installs and desktop tests can still navigate using touch.
    }
  }

  /// Disable the active hold's timer at the reader boundary until KEY_UP.
  static Future<void> pauseRepeats() async {
    if (!Platform.isAndroid) return;
    try { await _channel.invokeMethod<void>('pauseVolumeRepeat'); }
    on MissingPluginException { /* Older Android runners. */ }
  }

  static Future<void> deactivate() async {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler(null);
    try {
      await _channel.invokeMethod<void>('setVolumeNavigation', false);
    } on MissingPluginException {
      // Screen cleanup must work even without platform integration.
    } finally {
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
  }

  /// Completes only after the user returns from Android Settings.
  /// Security protections are never modified programmatically.
  static Future<bool> openSecuritySettingsForUpdate() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _security.invokeMethod<bool>(
          'openSecuritySettingsForUpdate') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> openSecuritySettings() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _security.invokeMethod<bool>('openSecuritySettings') ?? false;
    } on MissingPluginException {
      return false;
    }
  }
}
