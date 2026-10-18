import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Independent denylist. It never deletes or mutates an existing library work.
class BlacklistRule {
  static const kinds = ['id', 'artist', 'group', 'tag', 'title'];
  final String kind;
  final String value;
  final String reason;
  final String createdAt;
  const BlacklistRule({
    required this.kind,
    required this.value,
    this.reason = '',
    this.createdAt = '',
  });

  String get normalized => value.trim().toLowerCase().replaceAll(' ', '_');

  bool matches({
    String id = '',
    String title = '',
    Iterable<String> artists = const [],
    Iterable<String> groups = const [],
    Iterable<String> tags = const [],
  }) {
    final term = normalized;
    if (term.isEmpty) return false;
    String normalize(String text) =>
        text.toLowerCase().trim().replaceAll(' ', '_');
    bool anyContains(Iterable<String> items) => items.any((s) =>
        normalize(s).contains(term));
    switch (kind) {
      case 'id':
        return id.trim() == value.trim();
      case 'artist':
        return anyContains(artists);
      case 'group':
        return anyContains(groups);
      case 'tag':
        return anyContains(tags);
      case 'title':
        return normalize(title).contains(term);
      default:
        return false;
    }
  }

  Map<String, Object?> toJson() => {
    'kind': kind, 'value': value,
    'reason': reason, 'createdAt': createdAt,
  };

  factory BlacklistRule.fromJson(Map<dynamic, dynamic> json) {
    final kind = json['kind'];
    final value = json['value'];
    if (kind is! String || !kinds.contains(kind) || value is! String ||
        value.trim().isEmpty || value.length > 200) {
      throw const FormatException('잘못된 블랙리스트 항목이야.');
    }
    String text(String key) => json[key] is String
        ? (json[key] as String).trim() : '';
    return BlacklistRule(
      kind: kind, value: value.trim(),
      reason: text('reason').length <= 500 ? text('reason') : '',
      createdAt: text('createdAt'),
    );
  }
}

class BlacklistRules {
  final List<BlacklistRule> rules;
  const BlacklistRules([this.rules = const []]);

  BlacklistRule? firstMatch({
    String id = '',
    String title = '',
    Iterable<String> artists = const [],
    Iterable<String> groups = const [],
    Iterable<String> tags = const [],
  }) {
    for (final rule in rules) {
      if (rule.matches(id: id, title: title, artists: artists,
          groups: groups, tags: tags)) return rule;
    }
    return null;
  }

  bool blocks({
    String id = '', String title = '',
    Iterable<String> artists = const [],
    Iterable<String> groups = const [],
    Iterable<String> tags = const [],
  }) => firstMatch(id: id, title: title, artists: artists,
      groups: groups, tags: tags) != null;

  BlacklistRules add(BlacklistRule rule) {
    if (!BlacklistRule.kinds.contains(rule.kind) ||
        rule.value.trim().isEmpty || rule.value.length > 200) {
      throw const FormatException('차단 기준을 다시 확인해 줘.');
    }
    final key = rule.normalized;
    return BlacklistRules([
      for (final old in rules)
        if (old.kind != rule.kind || old.normalized != key) old,
      rule,
    ]);
  }

  BlacklistRules without(String kind, String value) => BlacklistRules([
    for (final item in rules)
      if (item.kind != kind || item.normalized !=
          value.trim().toLowerCase().replaceAll(' ', '_')) item,
  ]);

  BlacklistRules merge(BlacklistRules other) {
    var result = this;
    for (final rule in other.rules) {
      if (!result.rules.any((existing) => existing.kind == rule.kind &&
          existing.normalized == rule.normalized)) result = result.add(rule);
    }
    return result;
  }

  String encode() => const JsonEncoder.withIndent('  ').convert({
    'app': 'HYP Viewer Blacklist', 'schemaVersion': 1,
    'rules': rules.map((r) => r.toJson()).toList(),
  });

  static BlacklistRules decode(String data) {
    if (utf8.encode(data).length > 5 * 1024 * 1024) {
      throw const FormatException('블랙리스트 JSON이 너무 커.');
    }
    final raw = jsonDecode(data);
    if (raw is! Map<String, dynamic> ||
        raw['app'] != 'HYP Viewer Blacklist' ||
        raw['schemaVersion'] != 1 || raw['rules'] is! List) {
      throw const FormatException('블랙리스트 JSON 형식을 확인해 줘.');
    }
    final list = raw['rules'] as List;
    if (list.length > 5000) {
      throw const FormatException('블랙리스트는 최대 5000개 항목을 지원해.');
    }
    var result = const BlacklistRules();
    for (final entry in list) {
      if (entry is! Map) throw const FormatException('차단 항목 형식 오류');
      result = result.add(BlacklistRule.fromJson(entry));
    }
    return result;
  }
}

/// Store rules separately, preserving version 1 library and CBZ formats.
class BlacklistStore {
  const BlacklistStore();
  Future<File> _file() async {
    final root = await getApplicationSupportDirectory();
    await root.create(recursive: true);
    return File(root.path + Platform.pathSeparator + 'hyp_blacklist.json');
  }

  Future<BlacklistRules> load() async {
    final file = await _file();
    if (!await file.exists()) return const BlacklistRules();
    return BlacklistRules.decode(await file.readAsString());
  }

  Future<void> save(BlacklistRules rules) async {
    final file = await _file();
    // Leave the last good version available if a future write fails.
    if (await file.exists()) {
      await file.copy(file.path + '.previous');
    }
    await file.writeAsString(rules.encode(), flush: true);
  }
}
