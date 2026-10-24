import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

/// v0.4.25 Windows compatibility mode: avoid registering native request
/// interception, content blockers or document-start scripts while WebView2
/// is being constructed. They caused a grey native view on affected PCs.
/// Cosmetic filtering is still applied after the page has loaded; Android
/// retains its full network + document-start protections.
abstract final class WebSearchCompatibility {
  static bool supportsNativeAdHooks(TargetPlatform platform) =>
      platform != TargetPlatform.windows;
}

/// The manual and automatic Hitomi browsers share one explicit WebView2
/// environment under writable application support (never the install folder).
/// Initialization failures are surfaced in Flutter instead of creating a
/// blank native view. No browser is initialized on Android.
abstract final class WindowsWebSearchRuntime {
  static Future<WebViewEnvironment?>? _initialization;

  static Future<WebViewEnvironment?> get environment =>
      _initialization ??= _create();

  static Future<WebViewEnvironment?> _create() async {
    if (!Platform.isWindows) return null;
    final version = await WebViewEnvironment.getAvailableVersion();
    if (version == null || version.isEmpty) {
      throw StateError('Microsoft Edge WebView2 Runtime is unavailable.');
    }
    final appSupport = await getApplicationSupportDirectory();
    final folder = Directory(appSupport.path + Platform.pathSeparator +
        'hitomi_web_search_webview2');
    await folder.create(recursive: true);
    return WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(userDataFolder: folder.path));
  }

  /// Called only after an initialization error, not while a WebView is alive.
  static void retryFailedInitialization() {
    _initialization = null;
  }
}
