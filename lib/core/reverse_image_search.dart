import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import 'source_links.dart';

/// External source evidence, not proof of a gallery work ID.
class RemoteImageHit {
  final String provider, title, author, sourceUrl, thumbnailUrl, workId;
  final double? similarity;
  const RemoteImageHit({required this.provider, required this.title,
    required this.author, required this.sourceUrl,
    this.thumbnailUrl = '', this.workId = '', this.similarity});
}

class RemoteImageResponse {
  final List<RemoteImageHit> hits;
  final List<String> warnings;
  const RemoteImageResponse({this.hits = const [], this.warnings = const []});
}

/// Uploads a selected image ONLY after a user-initiated search.
/// ascii2d is keyless and may reject automated requests; SauceNAO uses an
/// optional user-provided API key. No searches run in the background.
class ReverseImageSearch {
  final http.Client client;
  const ReverseImageSearch(this.client);
  static const maxBytes = 6 * 1024 * 1024;
  static const _maxResponseBytes = 2 * 1024 * 1024;
  static final Uri _ascii = Uri.parse('https://ascii2d.net/');
  static final Uri _sauce = Uri.parse('https://saucenao.com/search.php');

  static bool safePublicUrl(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.hasPort || raw.length > 2048) return false;
    final host = uri.host.toLowerCase();
    if (host == 'localhost' || host.endsWith('.localhost') ||
        host.endsWith('.local') || host.endsWith('.internal') ||
        RegExp(r'^[0-9.]+$').hasMatch(host) || host.contains(':')) {
      return false;
    }
    return true;
  }

  static String galleryNumber(String url) {
    if (!safePublicUrl(url)) return '';
    final link = SourceLink.parse(url);
    if (link == null || link.kind != SourceKind.hitomiWork) return '';
    return RegExp(r'^\d{6,9}$').hasMatch(link.workId) ? link.workId : '';
  }

  static String _trim(dynamic value, {int max = 200}) {
    if (value is! String) return '';
    final text = value.trim();
    return text.length <= max ? text : text.substring(0, max);
  }

  static List<RemoteImageHit> parseSauceNao(String body) {
    final data = jsonDecode(body);
    if (data is! Map) throw const FormatException('Invalid SauceNAO response');
    final status = (data['header'] is Map)
        ? (data['header'] as Map)['status'] : null;
    if (status is num && status < 0) {
      throw FormatException('SauceNAO status: ' + status.toString());
    }
    if (data['results'] is! List) return [];
    final results = <RemoteImageHit>[];
    final seen = <String>{};
    for (final result in (data['results'] as List).take(24)) {
      if (result is! Map || result['header'] is! Map ||
          result['data'] is! Map) continue;
      final header = result['header'] as Map, item = result['data'] as Map;
      final score = double.tryParse(header['similarity'].toString());
      if (score == null || !score.isFinite || score < 35 || score > 100) {
        continue;
      }
      final urls = <String>[
        if (item['ext_urls'] is List)
          ...(item['ext_urls'] as List).whereType<String>(),
        if (item['source'] is String) item['source'] as String,
      ];
      final url = urls.where(safePublicUrl).firstOrNull ?? '';
      if (url.isEmpty || !seen.add(url)) continue;
      final thumbnail = _trim(header['thumbnail'], max: 2048);
      final title = _trim(item['title']).isNotEmpty
          ? _trim(item['title']) : _trim(item['material']);
      final author = [
        _trim(item['author_name']), _trim(item['member_name']),
        _trim(item['creator']),
      ].firstWhere((value) => value.isNotEmpty, orElse: () => '');
      results.add(RemoteImageHit(provider: 'SauceNAO', title: title,
        author: author, sourceUrl: url,
        thumbnailUrl: safePublicUrl(thumbnail) ? thumbnail : '',
        similarity: score, workId: galleryNumber(url)));
    }
    return results.take(12).toList();
  }

  /// Parses visible/public source links, without treating a Pixiv ID as Hitomi.
  static List<RemoteImageHit> parseAscii2d(String html) {
    final doc = html_parser.parse(html);
    final hits = <RemoteImageHit>[], seen = <String>{};
    for (final card in doc.querySelectorAll('.item-box').take(24)) {
      final details = card.querySelector('.detail-box') ?? card;
      Uri? source;
      for (final link in details.querySelectorAll('a[href]')) {
        final url = _ascii.resolve(link.attributes['href'] ?? '');
        if (safePublicUrl(url.toString()) && url.host != _ascii.host) {
          source = url;
          break;
        }
      }
      if (source == null || !seen.add(source.toString())) continue;
      final title = _trim((details.querySelector('h6') ??
          details.querySelector('h5'))?.text);
      final author = _trim(details.querySelector('small')?.text);
      final image = card.querySelector('.image-box img') ??
          card.querySelector('img');
      final thumb = _ascii.resolve(image?.attributes['data-src'] ??
          image?.attributes['src'] ?? '');
      hits.add(RemoteImageHit(provider: 'ascii2d', title: title,
        author: author, sourceUrl: source.toString(),
        thumbnailUrl: safePublicUrl(thumb.toString()) ?
            thumb.toString() : '', workId: galleryNumber(source.toString())));
    }
    return hits.take(12).toList();
  }

  Future<RemoteImageResponse> search(Uint8List image,
      {String sauceNaoKey = ''}) async {
    if (image.isEmpty || image.length > maxBytes) {
      return const RemoteImageResponse(warnings: [
        '이미지 크기는 최대 6MB야. 줄이거나 PNG/JPEG로 다시 선택해줘.',
      ]);
    }
    final results = <RemoteImageHit>[], warnings = <String>[];
    if (sauceNaoKey.trim().isNotEmpty) {
      try {
        results.addAll(await _sauceSearch(image, sauceNaoKey.trim()));
      } catch (error) { warnings.add('SauceNAO: ' + error.toString()); }
    }
    try {
      results.addAll(await _asciiSearch(image));
    } catch (error) { warnings.add('ascii2d: ' + error.toString()); }
    final dedup = <String, RemoteImageHit>{};
    for (final result in results) {
      if (!dedup.containsKey(result.sourceUrl) ||
          (result.similarity ?? 0) >
          (dedup[result.sourceUrl]!.similarity ?? 0)) {
        dedup[result.sourceUrl] = result;
      }
    }
    final hits = dedup.values.toList()
      ..sort((a, b) => (b.similarity ?? -1).compareTo(a.similarity ?? -1));
    return RemoteImageResponse(hits: hits.take(16).toList(),
        warnings: warnings);
  }

  Future<List<RemoteImageHit>> _sauceSearch(
      Uint8List image, String apiKey) async {
    final req = http.MultipartRequest('POST', _sauce)
      ..followRedirects = false
      ..fields.addAll({'api_key': apiKey, 'output_type': '2',
        'numres': '10', 'db': '999'})
      ..files.add(http.MultipartFile.fromBytes('file', image,
          filename: _filename(image)));
    final response = await client.send(req)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 429) {
      throw const FormatException('API quota exceeded (429)');
    }
    if (response.statusCode != 200) {
      throw FormatException('HTTP ' + response.statusCode.toString());
    }
    return parseSauceNao(await _boundedResponse(response));
  }

  Future<List<RemoteImageHit>> _asciiSearch(Uint8List image) async {
    final landing = await client.get(_ascii, headers: const {
      'User-Agent': 'HYPViewer/0.4.6', 'Accept': 'text/html',
    }).timeout(const Duration(seconds: 15));
    if (landing.statusCode != 200 ||
        landing.bodyBytes.length > _maxResponseBytes) {
      throw FormatException('entry page HTTP ' + landing.statusCode.toString());
    }
    final doc = html_parser.parse(utf8.decode(
        landing.bodyBytes, allowMalformed: true));
    final form = doc.querySelector('form[action="/search/file"]') ??
        doc.querySelector('form#file_upload');
    final csrf = form?.querySelector('input[name="authenticity_token"]')
        ?.attributes['value'] ?? '';
    if (csrf.isEmpty) {
      throw const FormatException('public search form unavailable');
    }
    final cookies = (landing.headers['set-cookie'] ?? '').split(
        RegExp(r',(?=[^;=,\s]+=)')).map((c) => c.split(';').first.trim())
        .where((c) => c.contains('=')).join('; ');
    final req = http.MultipartRequest(
        'POST', _ascii.resolve('/search/file'))
      ..followRedirects = false
      ..fields.addAll({'utf8': '✓', 'authenticity_token': csrf})
      ..files.add(http.MultipartFile.fromBytes('file', image,
          filename: _filename(image)));
    req.headers.addAll({'User-Agent': 'HYPViewer/0.4.6',
      'Referer': _ascii.toString(), 'Origin': 'https://ascii2d.net',
      if (cookies.isNotEmpty) 'Cookie': cookies});
    final posted = await client.send(req)
        .timeout(const Duration(seconds: 20));
    String body;
    if (posted.statusCode == 302 || posted.statusCode == 303) {
      final resultUrl = _ascii.resolve(posted.headers['location'] ?? '');
      if (resultUrl.scheme != 'https' || resultUrl.host != _ascii.host ||
          !resultUrl.path.startsWith('/search/')) {
        throw const FormatException('unsafe search redirect');
      }
      final result = await client.get(resultUrl, headers: {
        'User-Agent': 'HYPViewer/0.4.6',
        if (cookies.isNotEmpty) 'Cookie': cookies,
      }).timeout(const Duration(seconds: 15));
      if (result.statusCode != 200 ||
          result.bodyBytes.length > _maxResponseBytes) {
        throw FormatException('results HTTP ' + result.statusCode.toString());
      }
      body = utf8.decode(result.bodyBytes, allowMalformed: true);
    } else if (posted.statusCode == 200) {
      body = await _boundedResponse(posted);
    } else {
      throw FormatException('upload HTTP ' + posted.statusCode.toString());
    }
    if (!body.contains('item-box') && !body.contains('search/color') &&
        !body.contains('search/bovw')) {
      throw const FormatException('public results unavailable');
    }
    return parseAscii2d(body);
  }

  static String _filename(Uint8List data) =>
    data.length > 3 && data[0] == 0x89 && data[1] == 0x50
      ? 'image.png' : data.length > 2 && data[0] == 0xff &&
        data[1] == 0xd8 ? 'image.jpg' : 'image.webp';

  static Future<String> _boundedResponse(http.StreamedResponse r) async {
    if (r.contentLength != null && r.contentLength! > _maxResponseBytes) {
      throw const FormatException('response too large');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in r.stream.timeout(const Duration(seconds: 16))) {
      if (builder.length + chunk.length > _maxResponseBytes) {
        throw const FormatException('response too large');
      }
      builder.add(chunk);
    }
    return utf8.decode(builder.takeBytes(), allowMalformed: true);
  }
}
