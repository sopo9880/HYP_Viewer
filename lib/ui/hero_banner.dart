import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'hyp_theme.dart';

/// Functional three-slide product hero. The illustration is native Flutter
/// vector styling, not unlicensed images or a static screenshot.
class HypHeroBanner extends StatefulWidget {
  final VoidCallback onOpenLibrary;
  final VoidCallback onOpenDownloads;
  final Uint8List? artwork;

  const HypHeroBanner({
    super.key,
    required this.onOpenLibrary,
    required this.onOpenDownloads,
    this.artwork,
  });

  @override
  State<HypHeroBanner> createState() => _HypHeroBannerState();
}

class _HypHeroBannerState extends State<HypHeroBanner> {
  int _index = 0;

  static const titles = [
    '좋아하는 이야기를,\n언제 어디서나',
    '내 서재 속 이야기를,\n한 곳에서',
    '읽던 이야기의\n다음 페이지까지',
  ];
  static const descriptions = [
    '웹의 이미지 작품과 내가 가진 파일을\n더 편리하게 감상하세요.',
    '즐겨찾기와 작품 번호, 기록을\n내 기기에서 관리하세요.',
    '오프라인으로 저장한 작품은\n인터넷 없이 이어서 읽으세요.',
  ];

  void _turn(int delta) => setState(() => _index = (_index + delta + 3) % 3);

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, layout) {
        final compact = layout.maxWidth < 560;
        return Container(
          height: compact ? 235 : 240,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: HypColors.primary.withValues(alpha: 0.75)),
            boxShadow: [
              BoxShadow(
                color: HypColors.primary.withValues(alpha: 0.14),
                blurRadius: 20,
              ),
            ],
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF25204E),
                Color(0xFF171A39),
                Color(0xFF4B408B),
              ],
            ),
          ),
          child: Stack(children: [
            if (_index == 0 && widget.artwork != null) ...[
              Positioned.fill(
                child: Image.memory(widget.artwork!, fit: BoxFit.cover,
                    gaplessPlayback: true),
              ),
              // Keep the slogan and carousel controls legible on bright art.
              Positioned.fill(child: DecoratedBox(
                decoration: BoxDecoration(gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    const Color(0xFF13142A).withValues(alpha: 0.92),
                    const Color(0xFF13142A).withValues(alpha: 0.60),
                    const Color(0xFF13142A).withValues(alpha: 0.22),
                  ],
                )),
              )),
            ],
            if (_index != 0 || widget.artwork == null) Positioned(
              right: compact ? -185 : -95,
              bottom: -190,
              child: Container(
                width: 450, height: 450,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    HypColors.lightPurple.withValues(alpha: 0.45),
                    HypColors.primary.withValues(alpha: 0.13),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
            if (_index != 0 || widget.artwork == null) Positioned(
              right: compact ? -35 : 72,
              top: compact ? 38 : -20,
              child: Icon(
                Icons.auto_stories_rounded,
                size: compact ? 174 : 266,
                color: Colors.white.withValues(alpha: 0.11),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(compact ? 19 : 35, 21, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.auto_stories_rounded,
                        color: HypColors.lightPurple, size: 19),
                    const SizedBox(width: 8),
                    const Text('HYP Viewer',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 11),
                  Text(titles[_index], style: TextStyle(
                    fontSize: compact ? 23 : 31,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                  )),
                  const SizedBox(height: 9),
                  Text(descriptions[_index], style: TextStyle(
                    fontSize: compact ? 11 : 13,
                    height: 1.4,
                    color: HypColors.text.withValues(alpha: 0.86),
                  )),
                  const Spacer(),
                  Row(children: [
                    _arrow(Icons.chevron_left, '이전 소개', () => _turn(-1)),
                    const SizedBox(width: 14),
                    for (var i = 0; i < titles.length; i++)
                      GestureDetector(
                        onTap: () => setState(() => _index = i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Container(
                            height: 7, width: _index == i ? 19 : 7,
                            decoration: BoxDecoration(
                              color: _index == i
                                  ? HypColors.lightPurple : HypColors.dim,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 14),
                    _arrow(Icons.chevron_right, '다음 소개', () => _turn(1)),
                    const Spacer(),
                    if (!compact && _index != 0)
                      TextButton.icon(
                        onPressed: _index == 1
                            ? widget.onOpenLibrary : widget.onOpenDownloads,
                        iconAlignment: IconAlignment.end,
                        icon: const Icon(Icons.arrow_forward),
                        label: Text(_index == 1 ? '서재 열기' : '다운로드 보기'),
                      ),
                  ]),
                ],
              ),
            ),
          ]),
        );
      });

  Widget _arrow(IconData icon, String tooltip, VoidCallback onPressed) {
    return Material(
      color: HypColors.background.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        iconSize: 20,
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
      ),
    );
  }
}
