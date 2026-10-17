import 'dart:async';
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
    final expectedName = platform == TargetPlatform.android
        ? 'HYP_Viewer_v' + version + '.apk'
        : 'HYP_Viewer_Setup_v' + version + '.exe';
    final matches = assets.where((a) => a.name == expectedName).toList();
    return matches.length == 1 ? matches.first : null;
  }
}

/// Limits expensive Flutter/native progress updates during large installer
/// downloads. Always dispatches 0% and 100% and keeps significant changes.
class UpdateProgressLimiter {
  final Duration minInterval;
  final double minDelta;
  DateTime? _lastAt;
  double? _lastValue;

  UpdateProgressLimiter({
    this.minInterval = const Duration(milliseconds: 300),
    this.minDelta = 0.05,
  });

  bool shouldEmit(double raw, DateTime now) {
    if (!raw.isFinite) return false;
    final value = raw.clamp(0.0, 1.0).toDouble();
    final previous = _lastValue;
    if (previous == null ||
        (value >= 1.0 && previous < 1.0) ||
        (value == 0.0 && previous != 0.0)) {
      _lastAt = now;
      _lastValue = value;
      return true;
    }
    if (value == previous) return false;
    if (_lastAt != null && now.difference(_lastAt!) < minInterval &&
        (value - previous).abs() < minDelta) return false;
    _lastAt = now;
    _lastValue = value;
    return true;
  }
}

/// Small, best-effort LOCAL diagnostic log to distinguish a network error,
/// verified download and installer handover from an unexpected native exit.
/// Never logs URLs, titles, authentication, or the downloaded asset contents.
abstract final class UpdateDiagnostics {
  static Future<void> record(String phase, {
    Object? error, StackTrace? stack, Directory? baseDirectory,
  }) async {
    try {
      final base = baseDirectory ?? await getApplicationSupportDirectory();
      final directory = Directory(base.path +
          Platform.pathSeparator + 'hyp_updates');
      await directory.create(recursive: true);
      final file = File(directory.path +
          Platform.pathSeparator + 'update_diagnostics.log');
      if (await file.exists() && await file.length() > 1024 * 1024) {
        await file.writeAsString('');
      }
      final timestamp = DateTime.now().toUtc().toIso8601String();
      final errorClass = error == null ? '' : ' type=' +
          error.runtimeType.toString();
      final firstFrame = stack == null ? '' :
          ' stack=' + stack.toString().split('\n').first.trim();
      await file.writeAsString(
        '$timestamp $phase$errorClass$firstFrame\n',
        mode: FileMode.append, flush: true,
      );
    } catch (_) {
      // Diagnostics must never cause or interrupt an update.
    }
  }
}

/// Checks public GitHub releases and downloads a SHA-256-verified installer.
/// A download never triggers execution without separate, explicit user input.
class UpdateService {
  static const int maxInstallerBytes = 350 * 1024 * 1024;
  final http.Client client;
  final Directory? baseDirectory;
  final Duration retryBaseDelay;

  UpdateService(this.client, {
    this.baseDirectory,
    this.retryBaseDelay = const Duration(seconds: 1),
  });

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
      if (!RegExp(r'^\d+\.\d+\.\d+(?:\.\d+)?$').hasMatch(value)) return null;
      final parts = value.split('.').map(int.parse).toList();
      return parts.length == 3 ? [...parts, 0] : parts;
    }
    final a = parse(latest);
    final b = parse(current);
    if (a == null || b == null) return false;
    for (var i = 0; i < 4; i++) {
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

  /// Resumes SHA-256-verified GitHub release assets after connection changes.
  /// Incomplete bytes survive app restarts and never count as installed.
  Future<File> download(
      ReleaseUpdate release, ReleaseAsset installer, {
      void Function(double progress)? onProgress,
      void Function(String status)? onStatus,
    }) async {
    if (installer.size < 1 || installer.size > maxInstallerBytes ||
        !ReleaseAsset._trustedAssetUrl(installer.downloadUrl)) {
      throw const FormatException('허용되지 않은 릴리스 설치 파일이야.');
    }
    String expected = '';
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        expected = await _expectedHash(release, installer);
        break;
      } on FormatException {
        rethrow;
      } catch (_) {
        if (attempt == 4) rethrow;
        onStatus?.call('체크섬 서버 재연결 중 (' + (attempt + 1).toString() + '/5)');
        await Future<void>.delayed(retryBaseDelay * (attempt + 1));
      }
    }
    final root = baseDirectory ?? await getApplicationSupportDirectory();
    final dir = Directory(root.path + Platform.pathSeparator + 'hyp_updates');
    await dir.create(recursive: true);
    final temp = File(dir.path + Platform.pathSeparator + installer.name + '.part');
    final target = File(dir.path + Platform.pathSeparator + installer.name);
    final metadata = File(dir.path + Platform.pathSeparator +
        installer.name + '.metadata.json');
    final identity = [release.version, installer.name, installer.size, expected].join('|');

    Future<bool> validHash(File file) async {
      if (!await file.exists() || await file.length() != installer.size) return false;
      final hash = await sha256.bind(file.openRead()).first;
      return hash.toString().toLowerCase() == expected;
    }

    if (await target.exists()) {
      if (await validHash(target)) {
        onProgress?.call(1);
        onStatus?.call('검증된 설치 파일을 다시 사용해.');
        return target;
      }
      await target.delete();
    }
    var etag = '';
    if (await metadata.exists()) {
      try {
        final data = jsonDecode(await metadata.readAsString());
        if (data is Map && data['identity'] == identity) {
          etag = data['etag'] is String ? data['etag'] as String : '';
        } else {
          if (await temp.exists()) await temp.delete();
        }
      } catch (_) {
        if (await temp.exists()) await temp.delete();
      }
    } else if (await temp.exists()) {
      await temp.delete();
    }
    Future<void> saveMetadata() async {
      await metadata.writeAsString(
        jsonEncode({'identity': identity, 'etag': etag}), flush: true);
    }
    await saveMetadata();

    for (var attempt = 0; attempt < 8; attempt++) {
      var received = await temp.exists() ? await temp.length() : 0;
      if (received > installer.size) {
        await temp.delete();
        received = 0;
      }
      if (received == installer.size) {
        onStatus?.call('설치 파일 SHA-256 검증 중...');
        if (await validHash(temp)) {
          if (await target.exists()) await target.delete();
          onProgress?.call(1);
          return await temp.rename(target.path);
        }
        await temp.delete();
        received = 0;
        etag = '';
        await saveMetadata();
      }
      IOSink? sink;
      try {
        onStatus?.call(received > 0
            ? '네트워크 연결 복구 · ' + (received ~/ 1024).toString() + 'KB부터 이어받는 중'
            : '업데이트 파일을 다운로드하는 중...');
        final request = http.Request('GET', installer.downloadUrl);
        if (received > 0) {
          request.headers['Range'] = 'bytes=' + received.toString() + '-';
          if (etag.isNotEmpty) request.headers['If-Range'] = etag;
        }
        final response = await client.send(request)
            .timeout(const Duration(seconds: 20));
        if (response.statusCode == 416) {
          await temp.delete();
          etag = '';
          await saveMetadata();
          continue;
        }
        if (response.statusCode == 404 || response.statusCode == 403 ||
            (response.statusCode >= 400 && response.statusCode < 500 &&
                response.statusCode != 408 && response.statusCode != 429)) {
          throw HttpException('업데이트 파일 요청 거절: HTTP ' + response.statusCode.toString());
        }
        if (response.statusCode != 200 && response.statusCode != 206) {
          throw HttpException('재연결 필요: HTTP ' + response.statusCode.toString());
        }
        if (response.statusCode == 206) {
          final range = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$')
              .firstMatch(response.headers['content-range'] ?? '');
          if (range == null || int.parse(range.group(1)!) != received ||
              int.parse(range.group(3)!) != installer.size ||
              int.parse(range.group(2)!) < received ||
              int.parse(range.group(2)!) >= installer.size) {
            if (await temp.exists()) await temp.delete();
            etag = '';
            await saveMetadata();
            throw const FormatException('잘못된 다운로드 재개 범위야.');
          }
        } else if (received > 0) {
          received = 0;
          if (await temp.exists()) await temp.delete();
        }
        final newEtag = response.headers['etag'];
        if (newEtag != null && newEtag.isNotEmpty) {
          etag = newEtag;
          await saveMetadata();
        }
        sink = temp.openWrite(mode: received > 0 ? FileMode.append : FileMode.write);
        var completed = received;
        onProgress?.call(completed / installer.size);
        await for (final chunk in response.stream.timeout(
            const Duration(seconds: 45))) {
          completed += chunk.length;
          if (completed > maxInstallerBytes || completed > installer.size) {
            throw const FormatException('설치 파일의 크기가 예상보다 커.');
          }
          sink.add(chunk);
          onProgress?.call(completed / installer.size);
        }
        await sink.flush();
        await sink.close();
        sink = null;
        if (completed != installer.size) {
          throw const HttpException('다운로드가 중단됐어. 이어받기를 시도해.');
        }
        onStatus?.call('다운로드 완료 · SHA-256 검증 중...');
        if (!await validHash(temp)) {
          await temp.delete();
          etag = '';
          await saveMetadata();
          throw const FormatException('SHA-256 검증 실패: 손상된 파일을 삭제했어.');
        }
        if (await target.exists()) await target.delete();
        onStatus?.call('설치 파일 검증 완료.');
        return await temp.rename(target.path);
      } on FormatException {
        rethrow;
      } on HttpException catch (error) {
        if (error.message.startsWith('업데이트 파일 요청 거절') || attempt == 7) {
          rethrow;
        }
      } on SocketException {
        if (attempt == 7) rethrow;
      } on TimeoutException {
        if (attempt == 7) rethrow;
      } catch (_) {
        if (attempt == 7) rethrow;
      } finally {
        await sink?.flush();
        await sink?.close();
      }
      final seconds = (1 << attempt).clamp(1, 12).toInt();
      onStatus?.call('네트워크 재연결 대기 중 (' + (attempt + 2).toString() + '/8)');
      await Future<void>.delayed(retryBaseDelay * seconds);
    }
    throw const HttpException('재시도 횟수를 초과했어. 다시 누르면 이어받아.');
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
