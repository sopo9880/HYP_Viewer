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
    final commentUri = Uri.https('www.googleapis.com', '/youtube/v3/commentThreads', {
      'part': 'snippet', 'videoId': id, 'maxResults': '100',
      'order': 'relevance', 'textFormat': 'plainText', 'key': apiKey
    });
    final commentResponse = await client.get(commentUri).timeout(const Duration(seconds: 12));
    final comments = <String>[];
    if (commentResponse.statusCode != 200) {
      throw Exception('YouTube 댓글 조회 실패 (HTTP ${commentResponse.statusCode}). '
          'API 권한·할당량 또는 영상의 댓글 허용 여부를 확인해줘.');
    }
    final commentData = jsonDecode(commentResponse.body) as Map<String, dynamic>;
    for (final item in commentData['items'] as List? ?? []) {
      final body = item['snippet']?['topLevelComment']?['snippet']?['textDisplay'];
      if (body is String) comments.add(body);
    }
    final nextToken = commentData['nextPageToken'];
    return YoutubeResults(metadata['title'] as String? ?? '',
        metadata['description'] as String? ?? '', comments,
        mayBeIncomplete: nextToken is String && nextToken.isNotEmpty);
  }
}
