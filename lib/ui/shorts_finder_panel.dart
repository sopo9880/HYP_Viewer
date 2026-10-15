import 'package:flutter/material.dart';
import '../core/i18n.dart';
import '../l10n/app_localizations.dart';

import '../core/number_extractor.dart';
import 'candidate_editor.dart';
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
  final int clearEpoch;
  final VoidCallback? onClear;
  final VoidCallback onAnalyze;
  final Future<void> Function() onFetch;
  final Future<void> Function() onOpenYoutube;
  final Future<void> Function() onSave;
  final Future<void> Function(String code)? onQuickAddNumber;
  final Future<void> Function(List<String> codes) onSaveSelectedWorks;
  final CandidateBatchVerify? onVerifyCandidateCodes;
  final List<NumberCandidate> Function()? onCrossLineFallback;

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
    this.clearEpoch = 0,
    this.onClear,
    required this.onAnalyze,
    required this.onFetch,
    required this.onOpenYoutube,
    required this.onSave,
    this.onQuickAddNumber,
    required this.onSaveSelectedWorks,
    this.onVerifyCandidateCodes,
    this.onCrossLineFallback,
  });

  @override
  State<ShortsFinderPanel> createState() => _ShortsFinderPanelState();
}

class _ShortsFinderPanelState extends State<ShortsFinderPanel> {
  bool _showDetails = false;
  bool _userCollapsed = false;

  @override
  void initState() {
    super.initState();
    _showDetails = widget.candidates.isNotEmpty;
  }

  bool _revealApiKey = false;
  final GlobalKey _quickCandidateAnchor = GlobalKey();
  final GlobalKey<CandidateEditorState> _editorKey =
      GlobalKey<CandidateEditorState>();

  @override
  void didUpdateWidget(covariant ShortsFinderPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.clearEpoch != oldWidget.clearEpoch) {
      _showDetails = false;
      _userCollapsed = false;
      return;
    }
    final before = oldWidget.candidates.map((e) => e.code).join(',');
    final after = widget.candidates.map((e) => e.code).join(',');
    if (before != after) {
      if (widget.candidates.isNotEmpty && !_userCollapsed) {
        _showDetails = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final anchor = _quickCandidateAnchor.currentContext;
          if (anchor != null && mounted) {
            Scrollable.ensureVisible(anchor,
              duration: const Duration(milliseconds: 180),
              alignment: 0.20,
              alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
          }
        });
      }
    }
  }

  void _search() {
    // A new Shorts URL must be fetched even if an older comment is present.
    // Manual extraction has its own button inside the details section.
    final input = widget.url.text.trim();
    final workNumber = RegExp(r'^\d{1,12}$');
    if (workNumber.hasMatch(input) && widget.onQuickAddNumber != null) {
      widget.onQuickAddNumber!(input);
    } else if (input.isNotEmpty) {
      setState(() { _showDetails = true; _userCollapsed = false; });
      widget.onFetch();
    } else if (workNumber.hasMatch(widget.workId.text.trim()) &&
        widget.comment.text.trim().isEmpty &&
        widget.onQuickAddNumber != null) {
      widget.onQuickAddNumber!(widget.workId.text.trim());
    } else if (widget.comment.text.trim().isNotEmpty) {
      widget.onAnalyze();
    } else {
      setState(() => _showDetails = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showDetails = _showDetails;
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
                    HypText('링크로 작품 찾기',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    HypText(
                      'YouTube·Instagram·Hitomi 링크나 공유 텍스트에서 작품 번호를 찾아봐.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(key: const Key('finder-clear'),
                tooltip: HypI18n.t(context, '비우기'),
                onPressed: widget.busy || widget.onClear == null ? null : () {
                  widget.onClear!();
                  setState(() { _showDetails = false; _userCollapsed = false; });
                }, icon: const Icon(Icons.cleaning_services_outlined)),
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
              decoration: InputDecoration(
                hintText: HypI18n.t(context, '링크 또는 작품 번호 입력 (여러 링크 가능)'),
                prefixIcon: Icon(Icons.link_rounded, color: HypColors.muted),
              ),
            );
            final apiKey = TextField(
              controller: widget.apiKey,
              obscureText: !_revealApiKey,
              decoration: InputDecoration(
                hintText: HypI18n.t(context, '개인 YouTube Data API 키 (고급 · 선택)'),
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
              label: const HypText('작품 찾기'),
            );
            final advanced = Material(
              color: Colors.transparent,
              child: ExpansionTile(
                key: const Key('youtube-advanced-settings'),
                title: const HypText('고급 설정 · 내 YouTube Data API 키 사용 (선택)'),
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
          if (widget.candidates.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              key: _quickCandidateAnchor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppLocalizations.of(context)!.shortsCandidateCount(widget.candidates.length),
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 7),
                  SizedBox(
                    height: 42,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: widget.candidates.take(20).map((candidate) =>
                        Padding(
                          padding: const EdgeInsets.only(right: 7),
                          child: ActionChip(
                            key: Key('shorts-quick-candidate-${candidate.code}'),
                            avatar: const Icon(Icons.tag, size: 15),
                            label: HypText('#${candidate.code}'),
                            onPressed: () {
                              widget.workId.text = candidate.code;
                              setState(() => _showDetails = true);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _editorKey.currentState?.addSuggestion(candidate);
                              });
                            },
                          ),
                        ),
                      ).toList(),
                    ),
                  ),
                  const HypText('후보를 누르면 번호가 입력돼. 아래에서 확인 후 저장해줘.',
                      style: TextStyle(fontSize: 12, color: HypColors.muted)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          const HypText(
            '기본 조회는 API 키 없이 YouTube 공개 페이지에서 댓글을 읽어. '
            '유튜브 제한으로 실패할 수도 있어. 이때는 직접 댓글을 복사해 붙여넣어줘.',
            style: TextStyle(fontSize: 12, color: HypColors.muted),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 6, children: [
            OutlinedButton.icon(
              onPressed: widget.busy ? null : widget.onFetch,
              icon: const Icon(Icons.cloud_download_outlined, size: 19),
              label: const HypText('설명란 · 댓글 자동 조회'),
            ),
            TextButton.icon(
              onPressed: widget.onOpenYoutube,
              icon: const Icon(Icons.open_in_new, size: 19),
              label: const HypText('원본 링크 열고 내용 복사'),
            ),
          ]),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: () => setState(() {
              _showDetails = !showDetails;
              _userCollapsed = !_showDetails;
            }),
            icon: Icon(showDetails
                ? Icons.keyboard_arrow_up
                : Icons.keyboard_arrow_down),
            label: HypText(showDetails
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
            decoration: InputDecoration(
              labelText: HypI18n.t(context, '설명란 / 댓글 원문'),
              hintText: HypI18n.t(context, '댓글 내용을 붙여넣으면 숫자 후보를 추출할 수 있어.'),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: widget.onAnalyze,
              icon: const Icon(Icons.manage_search),
              label: const HypText('원문에서 번호 추출'),
            ),
          ),
          const SizedBox(height: 10),
          CandidateEditor(
            key: _editorKey,
            suggestions: widget.candidates,
            onVerify: widget.onVerifyCandidateCodes,
            onCrossLineFallback: widget.onCrossLineFallback,
            onSave: widget.onSaveSelectedWorks,
            busy: widget.busy,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) {
            final code = TextField(
              key: const Key('confirmed-work-id'),
              controller: widget.workId,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: HypI18n.t(context, '확정 작품 번호 *')),
            );
            final title = TextField(
              controller: widget.title,
              decoration: InputDecoration(labelText: HypI18n.t(context, '작품명 (선택)'),
                  helperText: HypI18n.t(context, '비워두면 작품 번호로 실제 제목을 조회해')),
            );
            final author = TextField(
              controller: widget.author,
              decoration: InputDecoration(labelText: HypI18n.t(context, '작가 (선택)')),
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
            label: const HypText('확정한 작품을 서재에 저장'),
          ),
          const SizedBox(height: 6),
          HypText(
            '후보 번호는 자동 검증된 작품 번호가 아니야. 원문을 보고 직접 확인한 뒤 저장해줘.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
