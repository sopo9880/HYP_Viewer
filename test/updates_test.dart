import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/updates.dart';

void main() {
  test('stable version comparisons ignore older and prerelease tags', () {
    expect(UpdateService.isNewer('0.2.0', '0.1.9'), true);
    expect(UpdateService.isNewer('0.1.0', '0.1.0'), false);
    expect(UpdateService.isNewer('0.1.0', '0.2.0'), false);
    expect(UpdateService.isNewer('0.3.0-rc1', '0.2.0'), false);
  });

  test('release asset only accepts expected GitHub owner and path', () {
    ReleaseAsset? parse(String url) => ReleaseAsset.fromJson({
      'name': 'HYP_Viewer_v0.2.0.apk', 'browser_download_url': url, 'size': 42,
      'digest': 'sha256:' + ''.padLeft(64, 'a'),
    });
    expect(parse('https://github.com/sopo9880/HYP_Viewer/releases/download/v0.2.0/HYP_Viewer_v0.2.0.apk'), isNotNull);
    expect(parse('https://github.com.evil.org/sopo9880/HYP_Viewer/releases/download/v0.2.0/x.apk'), isNull);
    expect(parse('http://github.com/sopo9880/HYP_Viewer/releases/download/v0.2.0/x.apk'), isNull);
  });

  test('platform only selects uniquely named assets', () {
    final a = ReleaseAsset('HYP_Viewer_v0.2.0.apk',
      Uri.parse('https://github.com/sopo9880/HYP_Viewer/releases/download/v0.2.0/HYP_Viewer_v0.2.0.apk'), 42, ''.padLeft(64, 'a'));
    final e = ReleaseAsset('HYP_Viewer_Setup_v0.2.0.exe',
      Uri.parse('https://github.com/sopo9880/HYP_Viewer/releases/download/v0.2.0/HYP_Viewer_Setup_v0.2.0.exe'), 42, ''.padLeft(64, 'b'));
    final release = ReleaseUpdate('0.2.0', 'notes', 'https://github.com/sopo9880/HYP_Viewer', assets: [a, e]);
    expect(release.installerFor(TargetPlatform.android)?.name, a.name);
    expect(release.installerFor(TargetPlatform.windows)?.name, e.name);
  });
}
