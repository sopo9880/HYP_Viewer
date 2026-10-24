import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/windows_web_search.dart';

void main() {
  test('Windows uses WebView2-safe cosmetic filtering; Android keeps blocking', () {
    expect(WebSearchCompatibility.supportsNativeAdHooks(TargetPlatform.windows),
        isFalse);
    expect(WebSearchCompatibility.supportsNativeAdHooks(TargetPlatform.android),
        isTrue);
  });

  test('manual and automatic Windows search share a writable WebView2 environment', () {
    final runtime = File('lib/core/windows_web_search.dart').readAsStringSync();
    expect(runtime, contains('WebViewEnvironment.getAvailableVersion()'));
    expect(runtime, contains('getApplicationSupportDirectory()'));
    expect(runtime, contains('WebViewEnvironment.create('));
    expect(runtime, contains('hitomi_web_search_webview2'));

    final manual = File('lib/ui/hitomi_web_search_page.dart')
        .readAsStringSync();
    final automatic = File('lib/ui/auto_hitomi_web_search.dart')
        .readAsStringSync();
    for (final source in [manual, automatic]) {
      expect(source, contains('WindowsWebSearchRuntime.environment'));
      expect(source, contains('webViewEnvironment: environment'));
      expect(source, contains('shouldInterceptRequest: Platform.isWindows ? null'));
      expect(source, contains(
          'contentBlockers: Platform.isWindows ? const <ContentBlocker>[]'));
      expect(source, contains('!Platform.isWindows'));
      expect(source, contains('WebSearchAdBlock.cleanPageJavaScript'));
    }
    expect(manual, contains('WindowsWebSearchRuntime.retryFailedInitialization()'));
    expect(manual, contains('외부 브라우저에서 열기'));
    expect(manual, contains('Timer(const Duration(seconds: 15)'));
    expect(automatic, contains('webview2-initialization-failed'));
  });

  test('Windows update refuses active transfer and waits for owned DPI shutdown', () {
    final main = File('lib/main.dart').readAsStringSync();
    final start = main.indexOf('Future<void> _downloadInstaller(');
    final end = main.indexOf('/// One GitHub update check', start);
    final updater = main.substring(start, end);
    expect(updater, contains('_downloadQueueRunning'));
    expect(updater, contains('_backgroundDownloads.hasTransfers'));
    expect(updater, contains("UpdateDiagnostics.record('handover-deferred-active-download')"));
    expect(updater, contains("phase = 'dpi-shutdown';"));
    expect(updater, contains('await dpi.stop().timeout('));
    expect(updater.indexOf('await dpi.stop()'),
        lessThan(updater.indexOf('launchInstaller(installer)')));
    expect(updater, contains('exit(0);'));
    expect(updater, contains("await UpdateDiagnostics.record('end');"));
  });

  test('installer cleanup is scoped to HYP executable and supervisor sessions', () {
    final installer = File('installer/hyp_viewer.iss').readAsStringSync();
    final cleanup = File('scripts/windows_update_cleanup.ps1').readAsStringSync();
    expect(installer, contains('function PrepareToInstall('));
    expect(installer, contains('Flags: dontcopy'));
    expect(installer, contains('ExtractTemporaryFile('));
    expect(installer, contains('windows_update_cleanup.ps1'));
    expect(installer, contains('CloseApplications=yes'));
    expect(cleanup, contains('IsExactOwnedProcess'));
    expect(cleanup, contains("ProcessId=\$ProcessId"));
    expect(cleanup, contains('stop.signal'));
    expect(cleanup, contains('GetOwnedDpiSessions'));
    expect(cleanup, contains('Stop-Process -Id'));
    expect(cleanup, isNot(contains('Stop-Service')));
    expect(cleanup, isNot(contains('sc.exe delete')));
    expect(cleanup, isNot(contains('Remove-Item')));
    expect(cleanup, isNot(contains('Stop-Process -Name')));
    expect(cleanup, isNot(contains('taskkill')));
  });
}
