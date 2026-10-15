import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../core/work.dart';
import '../core/work_grouping.dart';
import '../core/i18n.dart';
import '../l10n/app_localizations.dart';

/// Reviewed selection for either a new group or an existing one.
class AutoGroupReview {
  final String title;
  final String existingGroupId;
  final List<String> workIds;
  const AutoGroupReview({
    required this.title, required this.existingGroupId,
    required this.workIds,
  });
}

/// Display recommendations, allow inspecting every title, excluding a work,
/// editing a name and adjusting chapter order before any storage changes.
class AutoGroupWizard extends StatefulWidget {
  final List<WorkGroupSuggestion> suggestions;
  final List<WorkEntry> works;
  final Map<String, Uint8List> coverImages;
  const AutoGroupWizard({
    super.key, required this.suggestions, required this.works,
    this.coverImages = const {},
  });
  @override
  State<AutoGroupWizard> createState() => _AutoGroupWizardState();
}

class _AutoGroupWizardState extends State<AutoGroupWizard> {
  final Set<int> _approved = {};
  final Map<int, List<String>> _order = {};
  final Map<int, Set<String>> _included = {};
  final Map<int, TextEditingController> _titles = {};
  late final Map<String, WorkEntry> _byId;

  @override
  void initState() {
    super.initState();
    _byId = {for (final work in widget.works) work.workId: work};
    for (var i = 0; i < widget.suggestions.length; i++) {
      final proposal = widget.suggestions[i];
      _order[i] = [...proposal.workIds];
      _included[i] = {...proposal.workIds};
      _titles[i] = TextEditingController(text: proposal.title)
        ..addListener(_changedTitle);
    }
  }

  void _changedTitle() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final controller in _titles.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _move(int group, int index, int offset) {
    final order = _order[group]!;
    final target = index + offset;
    if (target < 0 || target >= order.length) return;
    setState(() => order.insert(target, order.removeAt(index)));
  }

  List<AutoGroupReview> _reviewedPlans() {
    final plans = <AutoGroupReview>[];
    final used = <String>{};
    for (var i = 0; i < widget.suggestions.length; i++) {
      if (!_approved.contains(i)) continue;
      final proposal = widget.suggestions[i];
      final title = _titles[i]!.text.trim();
      final ids = _order[i]!.where((id) =>
          _included[i]!.contains(id) && !used.contains(id)).toList();
      final minimum = proposal.existingGroupId.isEmpty ? 2 : 1;
      if (title.isEmpty || ids.length < minimum) continue;
      used.addAll(ids);
      plans.add(AutoGroupReview(
        title: title, existingGroupId: proposal.existingGroupId,
        workIds: ids,
      ));
    }
    return plans;
  }

  Widget _workRow(int group, String id, int index) {
    final work = _byId[id];
    final selected = _included[group]!.contains(id);
    final cover = work == null ? null : widget.coverImages[work.key];
    final episode = work == null ? null : WorkGrouping.episodeNumber(work);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Checkbox(
          key: Key('auto-group-work-$group-$id'),
          value: selected,
          onChanged: (enabled) => setState(() {
            if (enabled == true) {
              _included[group]!.add(id);
              _approved.add(group);
            } else {
              _included[group]!.remove(id);
            }
          }),
        ),
        SizedBox(width: 36, height: 48,
          child: ColoredBox(color: const Color(0xFF1F2028),
            child: cover == null
                ? const Icon(Icons.menu_book_outlined, size: 19)
                : Image.memory(cover, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.broken_image_outlined, size: 19)),
          )),
        const SizedBox(width: 8),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            HypText(work?.title ?? id, maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13)),
            HypText('#$id' + (episode == null ? '' : ' · $episode화'),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall),
          ],
        )),
        IconButton(
          key: Key('auto-group-up-$group-$id'),
          tooltip: HypI18n.t(context, '한 칸 위로'),
          onPressed: index == 0 ? null : () => _move(group, index, -1),
          icon: const Icon(Icons.keyboard_arrow_up, size: 22),
        ),
        IconButton(
          key: Key('auto-group-down-$group-$id'),
          tooltip: HypI18n.t(context, '한 칸 아래로'),
          onPressed: index == _order[group]!.length - 1
              ? null : () => _move(group, index, 1),
          icon: const Icon(Icons.keyboard_arrow_down, size: 22),
        ),
      ]),
    );
  }

  Widget _groupTile(int i) {
    final proposal = widget.suggestions[i];
    final isExisting = proposal.existingGroupId.isNotEmpty;
    final members = isExisting
        ? widget.works.where((w) =>
            w.groupId == proposal.existingGroupId).toList()
        : <WorkEntry>[];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: Key('auto-group-review-$i'),
        initiallyExpanded: widget.suggestions.length == 1,
        leading: Checkbox(
          key: Key('auto-group-$i'),
          value: _approved.contains(i),
          onChanged: (value) => setState(() {
            if (value == true) { _approved.add(i); }
            else { _approved.remove(i); }
          }),
        ),
        title: HypText(proposal.title, maxLines: 2,
          overflow: TextOverflow.ellipsis),
        subtitle: HypText(
          (isExisting ? '기존 묶음에 추가' : '새 묶음') + ' · ' +
          proposal.workIds.length.toString() + '개 후보 · ' +
          '규칙 점수 ' + proposal.confidence.toString() + '/100\n' +
          proposal.reason,
          maxLines: 3,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
        children: [
          TextField(
            key: Key('auto-group-title-$i'),
            controller: _titles[i],
            maxLength: 200,
            decoration: InputDecoration(
              labelText: isExisting ? '기존 묶음 이름 수정' : '새 묶음 이름',
              isDense: true,
            ),
          ),
          if (members.isNotEmpty) ...[
            Align(alignment: Alignment.centerLeft,
              child: Text(AppLocalizations.of(context)!.autoGroupExistingCount(members.length),
                  style: Theme.of(context).textTheme.bodySmall)),
            for (final work in members.take(6))
              Align(alignment: Alignment.centerLeft,
                child: HypText('· ' + work.title + ' #' + work.workId,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall)),
            if (members.length > 6)
              Text(AppLocalizations.of(context)!.autoGroupOthers(members.length - 6),
                style: Theme.of(context).textTheme.bodySmall),
            const Divider(height: 16),
          ],
          Align(alignment: Alignment.centerLeft,
            child: HypText('포함할 작품 선택 · 화살표로 순서 조정',
              style: Theme.of(context).textTheme.bodySmall)),
          for (var j = 0; j < _order[i]!.length; j++)
            _workRow(i, _order[i]![j], j),
          if (!isExisting && _included[i]!.length < 2)
            const HypText('새 묶음에는 최소 2개 작품이 필요해.',
              style: TextStyle(color: Colors.orangeAccent)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plans = _reviewedPlans();
    return AlertDialog(
      key: const Key('auto-group-wizard'),
      title: const HypText('Auto 묶기 · 추천 확인'),
      content: SizedBox(
        width: 610,
        height: MediaQuery.sizeOf(context).height * 0.58,
        child: Column(children: [
          const HypText('추천 묶음을 펼쳐 표지·제목·번호를 확인해 줘. '
              '개별 작품을 제외하거나 이름과 순서를 바꿀 수 있어. '
              '확인 전에는 서재가 바뀌지 않아.',
              style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          Expanded(child: ListView.builder(
            key: const Key('auto-group-suggestions'),
            itemCount: widget.suggestions.length,
            itemBuilder: (context, index) => _groupTile(index),
          )),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
          child: const HypText('취소')),
        FilledButton(
          key: const Key('auto-group-confirm'),
          onPressed: plans.isEmpty ? null :
              () => Navigator.pop(context, plans),
          child: HypText('선택한 묶음 ' + plans.length.toString() + '개 적용'),
        ),
      ],
    );
  }
}
