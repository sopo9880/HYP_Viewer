import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Hitomi's ranked work IDs, not exact per-gallery view counts.
class HitomiPopularity {
  final http.Client client;
  const HitomiPopularity(this.client);
  static const _host = 'ltn.gold-usergeneratedcontent.net';
  static const _maxBytes = 4 * 1024 * 1024;

  Future<Map<String, int>> loadRanks(String period) async {
    if (!const {'today', 'week', 'month', 'year'}.contains(period)) {
      throw const FormatException('지원하지 않는 인기 기간이야.');
    }
    final url = Uri.https(_host, '/n/popular/$period-all.nozomi');
    final request = http.Request('GET', url)
      ..followRedirects = false
      ..headers['Referer'] = 'https://hitomi.la/';
    final response = await client.send(request)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw FormatException('히토미 인기 목록 HTTP ${response.statusCode}');
    }
    if (response.contentLength != null &&
        response.contentLength! > _maxBytes) {
      throw const FormatException('인기 목록 용량 초과.');
    }
    final builder = BytesBuilder(copy: false);
    var read = 0;
    await for (final chunk in response.stream.timeout(
        const Duration(seconds: 20))) {
      read += chunk.length;
      if (read > _maxBytes) throw const FormatException('인기 목록 최대 크기 초과.');
      builder.add(chunk);
    }
    return parseNozomi(builder.takeBytes());
  }

  static Map<String, int> parseNozomi(Uint8List bytes) {
    if (bytes.isEmpty || bytes.lengthInBytes % 4 != 0) {
      throw const FormatException('잘못된 .nozomi 인기 목록 데이터.');
    }
    final view = ByteData.sublistView(bytes);
    final ranks = <String, int>{};
    for (var i = 0; i < bytes.lengthInBytes; i += 4) {
      final id = view.getUint32(i, Endian.big);
      if (id > 0) ranks.putIfAbsent(id.toString(), () => i ~/ 4 + 1);
    }
    return ranks;
  }
}
