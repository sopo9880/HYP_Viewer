import 'package:flutter/material.dart';

import '../core/blacklist.dart';
import '../core/i18n.dart';

class BlacklistManagerDialog extends StatefulWidget {
  final BlacklistRules rules;
  final Future<void> Function(BlacklistRules) onSave;
  final Future<void> Function() onExport;
  final Future<BlacklistRules?> Function() onImport;
  const BlacklistManagerDialog({
    super.key, required this.rules, required this.onSave,
    required this.onExport, required this.onImport,
  });
  @override
  State<BlacklistManagerDialog> createState() => _BlacklistManagerDialogState();
}

class _BlacklistManagerDialogState extends State<BlacklistManagerDialog> {
  late BlacklistRules _rules;
  final _value = TextEditingController();
  final _reason = TextEditingController();
  final _search = TextEditingController();
  String _kind = 'id';
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _rules = widget.rules;
  }

  @override
  void dispose() {
    _value.dispose();
    _reason.dispose();
    _search.dispose();
    super.dispose();
  }

  String _label(String kind) => switch (kind) {
    'id' => HypI18n.t(context, '작품 번호'),
    'artist' => HypI18n.t(context, '작가'),
    'group' => HypI18n.t(context, '서클'),
    'tag' => HypI18n.t(context, '태그'),
    _ => HypI18n.t(context, '제목 키워드'),
  };

  Future<void> _save(BlacklistRules updated) async {
    setState(() { _busy = true; _error = null; });
    try {
      await widget.onSave(updated);
      if (mounted) setState(() => _rules = updated);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final value = _value.text.trim();
    if (value.isEmpty) return;
    if (_kind == 'id' && !RegExp(r'^\d{6,12}$').hasMatch(value)) {
      setState(() => _error = HypI18n.t(context, '작품 번호 형식을 확인해 줘.'));
      return;
    }
    final rule = BlacklistRule(kind: _kind, value: value,
      reason: _reason.text.trim(),
      createdAt: DateTime.now().toUtc().toIso8601String());
    await _save(_rules.add(rule));
    if (_error == null) {
      _value.clear();
      _reason.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final entries = _rules.rules.where((r) =>
        query.isEmpty || r.value.toLowerCase().contains(query) ||
        r.reason.toLowerCase().contains(query)).toList();
    return AlertDialog(
      key: const Key('blacklist-manager'),
      title: Text(HypI18n.t(context, '블랙리스트 관리')),
      content: SizedBox(
        width: 560,
        height: MediaQuery.sizeOf(context).height * 0.64,
        child: Column(children: [
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(
              key: const Key('blacklist-kind'),
              initialValue: _kind,
              items: [for (final kind in BlacklistRule.kinds)
                DropdownMenuItem(value: kind, child: Text(_label(kind)))],
              onChanged: _busy ? null :
                (kind) => setState(() => _kind = kind ?? 'id'),
            )),
            const SizedBox(width: 8),
            Expanded(child: TextField(
              key: const Key('blacklist-value'),
              controller: _value,
              decoration: InputDecoration(
                labelText: HypI18n.t(context, '차단할 값')),
            )),
          ]),
          const SizedBox(height: 8),
          TextField(
            key: const Key('blacklist-reason'),
            controller: _reason,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: HypI18n.t(context, '차단 이유 (선택)')),
          ),
          Row(children: [
            FilledButton.icon(
              key: const Key('blacklist-add'),
              onPressed: _busy ? null : _add,
              icon: const Icon(Icons.add),
              label: Text(HypI18n.t(context, '차단 추가')),
            ),
            const Spacer(),
            IconButton(
              tooltip: HypI18n.t(context, 'JSON 내보내기'),
              onPressed: _busy ? null : widget.onExport,
              icon: const Icon(Icons.upload_file_outlined),
            ),
            IconButton(
              tooltip: HypI18n.t(context, 'JSON 가져오기'),
              onPressed: _busy ? null : () async {
                setState(() => _busy = true);
                final restored = await widget.onImport();
                if (mounted) setState(() {
                  if (restored != null) _rules = restored;
                  _busy = false;
                });
              },
              icon: const Icon(Icons.file_open_outlined),
            ),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              labelText: HypI18n.t(context, '차단 목록 검색')),
          ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          const SizedBox(height: 6),
          Expanded(child: ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final item = entries[index];
              return ListTile(
                key: Key('blacklist-rule-' + item.kind + '-' + item.value),
                dense: true,
                title: Text(_label(item.kind) + ': ' + item.value),
                subtitle: item.reason.isEmpty ? null : Text(item.reason),
                trailing: IconButton(
                  tooltip: HypI18n.t(context, '차단 해제'),
                  onPressed: _busy ? null :
                      () => _save(_rules.without(item.kind, item.value)),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              );
            },
          )),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(HypI18n.t(context, '닫기'))),
      ],
    );
  }
}
