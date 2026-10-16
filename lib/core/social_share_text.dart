/// Decode social share descriptions locally. This class never performs IO.
class SocialShareHints {
  final String title;
  final String author;
  final String caption;

  const SocialShareHints({
    this.title = '',
    this.author = '',
    this.caption = '',
  });
}

class SocialShareText {
  static final RegExp _entities = RegExp(
    r'&(?:#(?:[xX][0-9a-fA-F]{1,6}|[0-9]{1,7})|amp|quot|apos|lt|gt|nbsp);',
    caseSensitive: false,
  );
  static const Map<String, String> _named = {
    'amp': '&', 'quot': '"', 'apos': "'",
    'lt': '<', 'gt': '>', 'nbsp': ' ',
  };

  /// Supports &#xC624;, &#064; and named HTML entities. A second pass
  /// handles share text that contains the double-escaped &amp;#x...; form.
  static String decode(String raw) {
    var value = raw;
    for (var pass = 0; pass < 2; pass++) {
      final next = value.replaceAllMapped(_entities, (match) {
        final token = match.group(0)!.substring(1, match.group(0)!.length - 1);
        if (!token.startsWith('#')) {
          return _named[token.toLowerCase()] ?? match.group(0)!;
        }
        final encoded = token.substring(1);
        final hex = encoded.startsWith('x') || encoded.startsWith('X');
        final point = int.tryParse(hex ? encoded.substring(1) : encoded,
            radix: hex ? 16 : 10);
        if (point == null || point == 0 || point > 0x10ffff ||
            (point >= 0xd800 && point <= 0xdfff)) {
          return match.group(0)!;
        }
        return String.fromCharCode(point);
      });
      if (next == value) break;
      value = next;
    }
    return value;
  }

  static String normalize(String raw) => decode(raw)
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'\r\n?'), '\n')
      .trim();

  /// Only explicit Instagram captions and artist labels may prefill
  /// editable fields. A detected title is never a verified gallery ID.
  static SocialShareHints hints(String raw) {
    final normalized = normalize(raw);
    var caption = '';
    final marker = RegExp(r'on Instagram:\s*"', caseSensitive: false)
        .firstMatch(normalized);
    if (marker != null) {
      final tail = normalized.substring(marker.end);
      final closing = tail.indexOf('"');
      caption = (closing < 0 ? tail : tail.substring(0, closing)).trim();
    }
    var title = '';
    if (caption.isNotEmpty) {
      final firstLine = caption.split('\n').first.trim();
      if (firstLine.isNotEmpty && firstLine.length <= 200 &&
          !firstLine.startsWith('#') &&
          !RegExp(r'^https?://', caseSensitive: false).hasMatch(firstLine)) {
        title = firstLine;
      }
    }
    final authorMatch = RegExp(
      r'(?:^|\n)\s*(?:작가|author|作者)\s*[:：]\s*([^\[\n\r]{1,100})',
      caseSensitive: false,
    ).firstMatch(caption.isEmpty ? normalized : caption);
    return SocialShareHints(title: title,
      author: authorMatch?.group(1)?.trim() ?? '', caption: caption);
  }
}
