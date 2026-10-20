import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Bounded, offline-first network-ad host rules from a public EasyList.
/// Only plain host rules are accepted; remote scripts are NEVER executed.
class WebSearchAdRuleStore {
  WebSearchAdRuleStore._();
  static final WebSearchAdRuleStore instance = WebSearchAdRuleStore._();

  static const subscriptionUrl = 'https://easylist.to/easylist/easylist.txt';
  static const refreshInterval = Duration(days: 7);
  static const maxDownloadBytes = 8 * 1024 * 1024;
  static final RegExp _host = RegExp(
      r'^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\.[a-z]{2,24}$');

  Set<String> _domains = <String>{};
  bool _started = false;
  int get domainCount => _domains.length;
  Set<String> get domains => _domains;

  static Set<String> parseDomains(String source) {
    final result = <String>{};
    for (final raw in source.split('\n')) {
      final line = raw.trim().toLowerCase();
      // Only unqualified domain rules or strictly third-party rules.
      // Never treat exceptions, regexp, wildcards, cosmetics or scriptlets
      // as a blocking host.
      if (!line.startsWith('||') || line.startsWith('@@')) continue;
      final end = line.indexOf('^');
      if (end <= 2) continue;
      final host = line.substring(2, end);
      final suffix = line.substring(end + 1);
      if (suffix.isNotEmpty && suffix != r'$third-party') continue;
      if (!_host.hasMatch(host) || host.contains('..')) continue;
      result.add(host);
    }
    return result;
  }

  static bool matchesHost(String host, Set<String> domains) {
    var candidate = host.toLowerCase();
    while (true) {
      if (domains.contains(candidate)) return true;
      final dot = candidate.indexOf('.');
      if (dot < 0) return false;
      candidate = candidate.substring(dot + 1);
    }
  }

  bool blocks(String host) => matchesHost(host, _domains);

  void ensureStarted() {
    if (_started) return;
    _started = true;
    unawaited(_readCacheAndUpdate());
  }

  Future<void> _readCacheAndUpdate() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File(dir.path + Platform.pathSeparator +
          'web_search_ad_hosts.txt');
      if (await file.exists()) {
        final cached = await file.readAsLines();
        _domains = cached.map((s) => s.trim().toLowerCase())
            .where((host) => _host.hasMatch(host) && !host.contains('..'))
            .toSet();
        if (DateTime.now().difference(await file.lastModified()) <
            refreshInterval) return;
      }

      // Failure is harmless: curated built-in rules remain in force.
      final response = await http.get(Uri.parse(subscriptionUrl))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200 ||
          response.bodyBytes.length < 1024 ||
          response.bodyBytes.length > maxDownloadBytes) return;
      final updated = parseDomains(response.body);
      if (updated.length < 100) return;
      // Atomic replacement: never destroy a previously working cache on
      // an interrupted download.
      final tmp = File(file.path + '.tmp');
      final sorted = updated.toList()..sort();
      await tmp.writeAsString(sorted.join('\n') + '\n', flush: true);
      if (await file.exists()) {
        // Windows cannot atomically rename on top of an existing file.
        // Preserve the previous list until the replacement is in place.
        final backup = File(file.path + '.backup');
        if (await backup.exists()) await backup.delete();
        await file.rename(backup.path);
        try {
          await tmp.rename(file.path);
          await backup.delete();
        } catch (_) {
          await backup.rename(file.path);
          rethrow;
        }
      } else {
        await tmp.rename(file.path);
      }
      _domains = updated;
    } catch (_) {
      // No permissions, network access or path-provider plugin are required
      // for the built-in offline ad filtering to work.
    }
  }
}
