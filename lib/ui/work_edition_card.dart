import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/work.dart';
import '../core/work_editions.dart';
import '../l10n/app_localizations.dart';
import 'hyp_theme.dart';
import 'hyp_animated_title.dart';

/// A language stack has two intentional targets: cover = resume reading,
/// title/details = open the language picker.
class HypWorkEditionCard extends StatelessWidget {
  final List<WorkEntry> editions;
  final Map<String, Uint8List> coverImages;
  final VoidCallback onOpen;
  final VoidCallback? onOpenCover;

  const HypWorkEditionCard({
    super.key,
    required this.editions,
    required this.coverImages,
    required this.onOpen,
    this.onOpenCover,
  });

  @override
  Widget build(BuildContext context) {
    final covers = editions.take(3).toList();
    final title = editions.first.title.split('|').first.trim();
    final group = editions.first.editionGroupId;
    return Material(
      color: HypColors.surface,
      borderRadius: BorderRadius.circular(15),
      clipBehavior: Clip.antiAlias,
      child: Container(
        key: Key('edition-stack-' + group),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: HypColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: InkWell(
                key: Key('edition-cover-' + group),
                onTap: onOpenCover ?? onOpen,
                child: Stack(fit: StackFit.expand, children: [
                  for (var i = covers.length - 1; i >= 0; i--)
                    Positioned.fill(
                      left: i * 5.0,
                      top: i * 5.0,
                      right: (covers.length - 1 - i) * 5.0,
                      bottom: (covers.length - 1 - i) * 5.0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: HypColors.raised,
                          border: Border.all(color: HypColors.border, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: coverImages[covers[i].key] == null
                              ? const Icon(Icons.menu_book_outlined, size: 48)
                              : Image.memory(coverImages[covers[i].key]!,
                                  fit: BoxFit.contain),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 9,
                    right: 9,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: HypColors.background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Text(
                          AppLocalizations.of(context)!.editionCount(
                              editions.length),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            InkWell(
              key: Key('edition-details-' + group),
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(9, 9, 9, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HypAnimatedTitle(
                      key: Key('edition-title-' + group),
                      title: title.isEmpty ? editions.first.workId : title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 5),
                    HypText(
                      editions.map((work) =>
                          WorkEditions.languageName(work.sourceLanguage))
                          .toSet().join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: HypColors.muted),
                    ),
                    const SizedBox(height: 5),
                    InkWell(
                      key: Key('edition-choose-' + group),
                      onTap: onOpen,
                      child: Text(AppLocalizations.of(context)!.editionChoose,
                          style: const TextStyle(fontSize: 10)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
