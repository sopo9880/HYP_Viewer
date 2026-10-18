import 'package:flutter/material.dart';
import '../core/blacklist.dart';
import 'package:flutter/services.dart';

import '../core/candidate_verifier.dart';
import '../core/i18n.dart';
import 'hyp_animated_title.dart';
import '../l10n/app_localizations.dart';
import '../core/number_extractor.dart';

typedef CandidateBatchVerify = Future<Map<String, CandidateVerification>>
    Function(List<String> codes);

class _Slot {
  final int id;
  final TextEditingController controller;
  String episode;
  String evidence;
  String rule;
  bool selected;
  bool touched = false;
  String checkedCode = '';
  CandidateVerification? result;
  bool checking = false;

  _Slot(this.id, String code, this.episode, this.evidence, this.rule,
      {this.selected = false}) : controller = TextEditingController(text: code);
}

/// Candidate suggestions are evidence, not truth. Every editable slot belongs
/// to the user and keeps their input even if a later scan suggests another ID.
class CandidateEditor extends StatefulWidget {
  final List<NumberCandidate> suggestions;
  final CandidateBatchVerify? onVerify;
  final BlacklistRules blacklist;
  final Future<void> Function(BlacklistRule)? onBlacklistAdd;
  final Future<void> Function(String)? onPreview;
  final List<NumberCandidate> Function()? onCrossLineFallback;
  final Future<void> Function(List<String>) onSave;
  final bool busy;

  const CandidateEditor({
    super.key,
    required this.suggestions,
    required this.onSave,
    required this.busy,
    this.onVerify,
    this.blacklist = const BlacklistRules(),
    this.onBlacklistAdd,
    this.onPreview,
    this.onCrossLineFallback,
  });

  @override
  CandidateEditorState createState() => CandidateEditorState();
}

class CandidateEditorState extends State<CandidateEditor> {
  final List<_Slot> _slots = [];
  int _nextId = 0;
  bool _checking = false;
  bool _fallbackAttempted = false;
  int _verifiedCount = 0;
  int _verificationTotal = 0;
  String _fallbackMessage = '';
  static final _valid = RegExp(r'^\d{6,9}$');

  @override
  void initState() {
    super.initState();
    _appendSuggestions(widget.suggestions);
    if (widget.suggestions.isNotEmpty) {
      _scheduleVerify();
    } else if (widget.onCrossLineFallback != null &&
        widget.onVerify != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startFallback();
      });
    }
  }

  @override
  void didUpdateWidget(covariant CandidateEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldCodes = oldWidget.suggestions.map((e) => e.code).join(',');
    final nextCodes = widget.suggestions.map((e) => e.code).join(',');
    if (oldCodes != nextCodes) {
      // A new paste/video is a new scan: no stale suggestions carry over.
      for (final slot in _slots) {
        WidgetsBinding.instance.addPostFrameCallback((_) =>
            slot.controller.dispose());
      }
      _slots.clear();
      _fallbackAttempted = false;
      _fallbackMessage = '';
      _appendSuggestions(widget.suggestions);
      if (widget.suggestions.isNotEmpty) _scheduleVerify();
      else if (widget.onCrossLineFallback != null &&
          widget.onVerify != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _startFallback();
        });
      }
    }
  }

  void _appendSuggestions(List<NumberCandidate> suggestions) {
    final autoSelect = widget.onVerify == null && suggestions.length <= 3;
    for (final candidate in suggestions) {
      if (_slots.length >= 160) break;
      if (_slots.any((slot) => slot.controller.text == candidate.code)) {
        continue;
      }
      _slots.add(_Slot(
          _nextId++, candidate.code, candidate.episode,
          candidate.evidence, candidate.rule,
          selected: autoSelect));
    }
  }

  void _scheduleVerify() {
    if (widget.onVerify == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _verifyAll();
    });
  }

  void addSuggestion(NumberCandidate suggestion) {
    final existing = _slots.where((s) =>
        s.controller.text.trim() == suggestion.code).toList();
    setState(() {
      if (existing.isNotEmpty) {
        existing.first.selected = true;
      } else {
        _slots.add(_Slot(
            _nextId++, suggestion.code, suggestion.episode,
            suggestion.evidence, suggestion.rule, selected: true));
      }
    });
    if (widget.onVerify != null && existing.isEmpty) {
      _scheduleVerify();
    }
  }

  void addBlank() {
    setState(() => _slots.add(
      _Slot(_nextId++, '', '', '', 'manual', selected: true)));
  }

  void _remove(_Slot slot) {
    setState(() => _slots.remove(slot));
    WidgetsBinding.instance.addPostFrameCallback((_) =>
        slot.controller.dispose());
  }

  void _startFallback() {
    if (_fallbackAttempted || !mounted ||
        widget.onCrossLineFallback == null || _checking) return;
    _fallbackAttempted = true;
    final extra = widget.onCrossLineFallback!().where((candidate) =>
        candidate.rule.startsWith('cross-line') &&
        !_slots.any((s) => s.controller.text.trim() == candidate.code))
        .toList();
    if (extra.isEmpty) {
      setState(() => _fallbackMessage = '1차 결과 없음 · 2차 인접 줄 후보도 없어.');
      return;
    }
    setState(() {
      _fallbackMessage = '1차 작품 미발견 · 인접 줄 2차 검증 중 (' +
          extra.length.toString() + '개 후보)';
      _appendSuggestions(extra);
    });
    _scheduleVerify();
  }

  BlacklistRule? _blocked(_Slot slot) => widget.blacklist.firstMatch(
    id: slot.controller.text.trim(),
    title: slot.result?.title ?? '',
    artists: slot.result?.artists ?? const [],
    groups: slot.result?.groups ?? const [],
    tags: slot.result?.tags ?? const [],
  );

  Future<void> _verifyAll({bool force = false}) async {
    if (_checking || widget.onVerify == null) return;
    final matching = _slots.where((s) =>
        _blocked(s) == null && _valid.hasMatch(s.controller.text.trim()) &&
        (force || s.checkedCode != s.controller.text.trim() ||
            s.result == null ||
            s.result!.status == CandidateCheck.unavailable))
        .take(160).toList();
    if (matching.isEmpty) {
      _startFallback();
      return;
    }
    final checked = {for (final s in matching) s.id: s.controller.text.trim()};
    final uniqueCodes = checked.values.toSet().toList();
    final results = <String, CandidateVerification>{};
    setState(() {
      _checking = true;
      _verifiedCount = 0;
      _verificationTotal = uniqueCodes.length;
      for (final slot in matching) slot.checking = true;
    });
    var unavailableCount = 0;
    for (var start = 0; start < uniqueCodes.length; start += 24) {
      if (!mounted) return;
      final batch = uniqueCodes.skip(start).take(24).toList();
      Map<String, CandidateVerification> response;
      try {
        response = await widget.onVerify!(batch);
      } catch (_) {
        response = {};
      }
      for (final code in batch) {
        final check = response[code] ?? const CandidateVerification(
            CandidateCheck.unavailable, reason: 'request-failed');
        results[code] = check;
        if (check.status == CandidateCheck.unavailable) unavailableCount++;
      }
      if (!mounted) return;
      setState(() => _verifiedCount = results.length);
      // Stop issuing whole-comment traffic during a server outage.
      if (unavailableCount >= 8) break;
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      for (final slot in matching) {
        if (!_slots.contains(slot)) continue;
        slot.checking = false;
        final code = checked[slot.id]!;
        if (slot.controller.text.trim() != code) continue;
        slot.checkedCode = code;
        slot.result = results[code] ??
            const CandidateVerification(CandidateCheck.unavailable);
        if (!slot.touched) {
          slot.selected = slot.result!.status == CandidateCheck.verified &&
              _blocked(slot) == null;
        }
      }
    });
    // Only a definitive "not found" first pass triggers cross-line scans.
    // A 429/503/timeout is unavailable, not proof of absence.
    if (!_fallbackAttempted && results.isNotEmpty &&
        results.length == uniqueCodes.length &&
        results.values.every((item) => item.status == CandidateCheck.notFound) &&
        !_slots.any((slot) =>
            slot.result?.status == CandidateCheck.verified ||
            slot.result?.status == CandidateCheck.unavailable)) {
      _startFallback();
    } else if (unavailableCount > 0 && !_fallbackAttempted) {
      setState(() => _fallbackMessage =
          '서버 확인 실패가 있어 2차 확장은 보류했어. 나중에 재검증해 줘.');
    }
  }

  List<String> get selectedCodes {
    final used = <String>{};
    for (final slot in _slots) {
      final code = slot.controller.text.trim();
      if (slot.selected && _valid.hasMatch(code) &&
          _blocked(slot) == null) used.add(code);
    }
    return used.toList();
  }

  Widget _status(_Slot slot) {
    if (_blocked(slot) != null) {
      return HypText(HypI18n.t(context, '블랙리스트에 등록된 작품'),
          style: const TextStyle(color: Colors.redAccent));
    }
    if (slot.checking) return const HypText('작품 확인 중…');
    if (!_valid.hasMatch(slot.controller.text.trim())) {
      return const HypText('숫자 6~9자리 입력');
    }
    if (slot.checkedCode != slot.controller.text.trim() ||
        slot.result == null) {
      return const HypText('존재 여부 미검증');
    }
    switch (slot.result!.status) {
      case CandidateCheck.verified:
        return Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.verified_rounded,
              color: Colors.greenAccent, size: 16),
          const SizedBox(width: 5),
          Flexible(child: HypAnimatedTitle(
            key: Key('candidate-title-' + slot.id.toString()),
            title: slot.result!.title.isEmpty
                ? HypI18n.t(context, '작품 존재 확인')
                : slot.result!.title,
            motion: HypTitleMotion.automatic,
            style: const TextStyle(fontSize: 12, color: Colors.greenAccent),
          )),
        ]);
      case CandidateCheck.notFound:
        return const HypText('작품 미존재 (404)',
            style: TextStyle(color: Colors.orangeAccent, fontSize: 12));
      case CandidateCheck.unavailable:
        return const HypText('서버 확인 실패 · 직접 확인',
            style: TextStyle(color: Colors.amberAccent, fontSize: 12));
    }
  }

  Widget _slotCard(_Slot slot) {
    final label = slot.episode.isEmpty ? '수동 후보' : slot.episode;
    return Container(
      key: Key('candidate-row-' + slot.id.toString()),
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Checkbox(
            key: Key('candidate-select-' + slot.id.toString()),
            value: slot.selected && _blocked(slot) == null,
            onChanged: _blocked(slot) != null ? null : (value) => setState(() {
              slot.touched = true;
              slot.selected = value == true;
            }),
          ),
          Expanded(
            child: TextField(
              key: Key('candidate-input-' + slot.id.toString()),
              controller: slot.controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(9)],
              onChanged: (_) => setState(() {
                slot.touched = true;
                // An explicit edit opts this candidate back into selection.
                // The user may still uncheck it before saving.
                slot.selected = true;
                slot.result = null;
                slot.checkedCode = '';
              }),
              decoration: InputDecoration(
                isDense: true,
                labelText: HypI18n.translate(
                  label, HypLanguage.selected.value),
                hintText: HypI18n.t(context, '작품 번호 수정'),
                prefixIcon: const Icon(Icons.tag, size: 18),
              ),
            ),
          ),
          if (_valid.hasMatch(slot.controller.text.trim()) &&
              widget.onPreview != null && _blocked(slot) == null)
            IconButton(
              key: Key('candidate-preview-' + slot.id.toString()),
              tooltip: HypI18n.t(context, '미리보기'),
              onPressed: () => widget.onPreview!(slot.controller.text.trim()),
              icon: const Icon(Icons.visibility_outlined),
            ),
          if (_valid.hasMatch(slot.controller.text.trim()) &&
              widget.onBlacklistAdd != null && _blocked(slot) == null)
            IconButton(
              key: Key('candidate-blacklist-' + slot.id.toString()),
              tooltip: HypI18n.t(context, '블랙리스트에 추가'),
              onPressed: () => widget.onBlacklistAdd!(BlacklistRule(
                kind: 'id', value: slot.controller.text.trim())),
              icon: const Icon(Icons.block_outlined),
            ),
          IconButton(
            key: Key('candidate-remove-' + slot.id.toString()),
            tooltip: HypI18n.t(context, '후보 삭제'),
            icon: const Icon(Icons.close_rounded),
            onPressed: () => _remove(slot),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(left: 44, top: 5),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _status(slot),
            if (slot.evidence.isNotEmpty)
              Tooltip(
                message: slot.evidence,
                child: HypText(
                  (slot.rule.isEmpty ? '' : slot.rule + ' · ') + slot.evidence,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = selectedCodes.length;
    return Column(
      key: const Key('candidate-editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(child: HypText('후보 번호 편집 · 개수와 번호를 자유롭게 수정',
              style: Theme.of(context).textTheme.titleMedium)),
          HypText(_slots.length.toString(),
              style: Theme.of(context).textTheme.bodySmall),
        ]),
        if (widget.suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 7, runSpacing: 7, children:
            widget.suggestions.take(24).map((candidate) {
              final rows = _slots.where((s) =>
                  s.controller.text.trim() == candidate.code).toList();
              final selected = rows.isNotEmpty && rows.first.selected;
              return Tooltip(
                message: candidate.evidence,
                child: FilterChip(
                  key: Key('shorts-candidate-' + candidate.code),
                  label: HypText(candidate.episode.isEmpty
                      ? '#' + candidate.code
                      : candidate.episode + ' · #' + candidate.code),
                  selected: selected,
                  onSelected: (value) => setState(() {
                    if (rows.isNotEmpty) {
                      rows.first.touched = true;
                      rows.first.selected = value;
                    } else if (value) {
                      _slots.add(_Slot(
                          _nextId++, candidate.code, candidate.episode,
                          candidate.evidence, candidate.rule, selected: true));
                    }
                  }),
                ),
              );
            }).toList(),
          ),
        ],
        if (_checking)
          Padding(padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(AppLocalizations.of(context)!.candidateChecking(_verifiedCount, _verificationTotal),
              style: Theme.of(context).textTheme.bodySmall)),
        if (_fallbackMessage.isNotEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 8),
            child: HypText(_fallbackMessage,
              style: Theme.of(context).textTheme.bodySmall)),
        const SizedBox(height: 8),
        for (final slot in _slots) _slotCard(slot),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            key: const Key('candidate-add'),
            onPressed: widget.busy ? null : addBlank,
            icon: const Icon(Icons.add),
            label: const HypText('후보 입력칸 추가'),
          ),
          OutlinedButton.icon(
            key: const Key('candidate-verify-all'),
            onPressed: widget.busy || _checking || widget.onVerify == null
                ? null : () => _verifyAll(force: true),
            icon: const Icon(Icons.fact_check_outlined),
            label: const HypText('번호 존재 재검증'),
          ),
        ]),
        const SizedBox(height: 10),
        FilledButton.icon(
          key: const Key('save-selected-works'),
          onPressed: widget.busy || count == 0 ? null :
              () => widget.onSave(selectedCodes),
          icon: const Icon(Icons.library_add_outlined),
          label: Text(AppLocalizations.of(context)!.candidateSave(count)),
        ),
        const SizedBox(height: 5),
        const HypText('실제 존재하는 번호라도 댓글의 의도와 다를 수 있어. '
            '사용자가 선택한 번호만 서재에 저장돼.'),
      ],
    );
  }

  @override
  void dispose() {
    for (final slot in _slots) {
      slot.controller.dispose();
    }
    super.dispose();
  }
}
