import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Fetch only user-opened, public image CDN URLs. No redirects, private
/// networks, credentials, cookies or arbitrary URL fetching are allowed.
abstract final class MediaImageFetcher {
  static const int maxBytes = 6 * 1024 * 1024;
  static const allowedDomains = <String>{
    'cdninstagram.com', 'fbcdn.net', 'instagram.com',
    'ytimg.com', 'ggpht.com', 'googleusercontent.com',
  };

  static bool isApproved(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty ||
        uri.hasPort || uri.host.length > 200 || raw.length > 4000) return false;
    final host = uri.host.toLowerCase();
    return allowedDomains.any((domain) =>
        host == domain || host.endsWith('.' + domain));
  }

  static Future<Uint8List?> fetch(http.Client client, String raw) async {
    if (!isApproved(raw)) return null;
    final request = http.Request('GET', Uri.parse(raw))
      ..followRedirects = false
      ..maxRedirects = 0;
    http.StreamedResponse response;
    try {
      response = await client.send(request).timeout(const Duration(seconds: 12));
    } catch (_) {
      return null;
    }
    if (response.statusCode != 200 ||
        !(response.headers['content-type'] ?? '')
            .toLowerCase().startsWith('image/')) return null;
    final length = int.tryParse(response.headers['content-length'] ?? '');
    if (length != null && length > maxBytes) return null;
    final builder = BytesBuilder(copy: false);
    try {
      await for (final chunk in response.stream
          .timeout(const Duration(seconds: 12))) {
        if (builder.length + chunk.length > maxBytes) return null;
        builder.add(chunk);
      }
      final data = builder.takeBytes();
      return data.isEmpty ? null : data;
    } catch (_) {
      return null;
    }
  }
}
