import 'dart:typed_data';
import '../core/i18n.dart';
import 'package:flutter/material.dart';
import '../core/work.dart';
import '../core/work_editions.dart';
import 'hyp_theme.dart';

/// One visual card for several translations of the same chapter.
class HypWorkEditionCard extends StatelessWidget {
  final List<WorkEntry> editions;
  final Map<String, Uint8List> coverImages;
  final VoidCallback onOpen;
  const HypWorkEditionCard({
    super.key, required this.editions, required this.coverImages,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final covers = editions.take(3).toList();
    final title = editions.first.title.split('|').first.trim();
    return Material(
      color: HypColors.surface,
      borderRadius: BorderRadius.circular(15),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('edition-stack-' + editions.first.editionGroupId),
        onTap: onOpen,
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(15),
              border: Border.all(color: HypColors.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: Stack(fit: StackFit.expand, children: [
                for (var i = covers.length - 1; i >= 0; i--)
                  Positioned.fill(
                    left: i * 5.0, top: i * 5.0,
                    right: (covers.length - 1 - i) * 5.0,
                    bottom: (covers.length - 1 - i) * 5.0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: HypColors.raised,
                        border: Border.all(color: HypColors.border,
                            width: 2),
                        borderRadius: BorderRadius.circular(8)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: coverImages[covers[i].key] == null
                          ? const Icon(Icons.menu_book_outlined, size: 48)
                          : Image.memory(coverImages[covers[i].key]!,
                              fit: BoxFit.contain),
                      ),
                    ),
                  ),
                Positioned(top: 9, right: 9,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: HypColors.background,
                        borderRadius: BorderRadius.circular(12)),
                    child: Padding(padding: const EdgeInsets.all(5),
                      child: HypText(editions.length.toString() + '개 언어판',
                        style: const TextStyle(fontSize: 11)))),
              ])),
              Padding(padding: const EdgeInsets.fromLTRB(9, 9, 9, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HypText(title.isEmpty ? editions.first.workId : title,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    HypText(editions.map((work) =>
                        WorkEditions.languageName(work.sourceLanguage))
                          .toSet().join(' · '),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11,
                            color: HypColors.muted)),
                    const SizedBox(height: 5),
                    const LinearProgressIndicator(value: 0, minHeight: 4),
                  ])),
            ]),
        ),
      ),
    );
  }
}
