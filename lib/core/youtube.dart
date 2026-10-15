import 'dart:convert';
import 'package:http/http.dart' as http;

class ShortsLink {
  static String? videoId(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != 'https') return null;
    final host = uri.host.toLowerCase();
    if (!['youtube.com', 'www.youtube.com', 'm.youtube.com', 'youtu.be'].contains(host)) return null;
    String id = '';
    if (host == 'youtu.be') {
      id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    } else if (uri.pathSegments.length >= 2 && uri.pathSegments.first == 'shorts') {
      id = uri.pathSegments[1];
    } else {
      id = uri.queryParameters['v'] ?? '';
    }
    return RegExp(r'^[\w-]{11}$').hasMatch(id) ? id : null;
  }
}

class YoutubeResults {
  final String title;
  final String description;
  final List<String> comments;
  /// True if more public comment pages appear available but were not loaded.
  final bool mayBeIncomplete;
  const YoutubeResults(this.title, this.description, this.comments,
      {this.mayBeIncomplete = false});
}

class YoutubeClient {
  final http.Client client;
  YoutubeClient(this.client);

  Future<YoutubeResults> fetch(String id, String apiKey) async {
    final videoUri = Uri.https('www.googleapis.com', '/youtube/v3/videos', {
      'part': 'snippet', 'id': id, 'key': apiKey
    });
    final videoResponse = await client.get(videoUri).timeout(const Duration(seconds: 12));
    if (videoResponse.statusCode != 200) {
      throw Exception('YouTube 영상 정보 조회 실패 (HTTP ${videoResponse.statusCode}). API 키/할당량을 확인해줘.');
    }
    final videoData = jsonDecode(videoResponse.body) as Map<String, dynamic>;
    final items = videoData['items'] as List? ?? [];
    if (items.isEmpty) throw Exception('Video was not found');
    final metadata = items.first['snippet'] as Map<String, dynamic>;
    // YouTube Data API limits commentThreads to 100 items per page.
    // Retrieve up to five PUBLIC pages with the user's optional API key.
    // More pages or failed requests are reported as partial, never complete.
    final comments = <String>[];
    final seenBodies = <String>{};
    final seenTokens = <String>{};
    String? token;
    var interrupted = false;
    for (var page = 0; page < 5; page++) {
      final uri = Uri.https('www.googleapis.com',
          '/youtube/v3/commentThreads', {
        'part': 'snippet',
        'videoId': id,
        'maxResults': '100',
        'order': 'relevance',
        'textFormat': 'plainText',
        'key': apiKey,
        if (token != null) 'pageToken': token,
      });
      try {
        final response = await client.get(uri)
            .timeout(const Duration(seconds: 12));
        if (response.statusCode != 200) {
          interrupted = true;
          break;
        }
        final data = jsonDecode(response.body);
        if (data is! Map<String, dynamic> || data['items'] is! List) {
          interrupted = true;
          break;
        }
        for (final item in (data['items'] as List)) {
          if (item is! Map<String, dynamic>) continue;
          final snippet = item['snippet'];
          if (snippet is! Map<String, dynamic>) continue;
          final top = snippet['topLevelComment'];
          if (top is! Map<String, dynamic>) continue;
          final body = top['snippet'];
          if (body is! Map<String, dynamic>) continue;
          final text = body['textDisplay'];
          if (text is String && text.trim().isNotEmpty &&
              seenBodies.add(text.trim())) {
            comments.add(text.trim());
          }
        }
        final next = data['nextPageToken'];
        if (next is! String || next.isEmpty) {
          token = null;
          break;
        }
        if (!seenTokens.add(next)) {
          interrupted = true;
          break;
        }
        token = next;
      } catch (_) {
        interrupted = true;
        break;
      }
    }
    return YoutubeResults(metadata['title'] as String? ?? '',
        metadata['description'] as String? ?? '', comments,
        mayBeIncomplete: interrupted || token != null);

  }
}
