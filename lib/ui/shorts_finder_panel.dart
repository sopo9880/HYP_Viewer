import 'package:flutter/material.dart';

import '../core/number_extractor.dart';
import 'hyp_theme.dart';

/// The existing Shorts parser and YouTube client stay in the parent controller.
/// This panel only reorganizes their real controls into a responsive layout.
class ShortsFinderPanel extends StatefulWidget {
  final TextEditingController url;
  final TextEditingController apiKey;
  final TextEditingController comment;
  final TextEditingController workId;
  final TextEditingController title;
  final TextEditingController author;
  final List<NumberCandidate> candidates;
  final bool busy;
  final VoidCallback onAnalyze;
  final Future<void> Function() onFetch;
  final Future<void> Function() onOpenYoutube;
  final Future<void> Function() onSave;
  final Future<void> Function(List<String> codes) onSaveSelectedWorks;

  const ShortsFinderPanel({
    super.key,
    required this.url,
    required this.apiKey,
    required this.comment,
    required this.workId,
    required this.title,
    required this.author,
    required this.candidates,
    required this.busy,
    required this.onAnalyze,
    required this.onFetch,
    required this.onOpenYoutube,
    required this.onSave,
    required this.onSaveSelectedWorks,
  });

  @override
  State<ShortsFinderPanel> createState() => _ShortsFinderPanelState();
}

class _ShortsFinderPanelState extends State<ShortsFinderPanel> {
  bool _showDetails = false;
  bool _revealApiKey = false;
  final Set<String> _selectedCodes = <String>{};

  @override
  void initState() {
    super.initState();
    if (widget.candidates.length <= 2) {
      _selectedCodes.addAll(widget.candidates.map((e) => e.code));
    }
  }

  @override
  void didUpdateWidget(covariant ShortsFinderPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.candidates.map((e) => e.code).join(',');
    final after = widget.candidates.map((e) => e.code).join(',');
    if (before != after) {
      _selectedCodes.clear();
      // Two explicit entries can be registered with one click; with many
      // ambiguous candidates require the user to select them individually.
      if (widget.candidates.length <= 2) {
        _selectedCodes.addAll(widget.candidates.map((e) => e.code));
      }
      if (widget.candidates.isNotEmpty) _showDetails = true;
    }
  }

  void _search() {
    // A new Shorts URL must be fetched even if an older comment is present.
    // Manual extraction has its own button inside the details section.
    if (widget.url.text.trim().isNotEmpty) {
      setState(() => _showDetails = true);
      widget.onFetch();
    } else if (widget.comment.text.trim().isNotEmpty) {
      widget.onAnalyze();
    } else {
      setState(() => _showDetails = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showDetails = _showDetails || widget.candidates.isNotEmpty;
    return HypPanel(
      glow: true,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 51,
                height: 51,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    colors: [HypColors.primary, HypColors.lightPurple],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: HypColors.primary.withValues(alpha: 0.32),
                      blurRadius: 18,
                    ),
                  ],
                ),
                child: const Icon(Icons.link_rounded, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('쇼츠 작품 번호 찾기',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      'Shorts 링크만 붙여넣으면 공개 설명란·댓글에서 번호를 찾아봐. API 키는 필요 없어.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.smart_display_outlined,
                  size: 33, color: HypColors.border),
            ],
          ),
          const SizedBox(height: 17),
          LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 780;
            final url = TextField(
              key: const Key('shorts-url-input'),
              controller: widget.url,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: const InputDecoration(
                hintText: 'YouTube Shorts 링크 붙여넣기',
                prefixIcon: Icon(Icons.link_rounded, color: HypColors.muted),
              ),
            );
            final apiKey = TextField(
              controller: widget.apiKey,
              obscureText: !_revealApiKey,
              decoration: InputDecoration(
                hintText: '개인 YouTube Data API 키 (고급 · 선택)',
                prefixIcon: const Icon(Icons.key_outlined, color: HypColors.muted),
                suffixIcon: IconButton(
                  tooltip: _revealApiKey ? 'API 키 숨기기' : 'API 키 보기',
                  onPressed: () => setState(() => _revealApiKey = !_revealApiKey),
                  icon: Icon(_revealApiKey
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined),
                ),
              ),
            );
            final search = FilledButton.icon(
              key: const Key('shorts-search-button'),
              onPressed: widget.busy ? null : _search,
              icon: const Icon(Icons.search),
              label: const Text('작품 찾기'),
            );
            final advanced = Material(
              color: Colors.transparent,
              child: ExpansionTile(
                key: const Key('youtube-advanced-settings'),
                title: const Text('고급 설정 · 내 YouTube Data API 키 사용 (선택)'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                children: [apiKey],
              ),
            );
            if (wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(child: url),
                    const SizedBox(width: 10),
                    SizedBox(width: 150, child: search),
                  ]),
                  advanced,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                url,
                const SizedBox(height: 10),
                search,
                advanced,
              ],
            );
          }),
          const SizedBox(height: 10),
          const Text(
            '기본 조회는 API 키 없이 YouTube 공개 페이지에서 댓글을 읽어. '
            '유튜브 제한으로 실패할 수도 있어. 이때는 직접 댓글을 복사해 붙여넣어줘.',
            style: TextStyle(fontSize: 12, color: HypColors.muted),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 6, children: [
            OutlinedButton.icon(
              onPressed: widget.busy ? null : widget.onFetch,
              icon: const Icon(Icons.cloud_download_outlined, size: 19),
              label: const Text('설명란 · 댓글 자동 조회'),
            ),
            TextButton.icon(
              onPressed: widget.onOpenYoutube,
              icon: const Icon(Icons.open_in_new, size: 19),
              label: const Text('유튜브 열고 댓글 복사'),
            ),
          ]),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: () => setState(() => _showDetails = !showDetails),
            icon: Icon(showDetails
                ? Icons.keyboard_arrow_up
                : Icons.keyboard_arrow_down),
            label: Text(showDetails
                ? '댓글·번호 입력 접기'
                : '댓글 직접 입력 · 번호 확정'),
          ),
          if (widget.busy) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          AnimatedSize(
            alignment: Alignment.topCenter,
            duration: const Duration(milliseconds: 220),
            child: showDetails
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _details(context),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _details(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HypColors.background.withValues(alpha: 0.43),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HypColors.border.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('shorts-comment-input'),
            controller: widget.comment,
            minLines: 3,
            maxLines: 7,
            decoration: const InputDecoration(
              labelText: '설명란 / 댓글 원문',
              hintText: '댓글 내용을 붙여넣으면 숫자 후보를 추출할 수 있어.',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: widget.onAnalyze,
              icon: const Icon(Icons.manage_search),
              label: const Text('원문에서 번호 추출'),
            ),
          ),
          if (widget.candidates.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('추출된 후보 · 여러 작품은 체크 후 함께 저장해줘',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 7),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.candidates.take(20).map((candidate) {
                return Tooltip(
                  message: candidate.evidence,
                  child: FilterChip(
                    key: Key('shorts-candidate-' + candidate.code),
                    label: Text(candidate.code),
                    selected: _selectedCodes.contains(candidate.code),
                    avatar: const Icon(Icons.numbers, size: 15),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _selectedCodes.add(candidate.code);
                        widget.workId.text = candidate.code;
                      } else {
                        _selectedCodes.remove(candidate.code);
                      }
                    }),
                  ),
                );
              }).toList(),
            ),
            if (widget.candidates.length > 1) ...[
              const SizedBox(height: 9),
              FilledButton.icon(
                key: const Key('save-selected-works'),
                onPressed: widget.busy || _selectedCodes.isEmpty
                    ? null : () => widget.onSaveSelectedWorks(
                        widget.candidates
                            .where((e) => _selectedCodes.contains(e.code))
                            .map((e) => e.code).toList()),
                icon: const Icon(Icons.library_add_outlined),
                label: Text('선택한 작품 ${_selectedCodes.length}개 한 번에 저장'),
              ),
              const SizedBox(height: 4),
              const Text('추출된 모든 숫자가 실제 작품 번호는 아니야. '
                  '선택된 번호를 확인하고 저장해줘.',
                  style: TextStyle(fontSize: 12, color: HypColors.muted)),
            ],
          ],
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) {
            final code = TextField(
              key: const Key('confirmed-work-id'),
              controller: widget.workId,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '확정 작품 번호 *'),
            );
            final title = TextField(
              controller: widget.title,
              decoration: const InputDecoration(labelText: '작품명 (선택)',
                  helperText: '비워두면 작품 번호로 실제 제목을 조회해'),
            );
            final author = TextField(
              controller: widget.author,
              decoration: const InputDecoration(labelText: '작가 (선택)'),
            );
            if (constraints.maxWidth >= 630) {
              return Row(children: [
                Expanded(child: code),
                const SizedBox(width: 8),
                Expanded(child: title),
                const SizedBox(width: 8),
                Expanded(child: author),
              ]);
            }
            return Column(children: [
              code, const SizedBox(height: 9),
              title, const SizedBox(height: 9),
              author,
            ]);
          }),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const Key('save-work-button'),
            onPressed: widget.busy ? null : widget.onSave,
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('확정한 작품을 서재에 저장'),
          ),
          const SizedBox(height: 6),
          Text(
            '후보 번호는 자동 검증된 작품 번호가 아니야. 원문을 보고 직접 확인한 뒤 저장해줘.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
