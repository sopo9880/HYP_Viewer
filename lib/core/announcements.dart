import 'dart:convert';

import 'package:http/http.dart' as http;

/// Administrator announcements are maintained in a separate, write-protected
/// GitHub branch. No administrator credentials or push tokens are in the app.
class AppAnnouncement {
  final String id;
  final String title;
  final String message;
  final DateTime publishedAt;
  const AppAnnouncement({
    required this.id,
    required this.title,
    required this.message,
    required this.publishedAt,
  });

  factory AppAnnouncement.fromJson(Map<String, dynamic> value) {
    final id = value['id'];
    final title = value['title'];
    final message = value['message'];
    final published = DateTime.tryParse(value['publishedAt']?.toString() ?? '');
    if (id is! String || !RegExp(r'^[a-zA-Z0-9_-]{5,80}$').hasMatch(id) ||
        title is! String || title.trim().isEmpty || title.length > 120 ||
        message is! String || message.trim().isEmpty || message.length > 2000 ||
        published == null) {
      throw const FormatException('알림 정보가 올바르지 않아.');
    }
    return AppAnnouncement(
      id: id, title: title.trim(),
      message: message.trim(), publishedAt: published.toUtc(),
    );
  }
}

class AnnouncementService {
  // No HTTP user-ID, token, account, device identifier or telemetry sent.
  static final Uri feedUrl = Uri.https('raw.githubusercontent.com',
      '/sopo9880/HYP_Viewer/app-announcements/notices/feed.json');

  final http.Client client;
  AnnouncementService(this.client);

  Future<List<AppAnnouncement>> load() async {
    final response = await client.get(feedUrl, headers: {
      'Accept': 'application/json',
      'Cache-Control': 'no-cache',
    }).timeout(const Duration(seconds: 13));
    if (response.statusCode != 200) {
      throw FormatException('공지 피드 HTTP 오류: ' +
          response.statusCode.toString());
    }
    if (response.bodyBytes.length > 64 * 1024) {
      throw const FormatException('공지 응답이 너무 커.');
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map<String, dynamic> || json['schemaVersion'] != 1 ||
        json['announcements'] is! List) {
      throw const FormatException('공지 피드 형식이 변경됐어.');
    }
    final raw = json['announcements'] as List;
    if (raw.length > 30) throw const FormatException('공지 개수 제한을 초과했어.');
    final seen = <String>{};
    final result = <AppAnnouncement>[];
    for (final entry in raw) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('공지 항목이 올바르지 않아.');
      }
      final item = AppAnnouncement.fromJson(entry);
      if (!seen.add(item.id)) throw const FormatException('공지 ID가 중복됐어.');
      result.add(item);
    }
    result.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return result;
  }
}
