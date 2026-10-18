import 'dart:typed_data';
import '../core/i18n.dart';
import '../l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../core/work.dart';
import 'hyp_theme.dart';
import 'hyp_animated_title.dart';

/// A series occupies exactly one normal library grid cell.
/// Up to three real member covers are offset inside the same cover viewport.
class HypWorkGroupCard extends StatelessWidget {
  final String title;
  final List<WorkEntry> members;
  final Map<String, Uint8List> coverImages;
  final VoidCallback onOpen;
  final ValueChanged<String> onAction;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onSelect;
  final VoidCallback? onLongPress;
  const HypWorkGroupCard({
    super.key,
    required this.title,
    required this.members,
    required this.coverImages,
    required this.onOpen,
    required this.onAction,
    this.selectionMode = false,
    this.selected = false,
    this.onSelect,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final shown = members.take(3).toList();
    return Material(
      color: HypColors.surface,
      borderRadius: BorderRadius.circular(15),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('open-library-group'),
        onTap: selectionMode ? (onSelect ?? onOpen) : onOpen,
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: selected ? HypColors.lightPurple :
              HypColors.border.withValues(alpha: 0.65),
              width: selected ? 2 : 1),
            borderRadius: BorderRadius.circular(15)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: Stack(fit: StackFit.expand, children: [
                for (var i = shown.length - 1; i >= 0; i--)
                  Positioned.fill(
                    left: (shown.length - 1 - i) * 6.0,
                    top: i * 6.0,
                    right: i * 6.0,
                    bottom: (shown.length - 1 - i) * 4.0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: const Color(0xFF171925),
                        border: Border.all(color: HypColors.border, width: 1.5)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: coverImages[shown[i].key] == null
                            ? Center(child: Icon(Icons.auto_stories_outlined,
                                size: 44, color: HypColors.lightPurple
                                    .withValues(alpha: 0.65)))
                            : Image.memory(coverImages[shown[i].key]!,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) =>
                                    const Center(child: Icon(Icons.collections_bookmark))),
                      ),
                    ),
                  ),
                if (selectionMode)
                  Positioned(left: 5, top: 5,
                    child: Checkbox(
                      key: const Key('group-selection-checkbox'),
                      value: selected,
                      onChanged: (_) => onSelect?.call(),
                    ),
                  ),
                Positioned(right: 5, top: 5,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: HypColors.background
                        .withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(18)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 5),
                      child: Text(AppLocalizations.of(context)!.groupCardVolumes(members.length),
                        style: const TextStyle(fontSize: 11,
                            fontWeight: FontWeight.w800)),
                    )),
                ),
              ]),
            )),
            Padding(padding: const EdgeInsets.fromLTRB(10, 9, 5, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  HypAnimatedTitle(
                    key: Key('group-title-' + members.first.groupId),
                    title: title,
                    style: const TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(AppLocalizations.of(context)!.groupCardWorks(members.length), maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11,
                        color: HypColors.muted)),
                  const SizedBox(height: 2),
                  Row(children: [
                    const Expanded(child: HypText('열어서 회차 보기',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11))),
                    SizedBox(width: 27, height: 25,
                      child: PopupMenuButton<String>(
                        key: const Key('group-card-menu'),
                        icon: const Icon(Icons.more_vert_rounded,
                          color: HypColors.muted, size: 19),
                        padding: EdgeInsets.zero,
                        onSelected: onAction,
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'members',
                              child: HypText('구성원 추가·제외·이동')),
                          PopupMenuItem(value: 'rename',
                              child: HypText('묶음 이름 수정')),
                          PopupMenuItem(value: 'reorder',
                              child: HypText('회차 순서 변경')),
                          PopupMenuItem(value: 'ungroup',
                              child: HypText('묶음만 해제')),
                        ],
                      )),
                  ]),
                  const SizedBox(height: 2),
                  Container(height: 4,
                    decoration: BoxDecoration(
                      color: HypColors.border.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(6))),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
