import 'dart:convert';

import 'package:http/http.dart' as http;

import 'youtube.dart';

/// Best-effort anonymous reader of public YouTube watch-page comments.
/// Uses public page configuration and continuations, not YouTube Data API v3
/// or a user-supplied developer API key. YouTube may change or block this.
class YoutubePublicClient {
  static const int _maxComments = 300;
  static const int _maxPages = 10;
  final http.Client client;
  const YoutubePublicClient(this.client);

  static const _browserHeaders = <String, String>{
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept-Language': 'en-US,en;q=0.9',
    'Accept': 'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8',
  };

  Future<YoutubeResults> fetch(String id) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id)) {
      throw const FormatException('유튜브 영상 ID가 잘못됐어.');
    }
    final watch = Uri.https('www.youtube.com', '/watch', {'v': id});
    final response = await client.get(watch, headers: _browserHeaders)
        .timeout(const Duration(seconds: 18));
    if (response.statusCode != 200 || response.bodyBytes.length > 6 * 1024 * 1024) {
      throw FormatException('유튜브 공개 페이지를 가져오지 못했어 (HTTP ' +
          response.statusCode.toString() + ').');
    }
    final html = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (html.contains('Sign in to confirm you') ||
        html.contains('Before you continue to YouTube')) {
      throw const FormatException('유튜브에서 로그인 또는 동의 확인을 요구해. '
          '현재는 공개 댓글을 직접 가져올 수 없어.');
    }

    final player = _jsonAfter(html, 'ytInitialPlayerResponse');
    final initialData = _jsonAfter(html, 'ytInitialData');
    final video = _map(player?['videoDetails']);
    final status = _map(player?['playabilityStatus'])?['status'];
    if (status != null && status != 'OK') {
      throw const FormatException('로그인/연령 제한 또는 재생 제한으로 댓글을 볼 수 없어.');
    }
    final title = video?['title'] is String ? video!['title'] as String : '';
    final description = video?['shortDescription'] is String
        ? video!['shortDescription'] as String : '';

    // The browser embeds its own public web-client key and request context.
    // No developer API key is bundled or requested from our users.
    final key = RegExp(r'"INNERTUBE_API_KEY"\s*:\s*"([^"]+)"')
        .firstMatch(html)?.group(1);
    final context = _jsonProperty(html, 'INNERTUBE_CONTEXT') ??
        _fallbackContext(html);
    if (key == null || key.isEmpty || context == null) {
      // The metadata was publicly embedded, but the comments transport is
      // unavailable. Keep these publicly accessible work IDs and clearly
      // indicate partial coverage; never assume comments were collected.
      if (title.isNotEmpty || description.isNotEmpty) {
        return YoutubeResults(title, description, const [],
            mayBeIncomplete: true);
      }
      throw const FormatException('유튜브 공개 페이지 형식이 변경됐어. '
          '앱에서 댓글을 읽을 수 없어.');
    }

    final comments = <String>[];
    final seen = <String>{};
    String? token = _commentToken(initialData);
    Map<String, dynamic>? batch;

    if (token == null) {
      // Some watch pages only supply a comment token through the first next
      // request made with videoId.
      try {
        batch = await _next(key, context, videoId: id);
        _appendComments(batch, comments, seen);
        token = _commentToken(batch);
      } catch (_) {
        if (description.isEmpty) rethrow;
        return YoutubeResults(title, description, comments,
            mayBeIncomplete: true);
      }
    }

    final visited = <String>{};
    var interrupted = false;
    for (var attempt = 0; attempt < _maxPages && comments.length < _maxComments; attempt++) {
      if (token == null || token.isEmpty || !visited.add(token)) break;
      try {
        batch = await _next(key, context, continuation: token);
        _appendComments(batch, comments, seen);
        token = _commentToken(batch);
      } catch (_) {
        // Do not discard already accessible public comments when another
        // continuation page is unavailable. Report incompleteness instead.
        if (comments.isEmpty && description.isEmpty) rethrow;
        interrupted = true;
        break;
      }
    }

    if (comments.isEmpty && description.isEmpty) {
      throw const FormatException('공개 댓글을 가져오지 못했어. '
          '댓글이 비활성화됐거나 유튜브의 접근 제한/구조 변경일 수 있어. '
          '유튜브에서 댓글을 직접 복사해 입력해줘.');
    }
    return YoutubeResults(title, description, comments,
        mayBeIncomplete: interrupted ||
            (comments.isEmpty && description.isNotEmpty) ||
            (token != null && token.isNotEmpty && !visited.contains(token)) ||
            comments.length >= _maxComments);
  }

  Future<Map<String, dynamic>> _next(
    String key,
    Map<String, dynamic> context, {
    String? videoId,
    String? continuation,
  }) async {
    final body = <String, dynamic>{'context': context};
    if (videoId != null) body['videoId'] = videoId;
    if (continuation != null) body['continuation'] = continuation;
    final request = http.Request('POST',
        Uri.https('www.youtube.com', '/youtubei/v1/next',
            {'key': key, 'prettyPrint': 'false'}))
      ..followRedirects = false
      ..headers.addAll({
        ..._browserHeaders,
        'Content-Type': 'application/json',
        'Origin': 'https://www.youtube.com',
        'Referer': 'https://www.youtube.com/',
        'X-YouTube-Client-Name': '1',
      })
      ..body = jsonEncode(body);
    final response = await client.send(request)
        .timeout(const Duration(seconds: 18));
    if (response.statusCode != 200) {
      throw FormatException('유튜브 공개 댓글 요청 실패 (HTTP ' +
          response.statusCode.toString() + '). '
          '로그인 요구 또는 접속 제한일 수 있어.');
    }
    if (response.contentLength != null &&
        response.contentLength! > 5 * 1024 * 1024) {
      throw const FormatException('댓글 응답 크기 제한을 초과했어.');
    }
    final chunks = <int>[];
    await for (final chunk in response.stream.timeout(const Duration(seconds: 25))) {
      if (chunks.length + chunk.length > 5 * 1024 * 1024) {
        throw const FormatException('댓글 응답 크기 제한을 초과했어.');
      }
      chunks.addAll(chunk);
    }
    final parsed = jsonDecode(utf8.decode(chunks));
    if (parsed is! Map<String, dynamic>) {
      throw const FormatException('유튜브 댓글 응답 형식이 달라졌어.');
    }
    return parsed;
  }

  static Map<String, dynamic>? _map(dynamic value) =>
      value is Map<String, dynamic> ? value : null;

  static Map<String, dynamic>? _fallbackContext(String html) {
    final version = RegExp(r'"INNERTUBE_CONTEXT_CLIENT_VERSION"\s*:\s*"([^"]+)"')
        .firstMatch(html)?.group(1);
    if (version == null) return null;
    return {
      'client': {
        'clientName': 'WEB', 'clientVersion': version,
        'hl': 'en', 'gl': 'US',
      },
    };
  }

  static Map<String, dynamic>? _jsonAfter(String html, String marker) {
    var i = html.indexOf(marker);
    if (i < 0) return null;
    i = html.indexOf('{', i + marker.length);
    if (i < 0) return null;
    return _parseBalancedJson(html, i);
  }

  static Map<String, dynamic>? _jsonProperty(String html, String name) {
    final match = RegExp('"' + RegExp.escape(name) + r'"\s*:\s*\{')
        .firstMatch(html);
    if (match == null) return null;
    return _parseBalancedJson(html, match.end - 1);
  }

  static Map<String, dynamic>? _parseBalancedJson(String input, int start) {
    var depth = 0;
    var quoted = false;
    var escaped = false;
    for (var i = start; i < input.length; i++) {
      final c = input[i];
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (c == '\\') {
          escaped = true;
        } else if (c == '"') {
          quoted = false;
        }
      } else if (c == '"') {
        quoted = true;
      } else if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) {
          try {
            final decoded = jsonDecode(input.substring(start, i + 1));
            return _map(decoded);
          } on FormatException {
            return null;
          }
        }
      }
    }
    return null;
  }

  static String? _commentToken(Map<String, dynamic>? data) {
    if (data == null) return null;
    final content = _map(data['contents']);
    final watch = _map(content?['twoColumnWatchNextResults']);
    final results = _map(watch?['results']);
    final inner = _map(results?['results']);
    final items = inner?['contents'];
    if (items is List) {
      for (final item in items) {
        final section = _map(_map(item)?['itemSectionRenderer']);
        if (section == null) continue;
        final target = section['targetId'];
        if (target is String && !target.contains('comment')) continue;
        final token = _findTopLevelToken(section);
        if (token != null) return token;
      }
    }
    // Inspect top-level continuation items; skip reply continuation tokens.
    for (final root in [
      data['onResponseReceivedEndpoints'],
      data['onResponseReceivedActions'],
    ]) {
      if (root is! List) continue;
      for (final entry in root) {
        final obj = _map(entry);
        for (final key in ['appendContinuationItemsAction',
                           'reloadContinuationItemsCommand']) {
          final inner = _map(obj?[key]);
          final token = _findTopLevelToken(inner);
          if (token != null) return token;
        }
      }
    }
    return null;
  }

  static String? _findTopLevelToken(Map<String, dynamic>? group) {
    if (group == null) return null;
    final items = group['contents'] ?? group['continuationItems'];
    if (items is List) {
      for (final item in items) {
        final continuation = _map(_map(item)?['continuationItemRenderer']);
        final endpoint = _map(continuation?['continuationEndpoint']);
        final command = _map(endpoint?['continuationCommand']);
        final token = command?['token'];
        if (token is String && token.isNotEmpty) return token;
      }
    }
    final cont = group['continuations'];
    if (cont is List && cont.isNotEmpty) {
      final first = _map(cont.first);
      final token = _map(first?['nextContinuationData'])?['continuation'] ??
          _map(first?['reloadContinuationData'])?['continuation'];
      if (token is String && token.isNotEmpty) return token;
    }
    return null;
  }

  static void _appendComments(dynamic node, List<String> comments,
      Set<String> seen) {
    void add(dynamic text) {
      if (text is! String || text.trim().isEmpty ||
          comments.length >= _maxComments) return;
      if (seen.add(text.trim())) comments.add(text.trim());
    }
    void scan(dynamic value) {
      if (comments.length >= _maxComments) return;
      if (value is List) {
        for (final item in value) { scan(item); }
      } else if (value is Map) {
        final old = _map(value['commentRenderer']);
        if (old != null) {
          final content = _map(old['contentText']);
          if (content?['simpleText'] is String) {
            add(content!['simpleText']);
          } else if (content?['runs'] is List) {
            final parts = (content!['runs'] as List)
                .map((r) => _map(r)?['text'] ?? '').join();
            add(parts);
          }
        }
        final entity = _map(value['commentEntityPayload']);
        final properties = _map(entity?['properties']);
        add(_map(properties?['content'])?['content']);
        for (final entry in value.values) { scan(entry); }
      }
    }
    scan(node);
  }
}
