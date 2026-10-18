import 'dart:convert';
import 'dart:typed_data';

import 'online_reader_failure.dart';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'gallery.dart';
import 'online_gallery.dart';

/// In-app reader for public galleries.
/// Current full-size images use WebP on w1/w2 hosts. Legacy numeric-host
/// JPEG fallbacks (e.g. 2.gold-usergeneratedcontent.net) are not used:
/// they can fail DNS lookup even when the gallery metadata loads.
class HitomiGallery implements GalleryPageSource {
  final String workId;
  final String title;
  final List<Uri> pageUrls;
  final List<Uri> thumbnailUrls;
  final bool dataSaver;
  final http.Client _client;

  HitomiGallery({
    required this.workId,
    required this.title,
    required this.pageUrls,
    this.thumbnailUrls = const [],
    this.dataSaver = false,
    required http.Client client,
  }) : _client = client;

  @override
  int get pageCount => pageUrls.length;

  @override
  String filename(int index) {
    if (index < 0 || index >= pageUrls.length) {
      throw RangeError.index(index, pageUrls);
    }
    return 'page_${(index + 1).toString().padLeft(5, '0')}.webp';
  }

  @override
  Future<Uint8List> loadPage(int index) async {
    if (index < 0 || index >= pageUrls.length) {
      throw RangeError.index(index, pageUrls);
    }
    final original = pageUrls[index];
    if (dataSaver && index < thumbnailUrls.length) {
      try {
        return await _loadAllowed(thumbnailUrls[index], page: index + 1);
      } catch (_) {
        // A missing/blocked thumbnail never makes the book unreadable.
        // Retry the actual image with the same bounded request policy.
      }
    }
    return _loadAllowed(original, page: index + 1);
  }

  Future<Uint8List> _loadAllowed(Uri url, {required int page}) async {
    final origin = RegExp(r'^w[12]\.gold-usergeneratedcontent\.net$')
        .hasMatch(url.host);
    final thumbnail = RegExp(r'^[ab]tn\.gold-usergeneratedcontent\.net$')
        .hasMatch(url.host);
    if (url.scheme != 'https' || !(origin || thumbnail)) {
      throw OnlineReaderFailure(code: 'IMAGE_HOST_BLOCKED',
        stage: OnlineReaderStage.image, workId: workId, page: page,
        description: '허용되지 않은 웹 이미지 서버야.');
    }
    try {
      return await BoundedWebImages.load(_client, url,
        maxBytes: GalleryArchive.maxSingleImageBytes,
        headers: const {'Referer': 'https://hitomi.la/'});
    } catch (error) {
      throw OnlineReaderFailure.classify(error,
        workId: workId, stage: OnlineReaderStage.image,
        host: url.host, page: page);
    }
  }

}

/// Metadata supplied by the gallery's existing .js response. View counts
/// are deliberately not invented: the galleryinfo JSON has no verified
/// official per-gallery viewCount field in the current integration.
class GalleryInfo {
  final String workId;
  final String title;
  final List<String> titleAliases;
  final String author;
  final String group;
  final String series;
  final String language;
  final String type;
  final String date;
  final List<String> tags;
  final List<String> characters;
  final int pageCount;
  final int? views;

  const GalleryInfo({
    required this.workId,
    required this.title,
    this.titleAliases = const [],
    this.author = '',
    this.group = '',
    this.series = '',
    this.language = '',
    this.type = '',
    this.date = '',
    this.tags = const [],
    this.characters = const [],
    this.pageCount = 0,
    this.views,
  });

  static List<String> _names(Object? data) {
    if (data is! List) return const [];
    return data.take(150).map((item) {
      if (item is String) return item.trim();
      if (item is Map) {
        final name = item['tag'] ?? item['artist'] ?? item['group'] ??
            item['parody'] ?? item['character'] ?? item['name'] ?? '';
        final text = name.toString().trim();
        final prefix = item['female'] == true ? 'female:' :
            item['male'] == true ? 'male:' : '';
        return prefix + text;
      }
      return '';
    }).where((name) => name.isNotEmpty).toSet().toList();
  }

  factory GalleryInfo.parse(String code, Map<dynamic, dynamic> raw) {
    if (raw['id'].toString() != code) {
      throw const FormatException('작품 번호가 메타데이터와 일치하지 않아.');
    }
    String scalar(String key) =>
        raw[key] is String ? (raw[key] as String).trim() : '';
    final aliases = <String>{};
    for (final name in [
      'original_title', 'title_english', 'title_japanese',
      'title_korean', 'title_romanized',
    ]) {
      if (scalar(name).isNotEmpty) aliases.add(scalar(name));
    }
    for (final field in ['aliases', 'titles', 'alternative_titles']) {
      final value = raw[field];
      if (value is List) {
        aliases.addAll(value.whereType<String>().take(20));
      } else if (value is Map) {
        aliases.addAll(value.values.whereType<String>().take(20));
      }
    }
    aliases.removeWhere((alias) => alias.length < 2 || alias.length > 180);
    return GalleryInfo(
      workId: code,
      title: scalar('title'),
      titleAliases: aliases.take(24).toList(),
      author: _names(raw['artists']).join(', '),
      group: _names(raw['groups']).join(', '),
      series: _names(raw['parodys']).join(', '),
      language: scalar('language'),
      type: scalar('type'),
      date: scalar('date'),
      tags: _names(raw['tags']),
      characters: _names(raw['characters']),
      pageCount: raw['files'] is List ? (raw['files'] as List).length : 0,
    );
  }
}

class HitomiGalleryProvider {
  final http.Client client;
  const HitomiGalleryProvider(this.client);

  static const _host = 'ltn.gold-usergeneratedcontent.net';
  static const _maxScriptBytes = 1024 * 1024;

  /// Shared, verified metadata reader for title, work info and reader.
  /// One cache-bypass request is allowed on ID mismatches only. Returning
  /// another gallery's images as though they belonged to this ID is forbidden.
  Future<Map<dynamic, dynamic>> _verifiedGalleryInfo(String workId) async {
    if (!RegExp(r'^\d{1,12}$').hasMatch(workId)) {
      throw const FormatException('작품 번호는 숫자 1~12자리여야 해.');
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      final noCache = attempt == 1;
      final uri = Uri.https(_host, '/galleries/$workId.js',
        noCache ? {'_hyp_retry': DateTime.now()
            .microsecondsSinceEpoch.toString()} : null);
      final raw = await _readScript(uri, workId: workId, noCache: noCache);
      final match = RegExp(r'\bgalleryinfo\s*=').firstMatch(raw);
      // Some mirrors return a bare JSON object instead of JS assignment.
      // Never parse an unrelated script object.
      final start = match != null ? raw.indexOf('{', match.end)
          : raw.trimLeft().startsWith('{') ? raw.indexOf('{') : -1;
      final end = raw.lastIndexOf('}');
      if (start < 0 || end <= start) {
        throw OnlineReaderFailure(code: 'META_RESPONSE_INVALID',
          stage: OnlineReaderStage.metadata, workId: workId,
          httpStatus: 200, host: _host,
          description: '메타데이터에 galleryinfo JSON 객체가 없어.');
      }
      Object? decoded;
      try {
        decoded = jsonDecode(raw.substring(start, end + 1));
      } on FormatException {
        throw OnlineReaderFailure(code: 'META_JSON_INVALID',
          stage: OnlineReaderStage.metadata, workId: workId,
          httpStatus: 200, host: _host,
          description: '메타데이터 JSON 해석에 실패했어.');
      }
      if (decoded is! Map) {
        throw OnlineReaderFailure(code: 'META_RESPONSE_INVALID',
          stage: OnlineReaderStage.metadata, workId: workId,
          actualType: OnlineReaderFailure.jsonType(decoded),
          httpStatus: 200, host: _host,
          description: '메타데이터가 JSON 객체가 아니야.');
      }
      if (!decoded.containsKey('id') || decoded['id'] == null) {
        throw OnlineReaderFailure(code: 'META_ID_MISSING',
          stage: OnlineReaderStage.metadata, workId: workId,
          httpStatus: 200, host: _host,
          description: '메타데이터에 작품 번호가 없어.');
      }
      final rawId = decoded['id'];
      final reported = rawId is num && rawId.isFinite &&
          rawId == rawId.toInt()
          ? rawId.toInt().toString()
          : rawId is String ? rawId.trim() : '';
      if (reported != workId) {
        if (attempt == 0) continue;
        throw OnlineReaderFailure(code: 'META_ID_MISMATCH',
          stage: OnlineReaderStage.metadata, workId: workId,
          returnedWorkId: RegExp(r'^\d{1,12}$').hasMatch(reported)
              ? reported : null,
          actualType: OnlineReaderFailure.jsonType(rawId),
          retried: true, httpStatus: 200, host: _host,
          description: '재요청 후에도 서버에서 다른 작품 번호를 반환했어.');
      }
      return decoded;
    }
    throw StateError('Unreachable gallery metadata state');
  }

  /// Fetching a title does not download images or gg.js.
  Future<String> fetchTitle(String workId) async {
    final decoded = await _verifiedGalleryInfo(workId);
    return decoded['title'] is String
        ? (decoded['title'] as String).trim() : '';
  }

  Future<GalleryInfo> fetchInfo(String workId) async {
    final decoded = await _verifiedGalleryInfo(workId);
    return GalleryInfo.parse(workId, decoded);
  }

  Future<HitomiGallery> load(String workId, {bool dataSaver = false}) async {
    if (!RegExp(r'^\d{1,12}$').hasMatch(workId)) {
      throw const FormatException('작품 번호는 숫자 1~12자리여야 해.');
    }

    final decoded = await _verifiedGalleryInfo(workId);
    if (!decoded.containsKey('files')) {
      throw OnlineReaderFailure(code: 'META_FILES_MISSING',
        stage: OnlineReaderStage.metadata, workId: workId,
        httpStatus: 200, host: _host,
        description: '메타데이터에 이미지 목록(files)이 없어.');
    }
    if (decoded['files'] is! List) {
      throw OnlineReaderFailure(code: 'META_FILES_TYPE',
        stage: OnlineReaderStage.metadata, workId: workId,
        httpStatus: 200, host: _host,
        actualType: OnlineReaderFailure.jsonType(decoded['files']),
        description: '이미지 목록(files)이 배열이 아니야.');
    }
    final files = decoded['files'] as List;
    if (files.isEmpty) {
      throw OnlineReaderFailure(code: 'META_FILES_EMPTY',
        stage: OnlineReaderStage.metadata, workId: workId,
        httpStatus: 200, host: _host,
        description: '이미지 목록(files)이 비어 있어.');
    }
    if (files.length > GalleryArchive.maxPages) {
      throw OnlineReaderFailure(code: 'META_PAGE_LIMIT',
        stage: OnlineReaderStage.metadata, workId: workId,
        httpStatus: 200, host: _host,
        description: '지원하는 최대 페이지 수를 초과했어.');
    }
    final ggScript = await _readScript(Uri.https(_host, '/gg.js'),
      workId: workId, stage: OnlineReaderStage.routing);
    late final _HitomiGg gg;
    try {
      gg = _HitomiGg.fromScript(ggScript);
    } on FormatException catch (error) {
      throw OnlineReaderFailure.classify(error,
        workId: workId, stage: OnlineReaderStage.routing, host: _host);
    }
    final urls = <Uri>[];
    final thumbnails = <Uri>[];
    for (var index = 0; index < files.length; index++) {
      final item = files[index];
      if (item is! Map) {
        throw OnlineReaderFailure(code: 'META_IMAGE_ENTRY_INVALID',
          stage: OnlineReaderStage.metadata, workId: workId,
          httpStatus: 200, host: _host, page: index + 1,
          actualType: OnlineReaderFailure.jsonType(item),
          description: '이미지 파일 정보 형식이 올바르지 않아.');
      }
      try {
        urls.add(gg.urlFor(item));
        thumbnails.add(gg.thumbnailFor(item));
      } on FormatException {
        throw OnlineReaderFailure(code: 'ROUTING_HASH_INVALID',
          stage: OnlineReaderStage.routing, workId: workId,
          host: _host, page: index + 1,
          description: '이미지 파일의 해시 정보가 잘못됐어.');
      }
    }
    return HitomiGallery(
      workId: workId,
      title: decoded['title'] is String ? decoded['title'] as String : '',
      pageUrls: List.unmodifiable(urls),
      thumbnailUrls: List.unmodifiable(thumbnails),
      dataSaver: dataSaver,
      client: client,
    );
  }

  Future<String> _readScript(Uri uri, {
    String workId = '',
    OnlineReaderStage stage = OnlineReaderStage.metadata,
    bool noCache = false,
  }) async {
    if (uri.scheme != 'https' || uri.host != _host) {
      throw const FormatException('지원하지 않는 소스 서버야.');
    }
    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..headers['Accept'] = 'text/javascript,application/javascript,text/plain,*/*'
      ..headers['Referer'] = 'https://hitomi.la/';
    if (noCache) {
      request.headers['Cache-Control'] = 'no-cache, no-store';
      request.headers['Pragma'] = 'no-cache';
    }
    late final http.StreamedResponse response;
    try {
      response = await client.send(request)
          .timeout(const Duration(seconds: 18));
    } catch (error) {
      throw OnlineReaderFailure.classify(error,
        workId: workId, stage: stage, host: uri.host);
    }
    if (response.statusCode != 200) {
      throw OnlineReaderFailure(
        code: stage == OnlineReaderStage.routing
            ? 'ROUTING_HTTP_ERROR' : 'META_HTTP_ERROR',
        stage: stage, workId: workId, host: uri.host,
        httpStatus: response.statusCode,
        description: '메타데이터 서버가 오류 응답을 반환했어.');

    }
    if (response.contentLength != null &&
        response.contentLength! > _maxScriptBytes) {
      throw OnlineReaderFailure(code: 'META_SIZE_LIMIT',
        stage: stage, workId: workId, host: uri.host, httpStatus: 200,
        description: '메타데이터 크기가 제한을 초과했어.');
    }
    final bytes = BytesBuilder(copy: false);
    var read = 0;
    try {
      await for (final chunk in response.stream.timeout(
          const Duration(seconds: 25))) {
        read += chunk.length;
        if (read > _maxScriptBytes) {
          throw OnlineReaderFailure(code: 'META_SIZE_LIMIT',
            stage: stage, workId: workId, host: uri.host, httpStatus: 200,
            description: '메타데이터가 허용 크기를 초과했어.');
        }
        bytes.add(chunk);
      }
    } catch (error) {
      throw OnlineReaderFailure.classify(error,
        workId: workId, stage: stage, host: uri.host);
    }
    try {
      return utf8.decode(bytes.takeBytes());
    } on FormatException {
      throw OnlineReaderFailure(code: 'META_RESPONSE_INVALID',
        stage: stage, workId: workId, host: uri.host, httpStatus: 200,
        description: '메타데이터의 문자 인코딩이 올바르지 않아.');
    }
  }
}

/// Parses the current public gg.js routing information.
/// Host suffixes are limited to w1/w2, as in the current public WebP client;
/// do not generate numeric legacy JPEG image domains from an original filename.
class _HitomiGg {
  final int defaultOffset;
  final Map<int, int> offsets;
  final String pathPrefix;

  const _HitomiGg(this.defaultOffset, this.offsets, this.pathPrefix);

  factory _HitomiGg.fromScript(String script) {
    final fallback = RegExp(r'var\s+o\s*=\s*(\d+)').firstMatch(script);
    final override = RegExp(r'o\s*=\s*(\d+)\s*;\s*break\s*;')
        .firstMatch(script);
    final cases = RegExp(r'case\s+(\d+)\s*:').allMatches(script).toList();
    final b = RegExp(r"b:\s*'([^']*)'").firstMatch(script);
    if (fallback == null || b == null ||
        (override == null && cases.isNotEmpty)) {
      throw const FormatException('이미지 서버 라우팅 형식이 변경됐어.');
    }
    final defaultOffset = int.parse(fallback.group(1)!);
    final overrideOffset = override == null
        ? defaultOffset : int.parse(override.group(1)!);
    if (defaultOffset < 0 || defaultOffset > 1 ||
        overrideOffset < 0 || overrideOffset > 1) {
      throw const FormatException(
          '이미지 서버 선택 값이 범위를 벗어났어. 최신 gg.js 형식을 확인해 줘.');
    }
    final map = <int, int>{};
    for (final caseMatch in cases) {
      final hashCode = int.parse(caseMatch.group(1)!);
      if (hashCode < 0 || hashCode > 4095) {
        throw const FormatException('이미지 해시 라우팅 값이 유효하지 않아.');
      }
      map[hashCode] = overrideOffset;
    }
    final prefix = b.group(1)!;
    if (!RegExp(r'^[a-zA-Z0-9/_-]{1,60}$').hasMatch(prefix)) {
      throw const FormatException('이미지 경로 정보가 올바르지 않아.');
    }
    return _HitomiGg(defaultOffset, map, prefix);
  }

  /// Compact WebP thumbnails from the site's dedicated thumbnail servers.
  /// The hash-based layout is independent of the original image dimensions.
  Uri thumbnailFor(Map file) {
    final hash = file['hash']?.toString().toLowerCase() ?? '';
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      throw const FormatException('이미지 해시 정보가 잘못됐어.');
    }
    final last = hash.substring(hash.length - 3);
    final group = int.parse(last.substring(2) + last.substring(0, 2),
        radix: 16);
    final which = String.fromCharCode(97 + (offsets[group] ?? defaultOffset));
    return Uri.https('${which}tn.gold-usergeneratedcontent.net',
        '/webpsmalltn/${last[2]}/${last.substring(0, 2)}/$hash.webp');
  }

  Uri urlFor(Map file) {
    final hash = file['hash']?.toString().toLowerCase() ?? '';
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      throw const FormatException('이미지 해시 정보가 잘못됐어.');
    }
    final last = hash.substring(hash.length - 3);
    final group = int.parse(last.substring(2) + last.substring(0, 2), radix: 16);
    final hostSuffix = 1 + (offsets[group] ?? defaultOffset);
    // WebP is supplied by the current public gallery image servers even for
    // entries lacking an old 'haswebp' flag.
    return Uri.https(
      'w$hostSuffix.gold-usergeneratedcontent.net',
      '/$pathPrefix$group/$hash.webp',
    );
  }
}
