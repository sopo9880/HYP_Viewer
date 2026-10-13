import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'gallery.dart';

/// A remote gallery is opt-in and must be supplied by a source the user is
/// authorized to access. The source manifest explicitly grants downloads.
/// This module intentionally does not scrape or bypass other sites.
class OnlineGallery implements GalleryPageSource {
  final String workId;
  final String title;
  final bool downloadAllowed;
  final Uri manifestUrl;
  final List<Uri> pageUrls;
  final http.Client _client;

  const OnlineGallery({
    required this.workId,
    required this.title,
    required this.downloadAllowed,
    required this.manifestUrl,
    required this.pageUrls,
    required http.Client client,
  }) : _client = client;

  int get pageCount => pageUrls.length;

  String filename(int index) {
    final ext = pageExtension(pageUrls[index]);
    return 'page_' + (index + 1).toString().padLeft(5, '0') + '.' + ext;
  }

  Future<Uint8List> loadPage(int index, {CancelDownload? cancellation}) async {
    if (index < 0 || index >= pageUrls.length) {
      throw RangeError.index(index, pageUrls);
    }
    return BoundedWebImages.load(
      _client,
      pageUrls[index],
      maxBytes: GalleryArchive.maxSingleImageBytes,
      cancellation: cancellation,
    );
  }

  static String pageExtension(Uri url) {
    final path = url.path.toLowerCase();
    final match = RegExp(r'\.(jpg|jpeg|png|webp|gif|bmp)$').firstMatch(path);
    return match?.group(1) ?? 'jpg';
  }
}

class CancelDownload {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
  void check() {
    if (_cancelled) throw const DownloadCancelled();
  }
}

class DownloadCancelled implements Exception {
  const DownloadCancelled();
  @override
  String toString() => '다운로드가 취소됐어.';
}

/// Only ordinary public HTTPS origins are supported, and image URLs must
/// remain on the manifest's origin. Redirects and local network IPs are
/// intentionally rejected to avoid reading local services or arbitrary hosts.
class OnlineSourcePolicy {
  static bool isHttpsPublic(Uri url) {
    if (url.scheme != 'https' || url.host.isEmpty ||
        url.port != 443 || url.userInfo.isNotEmpty || url.hasFragment ||
        url.host == 'localhost' || url.host.endsWith('.localhost') ||
        url.host.endsWith('.local') || url.host.endsWith('.internal') ||
        InternetAddress.tryParse(url.host) != null) {
      return false;
    }
    return RegExp(r'^[a-z0-9.-]+\.[a-z]{2,}$').hasMatch(url.host.toLowerCase());
  }

  static Uri manifestUri(String pattern, String workId) {
    if (!RegExp(r'^\d{1,12}$').hasMatch(workId)) {
      throw const FormatException('작품 번호가 잘못됐어.');
    }
    final marker = '{workId}';
    if (pattern.split(marker).length != 2) {
      throw const FormatException('주소에는 {workId}가 정확히 한 번 들어가야 해.');
    }
    final url = Uri.tryParse(pattern.trim().replaceAll(marker, workId));
    if (url == null || !isHttpsPublic(url) || url.toString().length > 2048) {
      throw const FormatException('공개 HTTPS 도메인의 주소만 지원해.');
    }
    return url;
  }

  static Uri pageUrl(Uri manifestUrl, String raw) {
    if (raw.length > 2048 || raw.trim().isEmpty) {
      throw const FormatException('이미지 주소가 올바르지 않아.');
    }
    final url = manifestUrl.resolve(raw);
    if (!isHttpsPublic(url) || url.host != manifestUrl.host) {
      throw const FormatException('이미지는 매니페스트와 같은 HTTPS 도메인이어야 해.');
    }
    return url;
  }
}

/// Streaming response reader: refuses redirects, oversized payloads and HTML.
/// It does not follow links to arbitrary hosts.
class BoundedWebImages {
  static Future<Uint8List> load(
    http.Client client,
    Uri url, {
    required int maxBytes,
    CancelDownload? cancellation,
    bool image = true,
  }) async {
    if (!OnlineSourcePolicy.isHttpsPublic(url)) {
      throw const FormatException('안전하지 않은 원격 주소야.');
    }
    cancellation?.check();
    final request = http.Request('GET', url)
      ..followRedirects = false
      ..headers['Accept'] = image
          ? 'image/avif,image/webp,image/png,image/jpeg,image/gif,image/bmp'
          : 'application/json';
    final response = await client.send(request).timeout(const Duration(seconds: 18));
    if (response.statusCode != 200) {
      throw HttpException('이미지/매니페스트 서버가 응답하지 않았어: ' +
          response.statusCode.toString(), uri: url);
    }
    if (response.contentLength != null && response.contentLength! > maxBytes) {
      throw const FormatException('원격 파일이 너무 커.');
    }
    final contentType = (response.headers['content-type'] ?? '')
        .split(';').first.trim().toLowerCase();
    if (image) {
      const allowed = {
        'image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/bmp',
        'application/octet-stream',
      };
      if (!allowed.contains(contentType)) {
        throw const FormatException('서버가 이미지가 아닌 파일을 반환했어.');
      }
    } else if (contentType != 'application/json' && contentType != 'text/json') {
      throw const FormatException('JSON 매니페스트만 읽을 수 있어.');
    }

    final builder = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in response.stream.timeout(const Duration(seconds: 25))) {
      cancellation?.check();
      received += chunk.length;
      if (received > maxBytes) {
        throw const FormatException('응답이 허용 크기를 초과했어.');
      }
      builder.add(chunk);
    }
    cancellation?.check();
    return builder.takeBytes();
  }
}

class OnlineGalleryProvider {
  final http.Client client;
  const OnlineGalleryProvider(this.client);

  /// Manifest v1 example:
  /// {
  ///   "schemaVersion": 1, "workId": "2711759",
  ///   "title": "Example", "allowDownload": true,
  ///   "pages": ["/images/001.jpg", "/images/002.jpg"]
  /// }
  Future<OnlineGallery> load(String pattern, String workId) async {
    final manifestUrl = OnlineSourcePolicy.manifestUri(pattern, workId);
    final bytes = await BoundedWebImages.load(
      client, manifestUrl, maxBytes: 200 * 1024, image: false,
    );
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map<String, dynamic> ||
        data['schemaVersion'] != 1 ||
        data['workId'] != workId ||
        data['pages'] is! List) {
      throw const FormatException('지원하지 않는 작품 목록 형식이야.');
    }
    final rawPages = data['pages'] as List;
    if (rawPages.isEmpty || rawPages.length > GalleryArchive.maxPages) {
      throw const FormatException('지원하지 않는 페이지 개수야.');
    }
    final pages = <Uri>[];
    for (final entry in rawPages) {
      if (entry is! String) {
        throw const FormatException('페이지 주소는 문자열이어야 해.');
      }
      pages.add(OnlineSourcePolicy.pageUrl(manifestUrl, entry));
    }
    return OnlineGallery(
      workId: workId,
      title: data['title'] is String ? data['title'] as String : '',
      downloadAllowed: data['allowDownload'] == true,
      manifestUrl: manifestUrl,
      pageUrls: List.unmodifiable(pages),
      client: client,
    );
  }
}

class OnlineSourceSettings {
  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File(dir.path + Platform.pathSeparator + 'online_source.txt');
  }

  Future<String> load() async {
    final file = await _file();
    return await file.exists() ? file.readAsString() : '';
  }

  Future<void> save(String pattern) async {
    // Check template syntax before saving; only the user's chosen source
    // template is stored, never secrets or passwords.
    OnlineSourcePolicy.manifestUri(pattern, '123456');
    final file = await _file();
    await file.writeAsString(pattern.trim(), flush: true);
  }
}

/// Downloads only when explicitly requested and when the provider declares
/// allowDownload=true. Writes CBZ under app support through GalleryStore so
/// an app update does not remove the offline copy.
class OnlineGalleryDownloader {
  static const int maxTotalImageBytes = 165 * 1024 * 1024;
  final GalleryStore galleryStore;
  final Directory? temporaryDirectory;

  const OnlineGalleryDownloader(this.galleryStore, {this.temporaryDirectory});

  Future<GalleryArchive> download(
    OnlineGallery remote, {
    required CancelDownload cancellation,
    void Function(int completed, int total, int bytes)? onProgress,
  }) async {
    if (!remote.downloadAllowed) {
      throw const FormatException('이 소스는 다운로드를 허용하지 않아.');
    }
    final app = temporaryDirectory ?? await getApplicationSupportDirectory();
    final staging = Directory(
      app.path + Platform.pathSeparator + 'gallery_import_' +
      remote.workId + '_' + DateTime.now().microsecondsSinceEpoch.toString(),
    );
    await staging.create(recursive: true);
    final zipFile = File(staging.path + Platform.pathSeparator + 'gallery.cbz');
    final encoder = ZipFileEncoder();
    var opened = false;
    var totalBytes = 0;
    var completed = 0;
    try {
      encoder.create(zipFile.path, level: ZipFileEncoder.store);
      opened = true;
      for (var i = 0; i < remote.pageCount; i++) {
        cancellation.check();
        final image = await remote.loadPage(i, cancellation: cancellation);
        totalBytes += image.length;
        if (totalBytes > maxTotalImageBytes) {
          throw const FormatException('작품 다운로드 크기 제한(165MB)을 초과했어.');
        }
        final name = remote.filename(i);
        final pageFile = File(staging.path + Platform.pathSeparator + name);
        await pageFile.writeAsBytes(image, flush: true);
        cancellation.check();
        await encoder.addFile(pageFile, name, ZipFileEncoder.store);
        await pageFile.delete();
        completed++;
        onProgress?.call(completed, remote.pageCount, totalBytes);
      }
      await encoder.close();
      opened = false;
      cancellation.check();
      if (await zipFile.length() > GalleryArchive.maxCompressedBytes) {
        throw const FormatException('완성된 ZIP 파일이 너무 커.');
      }
      return await galleryStore.importFile(remote.workId, zipFile.path);
    } finally {
      if (opened) {
        try { await encoder.close(); } catch (_) {}
      }
      // On cancellation/failure do not touch the previous offline gallery.
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
  }
}
