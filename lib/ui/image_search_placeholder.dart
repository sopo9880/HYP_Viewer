import 'package:flutter/material.dart';
import '../core/i18n.dart';

/// Intentionally inactive until image identification can be verified safely.
/// Instagram/YouTube caption and comment extraction remains independent.
class ImageSearchPlaceholder extends StatelessWidget {
  const ImageSearchPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const HypText('이미지로 작품 찾기')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.image_search_outlined, size: 82,
                    color: colors.onSurfaceVariant),
                const SizedBox(height: 24),
                HypText('이미지로 작품 찾기',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                const HypText(
                  '이미지 검색은 준비 중이야. 이번 버전에서는 이미지 검색을 실행하지 않아.',
                  textAlign: TextAlign.center),
                const SizedBox(height: 9),
                const HypText(
                  '이미지 공유·업로드 파일은 아직 분석하지 않아. 서재와 링크 분석은 그대로 사용할 수 있어.',
                  textAlign: TextAlign.center),
                const SizedBox(height: 25),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                  label: const HypText('닫기'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
