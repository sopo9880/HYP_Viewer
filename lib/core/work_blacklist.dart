import 'dart:convert';

import 'online_search.dart';
import 'work.dart';

/// Local, user-defined rules. No network requests and no server-side profile.
class WorkBlacklistRule {
  static const kinds = {'id', 'artist', 'group', 'tag', 'title'};
  final String kind;
  final String value;
  final String reason;

  const WorkBlacklistRule(this.kind, this.value, {this.reason = ''});

  String get identity => kind + ':' + value.trim().toLowerCase();

  Map<String, String> toJson() =>
      {'kind': kind, 'value': value, if (reason.isNotEmpty) 'reason': reason};

  static WorkBlacklistRule parse(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('차단 규칙 형식이 올바르지 않아.');
    }
    final kind = raw['kind'];
    final value = raw['value'];
    final reason = raw['reason'];
    if (kind is! String || !kinds.contains(kind) ||
        value is! String || value.trim().isEmpty ||
        value.trim().length > 160 ||
        (kind == 'id' && !RegExp(r'^\d{1,12}$').hasMatch(value.trim())) ||
        (reason != null && (reason is! String || reason.length > 250))) {
      throw const FormatException('블랙리스트에 유효하지 않은 차단 규칙이 있어.');
    }
    return WorkBlacklistRule(kind, value.trim(),
        reason: reason is String ? reason.trim() : '');
  }
}

/// Shared matcher for the search screen, candidate verification and saves.
/// ID matches are exact; metadata rules are case-insensitive substring matches.
abstract final class WorkBlacklist {
  static String norm(String raw) =>
      raw.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  static List<WorkBlacklistRule> decodeRules(Object? input) {
    if (input == null) return const [];
    if (input is! List || input.length > 500) {
      throw const FormatException('블랙리스트는 최대 500개까지 지원해.');
    }
    final rules = <WorkBlacklistRule>[];
    final seen = <String>{};
    for (final item in input) {
      final rule = WorkBlacklistRule.parse(item);
      if (seen.add(rule.identity)) rules.add(rule);
    }
    return rules;
  }

  static String exportJson(Iterable<WorkBlacklistRule> rules) =>
      const JsonEncoder.withIndent('  ').convert({
        'app': 'HYP Viewer', 'type': 'blacklist', 'version': 1,
        'rules': rules.map((r) => r.toJson()).toList(),
      });

  static List<WorkBlacklistRule> importJson(String json) {
    if (utf8.encode(json).length > 128 * 1024) {
      throw const FormatException('블랙리스트 JSON이 너무 커.');
    }
    final data = jsonDecode(json);
    if (data is! Map || data['app'] != 'HYP Viewer' ||
        data['type'] != 'blacklist' || data['version'] != 1) {
      throw const FormatException('HYP Viewer 블랙리스트 JSON이 아니야.');
    }
    return decodeRules(data['rules']);
  }

  static WorkBlacklistRule? match({
    required Iterable<WorkBlacklistRule> rules,
    required String workId,
    String title = '',
    Iterable<String> titleAliases = const [],
    Iterable<String> artists = const [],
    Iterable<String> groups = const [],
    Iterable<String> tags = const [],
  }) {
    bool contains(Iterable<String> values, String needle) =>
        values.any((s) => norm(s).contains(needle));
    for (final rule in rules) {
      final term = norm(rule.value);
      final matched = switch (rule.kind) {
        'id' => workId == rule.value,
        'artist' => contains(artists, term),
        'group' => contains(groups, term),
        'tag' => contains(tags, term),
        'title' => contains([title, ...titleAliases], term),
        _ => false,
      };
      if (matched) return rule;
    }
    return null;
  }

  static WorkBlacklistRule? matchId(
      Iterable<WorkBlacklistRule> rules, String id) {
    for (final rule in rules) {
      if (rule.kind == 'id' && rule.value == id) return rule;
    }
    return null;
  }

  static WorkBlacklistRule? matchLocal(
      Iterable<WorkBlacklistRule> rules, WorkEntry work) => match(
        rules: rules,
        workId: work.workId,
        title: work.title, titleAliases: work.titleAliases,
        artists: work.author.split(','),
        groups: work.sourceGroup.split(','),
        tags: work.tags,
      );

  static WorkBlacklistRule? matchOnline(
      Iterable<WorkBlacklistRule> rules, OnlineSearchWork work) => match(
        rules: rules, workId: work.workId, title: work.title,
        titleAliases: work.titleAliases, artists: work.artists,
        groups: work.groups, tags: work.tags);
}
