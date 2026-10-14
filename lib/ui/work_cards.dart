import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../core/work.dart';
import 'hyp_theme.dart';
import 'cover_palettes.dart';

class HypWorkGrid extends StatelessWidget {
  final List<WorkEntry> works;
  final Set<String> offlineKeys;
  final Map<String, int> pageCounts;
  final Map<String, Uint8List> coverImages;
  final void Function(WorkEntry) onOpen;
  final void Function(String, WorkEntry) onAction;

  const HypWorkGrid({
    super.key,
    required this.works,
    required this.offlineKeys,
    required this.pageCounts,
    required this.coverImages,
    required this.onOpen,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, size) {
        final w = size.maxWidth;
        final columns = w >= 1100 ? 5 : w >= 850 ? 4 : w >= 620 ? 3 : w >= 335 ? 2 : 1;
        return GridView.builder(
          itemCount: works.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: columns == 1 ? 1.35 : 0.76,
          ),
          itemBuilder: (context, index) => HypWorkCard(
            work: works[index],
            isOffline: offlineKeys.contains(works[index].key),
            totalPages: pageCounts[works[index].key],
            coverBytes: coverImages[works[index].key],
            onOpen: () => onOpen(works[index]),
            onAction: (action) => onAction(action, works[index]),
          ),
        );
      });
}

class HypWorkCard extends StatelessWidget {
  final WorkEntry work;
  final bool isOffline;
  final int? totalPages;
  final Uint8List? coverBytes;
  final VoidCallback onOpen;
  final ValueChanged<String> onAction;

  const HypWorkCard({
    super.key,
    required this.work,
    required this.isOffline,
    required this.totalPages,
    required this.coverBytes,
    required this.onOpen,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final progress = work.completed
        ? 1.0
        : totalPages != null && totalPages! > 0
            ? (work.currentPage / totalPages!).clamp(0.0, 1.0).toDouble()
            : null;
    return Material(
      color: HypColors.surface,
      borderRadius: BorderRadius.circular(15),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('work-' + work.key),
        onTap: onOpen,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: HypColors.border.withValues(alpha: 0.65)),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Stack(fit: StackFit.expand, children: [
                _cover(),
                if (isOffline)
                  const Positioned(
                    left: 8, top: 8,
                    child: Icon(Icons.offline_pin_rounded,
                        color: HypColors.success, size: 20),
                  ),
                if (progress != null)
                  Positioned(
                    right: 8, top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: HypColors.background.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        (progress * 100).round().toString() + '%',
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 5, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(
                  work.title.isEmpty ? '작품 ' + work.workId : work.title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  work.author.isNotEmpty
                      ? '작가 ' + work.author
                      : '번호 ' + work.workId,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: HypColors.muted),
                ),
                const SizedBox(height: 2),
                Row(children: [
                  Expanded(
                    child: Text(
                      work.completed
                          ? '완독'
                          : totalPages != null
                              ? work.currentPage.toString() + ' / ' +
                                  totalPages.toString() + ' 페이지'
                              : work.currentPage.toString() + '페이지부터',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  SizedBox(
                    width: 27, height: 25,
                    child: PopupMenuButton<String>(
                      tooltip: '작품 메뉴',
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.more_vert_rounded,
                          color: HypColors.muted, size: 19),
                      onSelected: onAction,
                      itemBuilder: (_) => [
                        if (isOffline)
                          const PopupMenuItem(
                              value: 'offline', child: Text('오프라인 읽기')),
                        const PopupMenuItem(
                            value: 'online', child: Text('앱 내 온라인 읽기')),
                        const PopupMenuItem(
                            value: 'page', child: Text('웹 리더 · 시작 페이지 선택')),
                        const PopupMenuItem(
                            value: 'download', child: Text('온라인 작품 오프라인 저장')),
                        const PopupMenuItem(
                            value: 'download_json', child: Text('추가 JSON 소스 다운로드')),
                        if (isOffline)
                          const PopupMenuItem(
                            value: 'delete_offline', child: Text('오프라인 파일 삭제')),
                        const PopupMenuItem(
                            value: 'import', child: Text('CBZ/ZIP 연결')),
                        const PopupMenuItem(
                            value: 'cover', child: Text('표지 선택')), 
                        PopupMenuItem(
                          value: 'favorite',
                          child: Text(work.favorite
                              ? '즐겨찾기 해제' : '즐겨찾기'),
                        ),
                        if (work.videoUrl.isNotEmpty)
                          const PopupMenuItem(
                              value: 'original', child: Text('원본 쇼츠')),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 2),
                if (progress != null)
                  LinearProgressIndicator(
                    minHeight: 4,
                    value: progress,
                    backgroundColor: HypColors.border,
                    borderRadius: BorderRadius.circular(6),
                    color: HypColors.lightPurple,
                  )
                else
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: HypColors.border.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _cover() {
    if (coverBytes != null && work.coverMode != 'preset') {
      return Image.memory(coverBytes!, fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _fallbackCover());
    }
    return _fallbackCover();
  }

  Widget _fallbackCover() {
    final seed = work.workId.codeUnits.fold<int>(0, (a, b) => a + b);
    final paletteIndex = work.coverMode == 'preset'
        ? work.coverPreset.clamp(0, 5).toInt()
        : seed % CoverPalettes.colors.length;
    final palette = CoverPalettes.colors[paletteIndex];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: palette,
        ),
      ),
      child: Stack(children: [
        Center(child: Icon(CoverPalettes.symbols[paletteIndex], size: 54,
            color: Colors.white.withValues(alpha: 0.23))),
        if (work.favorite)
          const Positioned(top: 8, left: 8,
              child: Icon(Icons.favorite, color: HypColors.lightPurple, size: 18)),
        Positioned(
          bottom: 9, left: 10, right: 10,
          child: Text(work.title.isEmpty ? 'HYP Viewer' : work.title,
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.86),
                fontWeight: FontWeight.w600, fontSize: 11,
              )),
        ),
      ]),
    );
  }
}
