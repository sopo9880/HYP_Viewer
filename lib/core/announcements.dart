import 'dart:convert';

import 'package:http/http.dart' as http;

/// Administrator announcements are maintained in a separate, write-protected
/// GitHub branch. No administrator credentials or push tokens are in the app.
class AppAnnouncement {
  final String id;
  final String title;
  final String message;
  final DateTime publishedAt;
  final Map<String, String> translatedTitles, translatedMessages;
  const AppAnnouncement({
    required this.id,
    required this.title,
    required this.message,
    required this.publishedAt,
    this.translatedTitles = const {},
    this.translatedMessages = const {},
  });

  static Map<String, String> _translations(
      Object? source, String field, int maximum) {
    if (source is! Map) return {};
    final result = <String, String>{};
    for (final language in const ['en', 'ja']) {
      final translated = source[language];
      if (translated is! Map || translated[field] is! String) continue;
      final value = (translated[field] as String).trim();
      if (value.isNotEmpty && value.length <= maximum) {
        result[language] = value;
      }
    }
    return result;
  }

  String titleFor(String language) {
    if (language == 'ko') return title;
    final translated = translatedTitles[language];
    if (translated != null) return translated;
    if (!RegExp(r'[가-힣]').hasMatch(title)) return title;
    return language == 'ja'
        ? '翻訳されていないお知らせ' : 'Untranslated announcement';
  }

  String messageFor(String language) {
    if (language == 'ko') return message;
    final translated = translatedMessages[language];
    if (translated != null) return translated;
    if (!RegExp(r'[가-힣]').hasMatch(message)) return message;
    return language == 'ja'
        ? 'このお知らせは韓国語のみです。原文は言語を韓国語に切り替えて確認できます。'
        : 'This notice is only available in Korean. Switch the app to Korean to read the original.';
  }

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
      translatedTitles: _translations(value['translations'], 'title', 120),
      translatedMessages: _translations(value['translations'], 'message', 2000),
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
