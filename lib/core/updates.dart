import 'dart:convert';
import 'package:http/http.dart' as http;

class ReleaseUpdate {
  final String version;
  final String notes;
  final String url;
  const ReleaseUpdate(this.version, this.notes, this.url);
}

class UpdateService {
  final http.Client client;
  UpdateService(this.client);

  Future<ReleaseUpdate?> latest(String current) async {
    final response = await client.get(
      Uri.parse('https://api.github.com/repos/sopo9880/HYP_Viewer/releases/latest'),
      headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'HYP-Viewer'},
    ).timeout(const Duration(seconds: 12));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('GitHub Releases status ' + response.statusCode.toString());
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final version = (data['tag_name'] as String? ?? '').replaceFirst(RegExp(r'^v'), '');
    if (!_isNewer(version, current)) return null;
    return ReleaseUpdate(version, data['body'] as String? ?? '', data['html_url'] as String? ?? '');
  }

  bool _isNewer(String latest, String current) {
    List<int> parts(String v) => v.split('-').first.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final a = parts(latest);
    final b = parts(current);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }
}
