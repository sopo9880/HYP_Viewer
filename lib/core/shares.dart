import 'package:flutter/services.dart';
import 'youtube.dart';
import 'source_links.dart';
import 'social_share_text.dart';

/// Listen for Android ACTION_SEND text; no native channel is needed on Windows.
class SharedShorts {
  static const MethodChannel _channel = MethodChannel('hyp_viewer/share');

  static String? findVideoUrl(String raw) {
    for (final match in RegExp(r'https?://[^\s<>"\x27]+').allMatches(raw)) {
      final url = match.group(0)!.replaceFirst(RegExp(r'[)\].,!?]+$'), '');
      final id = ShortsLink.videoId(url);
      if (id != null) return 'https://www.youtube.com/shorts/$id';
    }
    final id = ShortsLink.videoId(raw.trim());
    return id == null ? null : 'https://www.youtube.com/shorts/$id';
  }

  /// Instagram can share a caption without a URL. Keep that text.
  static String? normalizeIncoming(String raw) {
    if (raw.length > 262144) return null;
    final normalized = SocialShareText.normalize(raw);
    return normalized.isEmpty ? null : normalized;
  }

  /// Shared URLs are kept intact (videos, posts and reels).
  static String? findSourceUrl(String raw) {
    final links = SourceLink.extract(raw);
    return links.isEmpty ? null : links.first.url;
  }

  static Future<void> start(void Function(String text) onShared, {
    void Function(List<String> paths)? onSharedImages,
  }) async {
    final received = <String>{};
    void acceptImages(dynamic value) {
      if (value is! List || onSharedImages == null) return;
      final paths = value.whereType<String>().where((path) =>
          path.isNotEmpty && received.add(path)).take(8).toList();
      if (paths.isNotEmpty) onSharedImages(paths);
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedText' && call.arguments is String) {
        final shared = normalizeIncoming(call.arguments as String);
        if (shared != null) onShared(shared);
      } else if (call.method == 'sharedImages') {
        acceptImages(call.arguments);
      }
    });
    try {
      final initial = await _channel.invokeMethod<String>('getSharedText');
      if (initial != null) {
        final shared = normalizeIncoming(initial);
        if (shared != null) onShared(shared);
      }
    } on MissingPluginException {
      // Desktop environments don't implement this optional platform channel.
    } on PlatformException {
      // An unavailable share channel should never block app startup.
    }
    try {
      acceptImages(await _channel.invokeMethod<List<dynamic>>('getSharedImages'));
    } on MissingPluginException {
      // Native image sharing is only present on updated Android builds.
    } on PlatformException {
      // App still supports manual image selection.
    }
  }
}
