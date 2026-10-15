import 'package:flutter/services.dart';
import 'youtube.dart';
import 'source_links.dart';

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

  /// Shared URLs are kept intact (videos, posts and reels).
  static String? findSourceUrl(String raw) {
    final links = SourceLink.extract(raw);
    return links.isEmpty ? null : links.first.url;
  }

  static Future<void> start(void Function(String url) onShared) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedText' && call.arguments is String) {
        final shared = call.arguments as String;
        if (SourceLink.extract(shared).isNotEmpty) onShared(shared);
      }
    });
    try {
      final initial = await _channel.invokeMethod<String>('getSharedText');
      if (initial != null) {
        if (SourceLink.extract(initial).isNotEmpty) onShared(initial);
      }
    } on MissingPluginException {
      // Desktop environments don't implement this optional platform channel.
    } on PlatformException {
      // An unavailable share channel should never block app startup.
    }
  }
}
