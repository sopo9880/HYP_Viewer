import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/updates.dart';

class _HandoverClient extends http.BaseClient {
  final List<int> data;
  int requests = 0;
  _HandoverClient(this.data);

  Stream<List<int>> _disconnected() async* {
    yield data.sublist(0, 4);
    throw const SocketException('Wi-Fi disconnected');
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    if (requests == 1) {
      expect(request.headers['Range'], isNull);
      return http.StreamedResponse(_disconnected(), 200);
    }
    expect(request.headers['Range'], 'bytes=4-');
    return http.StreamedResponse(Stream.value(data.sublist(4)), 206,
      headers: {'content-range': 'bytes 4-' +
        (data.length - 1).toString() + '/' + data.length.toString()});
  }
}

void main() {
  test('stable version comparisons ignore older and prerelease tags', () {
    expect(UpdateService.isNewer('0.2.0', '0.1.9'), true);
    expect(UpdateService.isNewer('0.1.0', '0.1.0'), false);
    expect(UpdateService.isNewer('0.1.0', '0.2.0'), false);
    expect(UpdateService.isNewer('0.3.0-rc1', '0.2.0'), false);
    expect(UpdateService.isNewer('0.4.3.1', '0.4.3'), true);
    expect(UpdateService.isNewer('0.4.3.1', '0.4.3.1'), false);
    expect(UpdateService.isNewer('0.4.4', '0.4.3.1'), true);
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

  test('resumes partial APK across a Wi-Fi to cellular handover', () async {
    final bytes = List<int>.generate(64, (i) => i);
    final client = _HandoverClient(bytes);
    final root = await Directory.systemTemp.createTemp('hyp_update_test_');
    addTearDown(() async { client.close(); await root.delete(recursive: true); });
    final asset = ReleaseAsset('HYP_Viewer_v0.3.0.apk',
      Uri.parse('https://github.com/sopo9880/HYP_Viewer/releases/download/v0.3.0/HYP_Viewer_v0.3.0.apk'),
      bytes.length, sha256.convert(bytes).toString());
    final release = ReleaseUpdate('0.3.0', '', '', assets: [asset]);
    final service = UpdateService(client, baseDirectory: root,
        retryBaseDelay: Duration.zero);
    final apk = await service.download(release, asset);
    expect(await apk.readAsBytes(), bytes);
    expect(client.requests, 2);
    final cached = await service.download(release, asset);
    expect(cached.path, apk.path);
    expect(client.requests, 2);
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
