import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'gallery.dart';
import 'online_gallery.dart';

/// Online image reader adapted independently from the public Hitomi gallery
/// metadata / gg.js URL scheme described in lanyeeee/hitomi-downloader (MIT).
/// No DRM or login bypass. No automatic offline downloading is provided here.
class HitomiGallery implements GalleryPageSource {
  final String workId;
  final String title;
  final List<Uri> pageUrls;
  final http.Client _client;

  HitomiGallery({
    required this.workId,
    required this.title,
    required this.pageUrls,
    required http.Client client,
  }) : _client = client;

  @override
  int get pageCount => pageUrls.length;

  @override
  String filename(int index) {
    if (index < 0 || index >= pageUrls.length) {
      throw RangeError.index(index, pageUrls);
    }
    final extension = pageUrls[index].pathSegments.last.split('.').last;
    return 'page_' + (index + 1).toString().padLeft(5, '0') + '.' + extension;
  }

  @override
  Future<Uint8List> loadPage(int index) {
    if (index < 0 || index >= pageUrls.length) {
      throw RangeError.index(index, pageUrls);
    }
    final url = pageUrls[index];
    if (!RegExp(r'^(?:w|a)?[0-9]+\.gold-usergeneratedcontent\.net$')
        .hasMatch(url.host)) {
      throw const FormatException('허용되지 않은 이미지 서버야.');
    }
    return BoundedWebImages.load(
      _client,
      url,
      maxBytes: GalleryArchive.maxSingleImageBytes,
      headers: const {'Referer': 'https://hitomi.la/'},
    );
  }
}

class HitomiGalleryProvider {
  final http.Client client;
  const HitomiGalleryProvider(this.client);

  static const _host = 'ltn.gold-usergeneratedcontent.net';
  static const _maxScriptBytes = 1024 * 1024;

  Future<HitomiGallery> load(String workId) async {
    if (!RegExp(r'^\d{1,12}$').hasMatch(workId)) {
      throw const FormatException('작품 번호는 숫자 1~12자리여야 해.');
    }

    final metadataText = await _readScript(
      Uri.https(_host, '/galleries/' + workId + '.js'),
    );
    final start = metadataText.indexOf('{');
    final end = metadataText.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException('작품 메타데이터 응답이 올바르지 않아.');
    }
    final decoded = jsonDecode(metadataText.substring(start, end + 1));
    if (decoded is! Map || decoded['id'].toString() != workId ||
        decoded['files'] is! List) {
      throw const FormatException('작품 번호 또는 이미지 목록이 일치하지 않아.');
    }

    final files = decoded['files'] as List;
    if (files.isEmpty || files.length > GalleryArchive.maxPages) {
      throw const FormatException('지원하지 않는 이미지 페이지 수야.');
    }
    final ggScript = await _readScript(Uri.https(_host, '/gg.js'));
    final gg = _HitomiGg.fromScript(ggScript);
    final urls = <Uri>[];
    for (final item in files) {
      if (item is! Map) {
        throw const FormatException('이미지 파일 정보가 올바르지 않아.');
      }
      urls.add(gg.urlFor(item));
    }
    return HitomiGallery(
      workId: workId,
      title: decoded['title'] is String ? decoded['title'] as String : '',
      pageUrls: List.unmodifiable(urls),
      client: client,
    );
  }

  Future<String> _readScript(Uri uri) async {
    if (uri.scheme != 'https' || uri.host != _host) {
      throw const FormatException('지원하지 않는 소스 서버야.');
    }
    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..headers['Accept'] = 'text/javascript,application/javascript,text/plain,*/*'
      ..headers['Referer'] = 'https://hitomi.la/';
    final response = await client.send(request)
        .timeout(const Duration(seconds: 18));
    if (response.statusCode != 200) {
      throw FormatException('작품 메타데이터 서버 응답 오류: HTTP ' +
          response.statusCode.toString());
    }
    if (response.contentLength != null &&
        response.contentLength! > _maxScriptBytes) {
      throw const FormatException('메타데이터가 너무 커.');
    }
    final bytes = BytesBuilder(copy: false);
    var read = 0;
    await for (final chunk in response.stream.timeout(const Duration(seconds: 25))) {
      read += chunk.length;
      if (read > _maxScriptBytes) {
        throw const FormatException('메타데이터가 허용 크기를 초과했어.');
      }
      bytes.add(chunk);
    }
    return utf8.decode(bytes.takeBytes());
  }
}

/// Hitomi's public image host layout depends on a mapping in gg.js.
/// It can change; failures must be reported, not silently skipped.
class _HitomiGg {
  final int defaultOffset;
  final Map<int, int> offsets;
  final String pathPrefix;

  const _HitomiGg(this.defaultOffset, this.offsets, this.pathPrefix);

  factory _HitomiGg.fromScript(String script) {
    final fallback = RegExp(r'var\s+o\s*=\s*(\d+)').firstMatch(script);
    final override = RegExp(r'o\s*=\s*(\d+)\s*;\s*break\s*;')
        .firstMatch(script);
    final b = RegExp(r"b:\s*'([^']*)'").firstMatch(script);
    if (fallback == null || b == null ||
        (override == null && RegExp(r'case\s+\d+\s*:').hasMatch(script))) {
      throw const FormatException('이미지 서버 주소 설정 형식이 바뀌었어.');
    }
    final offset = int.parse(fallback.group(1)!);
    final overrideOffset = override == null ? offset : int.parse(override.group(1)!);
    if (offset > 100 || overrideOffset > 100) {
      throw const FormatException('이미지 서버 번호가 올바르지 않아.');
    }
    final map = <int, int>{};
    for (final caseMatch in RegExp(r'case\s+(\d+)\s*:').allMatches(script)) {
      map[int.parse(caseMatch.group(1)!)] = overrideOffset;
    }
    final prefix = b.group(1)!;
    if (!RegExp(r'^[a-zA-Z0-9/_-]{0,60}$').hasMatch(prefix)) {
      throw const FormatException('이미지 경로 정보가 올바르지 않아.');
    }
    return _HitomiGg(offset, map, prefix);
  }

  Uri urlFor(Map file) {
    final hash = file['hash']?.toString().toLowerCase() ?? '';
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      throw const FormatException('이미지 해시 정보가 잘못됐어.');
    }
    final last = hash.substring(hash.length - 3);
    final group = int.parse(last.substring(2) + last.substring(0, 2), radix: 16);
    final subdomain = 1 + (offsets[group] ?? defaultOffset);
    final basePath = pathPrefix + group.toString() + '/' + hash;

    final originalName = file['name']?.toString().toLowerCase() ?? '';
    final originalExt = originalName.split('.').last;
    final hasWebp = file['haswebp'] == 1 || file['haswebp'] == '1';
    final hasAvif = file['hasavif'] == 1 || file['hasavif'] == '1';
    String dir;
    String ext;
    String hostPrefix;
    if (hasWebp) {
      dir = '/webp/';
      ext = 'webp';
      hostPrefix = 'w';
    } else if (const {'jpg', 'jpeg', 'png', 'gif', 'webp'}.contains(originalExt)) {
      dir = '/';
      ext = originalExt;
      hostPrefix = '';
    } else if (hasAvif) {
      dir = '/avif/';
      ext = 'avif';
      hostPrefix = 'a';
    } else {
      throw const FormatException('지원하지 않는 이미지 형식이야.');
    }
    return Uri.https(hostPrefix + subdomain.toString() +
        '.gold-usergeneratedcontent.net', dir + basePath + '.' + ext);
  }
}
