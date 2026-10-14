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
    required void Function(bool next) onTurn,
  }) async {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'next') onTurn(true);
      if (call.method == 'previous') onTurn(false);
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
      await _channel.invokeMethod<void>('setVolumeNavigation', volumeNavigation);
    } on MissingPluginException {
      // Older installs and desktop tests can still navigate using touch.
    }
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

  static Future<bool> openSecuritySettings() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _security.invokeMethod<bool>('openSecuritySettings') ?? false;
    } on MissingPluginException {
      return false;
    }
  }
}
