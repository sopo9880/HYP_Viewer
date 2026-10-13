import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

class ReleaseAsset {
  final String name;
  final Uri downloadUrl;
  final int size;
  final String? sha256Hex;

  const ReleaseAsset(this.name, this.downloadUrl, this.size, this.sha256Hex);

  static ReleaseAsset? fromJson(Map<String, dynamic> data) {
    final name = data['name'];
    final rawUrl = data['browser_download_url'];
    if (name is! String || !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(name) ||
        rawUrl is! String || data['size'] is! num) {
      return null;
    }
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !_trustedAssetUrl(uri)) return null;
    final digest = data['digest'];
    final sha = digest is String && RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest)
        ? digest.substring(7).toLowerCase() : null;
    return ReleaseAsset(name, uri, (data['size'] as num).toInt(), sha);
  }

  static bool _trustedAssetUrl(Uri uri) =>
      uri.scheme == 'https' && uri.host == 'github.com' &&
      uri.path.startsWith('/sopo9880/HYP_Viewer/releases/download/');
}

class ReleaseUpdate {
  final String version;
  final String notes;
  final String url;
  final List<ReleaseAsset> assets;

  const ReleaseUpdate(this.version, this.notes, this.url,
      {this.assets = const []});

  ReleaseAsset? installerFor(TargetPlatform platform) {
    if (platform != TargetPlatform.android && platform != TargetPlatform.windows) {
      return null;
    }
    final matches = assets.where((a) {
      if (platform == TargetPlatform.android) {
        return a.name.startsWith('HYP_Viewer_') && a.name.endsWith('.apk');
      }
      return a.name.startsWith('HYP_Viewer_Setup_') && a.name.endsWith('.exe');
    }).toList();
    return matches.length == 1 ? matches.first : null;
  }
}

/// Checks public GitHub releases and downloads a SHA-256-verified installer.
/// A download never triggers execution without separate, explicit user input.
class UpdateService {
  static const int maxInstallerBytes = 350 * 1024 * 1024;
  final http.Client client;

  UpdateService(this.client);

  Future<ReleaseUpdate?> latest(String current) async {
    final response = await client.get(
      Uri.parse('https://api.github.com/repos/sopo9880/HYP_Viewer/releases/latest'),
      headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'HYP-Viewer'},
    ).timeout(const Duration(seconds: 12));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('GitHub Releases status ' + response.statusCode.toString());
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final version = (data['tag_name'] as String? ?? '').replaceFirst(RegExp(r'^v'), '');
    if (!isNewer(version, current)) return null;

    final list = <ReleaseAsset>[];
    for (final item in data['assets'] as List? ?? const []) {
      if (item is Map<String, dynamic>) {
        final parsed = ReleaseAsset.fromJson(item);
        if (parsed != null) list.add(parsed);
      }
    }
    return ReleaseUpdate(
      version,
      data['body'] as String? ?? '',
      data['html_url'] as String? ?? '',
      assets: list,
    );
  }

  static bool isNewer(String latest, String current) {
    List<int>? parse(String value) {
      // Ignore malformed tags and pre-release versions for this stable updater.
      if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(value)) return null;
      return value.split('.').map(int.parse).toList();
    }
    final a = parse(latest);
    final b = parse(current);
    if (a == null || b == null) return false;
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  Future<String> _expectedHash(ReleaseUpdate release, ReleaseAsset installer) async {
    if (installer.sha256Hex != null) return installer.sha256Hex!;
    final checksums = release.assets.where((a) => a.name == 'SHA256SUMS.txt').toList();
    if (checksums.length != 1 || checksums.single.size > 128 * 1024) {
      throw const FormatException('이 릴리스에 SHA-256 검증 정보가 없어.');
    }
    final response = await client.get(checksums.single.downloadUrl)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200 || response.bodyBytes.length > 128 * 1024) {
      throw const FormatException('체크섬 파일을 가져오지 못했어.');
    }
    for (final line in const LineSplitter().convert(response.body)) {
      final match = RegExp(r'^([a-fA-F0-9]{64})\s+\*?(.+)$').firstMatch(line.trim());
      if (match != null && match.group(2) == installer.name) {
        return match.group(1)!.toLowerCase();
      }
    }
    throw const FormatException('설치 파일의 체크섬을 찾지 못했어.');
  }

  Future<File> download(
      ReleaseUpdate release, ReleaseAsset installer, {
      void Function(double progress)? onProgress,
    }) async {
    if (installer.size < 1 || installer.size > maxInstallerBytes ||
        !ReleaseAsset._trustedAssetUrl(installer.downloadUrl)) {
      throw const FormatException('허용되지 않은 릴리스 설치 파일이야.');
    }
    final expected = await _expectedHash(release, installer);
    final root = await getTemporaryDirectory();
    final dir = Directory(root.path + Platform.pathSeparator + 'hyp_updates');
    await dir.create(recursive: true);
    final temp = File(dir.path + Platform.pathSeparator + installer.name + '.part');
    final target = File(dir.path + Platform.pathSeparator + installer.name);
    IOSink? sink;
    try {
      final request = http.Request('GET', installer.downloadUrl);
      final response = await client.send(request).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw HttpException('업데이트 다운로드 실패: HTTP ' + response.statusCode.toString());
      }
      sink = temp.openWrite();
      var received = 0;
      await for (final bytes in response.stream.timeout(const Duration(seconds: 45))) {
        received += bytes.length;
        if (received > maxInstallerBytes || received > installer.size) {
          throw const FormatException('설치 파일의 크기가 예상보다 커.');
        }
        sink.add(bytes);
        onProgress?.call(received / installer.size);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (received != installer.size) {
        throw const FormatException('설치 파일의 크기가 릴리스 정보와 달라.');
      }
      final digest = await sha256.bind(temp.openRead()).first;
      if (digest.toString().toLowerCase() != expected) {
        throw const FormatException('SHA-256 검증 실패: 설치 파일을 사용하지 않을게.');
      }
      if (await target.exists()) await target.delete();
      return await temp.rename(target.path);
    } catch (_) {
      await sink?.close();
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }

  /// Requests the OS installer. Android displays the system package installer.
  /// Windows launches Inno Setup, then the UI may close for replacement.
  Future<void> launchInstaller(File installer) async {
    if (Platform.isAndroid) {
      if (!installer.path.endsWith('.apk')) {
        throw const FormatException('Android 업데이트는 APK 파일만 가능해.');
      }
      final result = await OpenFilex.open(
        installer.path,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type != ResultType.done) {
        throw StateError('Android 설치 화면을 열지 못했어: ' + result.message);
      }
    } else if (Platform.isWindows) {
      if (!installer.path.endsWith('.exe')) {
        throw const FormatException('Windows 업데이트는 EXE 파일만 가능해.');
      }
      await Process.start(
        installer.path,
        ['/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS'],
        mode: ProcessStartMode.detached,
      );
    } else {
      throw UnsupportedError('이 운영체제에서는 자동 설치를 지원하지 않아.');
    }
  }
}
