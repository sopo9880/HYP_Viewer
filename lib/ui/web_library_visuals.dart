import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/web_viewer_store.dart';
import '../l10n/app_localizations.dart';
import 'cover_palettes.dart';
import 'hyp_theme.dart';

enum WebVisualSort { newest, title, progress }

/// Non-destructive presentation metadata. HYP, WEB and SERIES continue to
/// own their original archive and reader implementations.
class WebVisualEntry {
  final String id;
  final String title;
  final String subtitle;
  final String detail;
  final String? coverWorkId;
  final String? remoteCoverUrl;
  final DateTime modifiedAt;
  final double progress;
  final bool downloaded;
  final IconData icon;
  final VoidCallback onOpen;
  final Map<String, String> actions;
  final ValueChanged<String>? onAction;

  const WebVisualEntry({
    required this.id, required this.title, required this.subtitle,
    required this.detail, required this.modifiedAt,
    required this.progress, required this.downloaded,
    required this.icon, required this.onOpen,
    this.coverWorkId, this.remoteCoverUrl,
    this.actions = const {}, this.onAction,
  });
}

/// The same first-page cover used for both WEB standalone books and SERIES
/// grouped chapters. WEB-owned CBZ bytes are never copied into HYP's store.
class WebCoverPreview extends StatelessWidget {
  final WebViewerStore store;
  final String title;
  final String? coverWorkId;
  final String? remoteCoverUrl;
  final IconData fallbackIcon;
  const WebCoverPreview({
    super.key, required this.store, required this.title,
    required this.fallbackIcon, this.coverWorkId, this.remoteCoverUrl,
  });

  Widget _fallback() {
    final seed = title.codeUnits.fold<int>(0, (a, b) => a + b);
    final palette = seed % CoverPalettes.colors.length;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: CoverPalettes.colors[palette],
      )),
      child: Stack(children: [
        Center(child: Icon(fallbackIcon, size: 58,
          color: Colors.white.withValues(alpha: 0.25))),
        Positioned(left: 12, right: 12, bottom: 12, child: Text(
          title, maxLines: 3, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white,
            fontSize: 12, fontWeight: FontWeight.w700),
        )),
      ]),
    );
  }

  Widget _content(Uint8List? cover) {
    if (cover != null) {
      return Image.memory(cover, fit: BoxFit.cover, cacheWidth: 480,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => _fallback());
    }
    final uri = WebViewerStore.safeUrl(remoteCoverUrl ?? '');
    if (uri != null) {
      return Image.network(uri.toString(), fit: BoxFit.cover,
        cacheWidth: 480,
        errorBuilder: (context, error, stackTrace) => _fallback());
    }
    return _fallback();
  }

  @override
  Widget build(BuildContext context) {
    if (coverWorkId == null) return _content(null);
    return FutureBuilder<Uint8List?>(
      future: store.coverFor(coverWorkId!),
      builder: (_, result) => _content(result.data),
    );
  }
}

class WebVisualCard extends StatelessWidget {
  final WebViewerStore store;
  final WebVisualEntry entry;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onSelect;
  final VoidCallback? onLongPress;
  const WebVisualCard({
    super.key, required this.store, required this.entry,
    this.selectionMode = false, this.selected = false,
    this.onSelect, this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final p = entry.progress.clamp(0.0, 1.0).toDouble();
    return Material(
      color: HypColors.surface,
      borderRadius: BorderRadius.circular(15),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('web-visual-card-' + entry.id),
        onTap: selectionMode ? onSelect : entry.onOpen,
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              width: selectionMode && selected ? 2 : 1,
              color: selectionMode && selected
                  ? HypColors.lightPurple
                  : HypColors.border.withValues(alpha: 0.7)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: Stack(fit: StackFit.expand, children: [
                WebCoverPreview(
                  store: store, title: entry.title,
                  coverWorkId: entry.coverWorkId,
                  remoteCoverUrl: entry.remoteCoverUrl,
                  fallbackIcon: entry.icon,
                ),
                if (selectionMode)
                  Positioned(left: 8, top: 8,
                    child: Icon(selected ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                      color: selected ? HypColors.lightPurple : Colors.white,
                      size: 26)),
                if (entry.downloaded && !selectionMode)
                  const Positioned(left: 8, top: 8,
                    child: Icon(Icons.offline_pin_rounded,
                      color: HypColors.success, size: 20)),
                Positioned(right: 8, top: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: HypColors.background.withValues(alpha: 0.84),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      child: Text((p * 100).round().toString() + '%',
                        style: const TextStyle(fontSize: 11,
                          color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                  )),
              ])),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 7, 9),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(entry.title, maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(entry.subtitle, maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11,
                        color: HypColors.muted)),
                    Row(children: [
                      Expanded(child: Text(entry.detail, maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11,
                          color: HypColors.muted))),
                      if (entry.actions.isNotEmpty)
                        SizedBox(width: 30, height: 30,
                          child: PopupMenuButton<String>(
                            tooltip: entry.title,
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.more_vert,
                              color: HypColors.muted, size: 20),
                            onSelected: entry.onAction,
                            itemBuilder: (_) => entry.actions.entries.map(
                              (action) => PopupMenuItem<String>(
                                value: action.key,
                                child: Text(action.value),
                              )).toList(),
                          )),
                    ]),
                    LinearProgressIndicator(
                      minHeight: 4,
                      value: p,
                      backgroundColor: HypColors.border,
                      borderRadius: BorderRadius.circular(6),
                      color: HypColors.lightPurple,
                    ),
                  ],
                )),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reusable responsive cover shelf with the same breakpoints and palettes
/// as HypWorkGrid. A visible-page cap prevents decoding hundreds of CBZs.
class WebVisualLibrary extends StatefulWidget {
  final WebViewerStore store;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<WebVisualEntry> items;
  final bool searchable;
  final int initialVisible;
  final VoidCallback? onViewAll;
  final String emptyMessage;
  final Future<void> Function(List<WebVisualEntry>)? onDeleteSelected;

  const WebVisualLibrary({
    super.key, required this.store, required this.title,
    required this.subtitle, required this.icon, required this.items,
    required this.emptyMessage, this.searchable = true,
    this.initialVisible = 36, this.onViewAll,
    this.onDeleteSelected,
  });

  @override
  State<WebVisualLibrary> createState() => _WebVisualLibraryState();
}

class _WebVisualLibraryState extends State<WebVisualLibrary> {
  String _query = '';
  WebVisualSort _sort = WebVisualSort.newest;
  int _visible = 36;
  bool _reverse = false;
  bool _selecting = false;
  final Set<String> _selectedIds = {};

  void _toggleSelection() => setState(() {
    _selecting = !_selecting;
    _selectedIds.clear();
  });

  void _toggleSelected(String id) => setState(() {
    if (!_selectedIds.add(id)) _selectedIds.remove(id);
  });

  Future<void> _deleteSelected() async {
    final action = widget.onDeleteSelected;
    if (action == null || _selectedIds.isEmpty) return;
    final selected = widget.items.where((entry) =>
        _selectedIds.contains(entry.id)).toList();
    await action(selected);
    if (mounted) setState(() {
      _selectedIds.clear();
      _selecting = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _visible = widget.initialVisible;
  }

  @override
  void didUpdateWidget(covariant WebVisualLibrary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialVisible != oldWidget.initialVisible) {
      _visible = widget.initialVisible;
    }
  }

  List<WebVisualEntry> _filtered() {
    final query = _query.trim().toLowerCase();
    final entries = widget.items.where((item) => query.isEmpty ||
        item.title.toLowerCase().contains(query) ||
        item.subtitle.toLowerCase().contains(query)).toList();
    entries.sort((a, b) => switch (_sort) {
      WebVisualSort.newest => b.modifiedAt.compareTo(a.modifiedAt),
      WebVisualSort.title => a.title.toLowerCase()
          .compareTo(b.title.toLowerCase()),
      WebVisualSort.progress => b.progress.compareTo(a.progress),
    });
    return _reverse ? entries.reversed.toList() : entries;
  }

  @override
  Widget build(BuildContext context) {
    final labels = AppLocalizations.of(context)!;
    final all = _filtered();
    final shown = all.take(_visible).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HypSectionTitle(
          icon: widget.icon,
          title: widget.title,
          subtitle: widget.subtitle,
          actionLabel: widget.onViewAll == null
              ? null : labels.webVisualViewAll,
          onAction: widget.onViewAll,
        ),
        const SizedBox(height: 13),
        if (widget.onDeleteSelected != null) ...[
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              key: const Key('web-library-select-mode'),
              onPressed: _toggleSelection,
              icon: Icon(_selecting ? Icons.close : Icons.checklist_outlined),
              label: Text(_selecting ? '선택 종료' : '선택'),
            ),
            if (_selecting) ...[
              OutlinedButton.icon(
                onPressed: () => setState(() => _selectedIds
                  ..clear()..addAll(all.map((e) => e.id))),
                icon: const Icon(Icons.select_all),
                label: const Text('전체 선택'),
              ),
              FilledButton.icon(
                onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
                icon: const Icon(Icons.delete_outline),
                label: Text('선택 삭제 (${_selectedIds.length})'),
              ),
            ],
          ]),
          const SizedBox(height: 12),
        ],
        if (widget.searchable) ...[
          LayoutBuilder(builder: (context, constraints) {
            final field = TextField(
              key: const Key('web-visual-library-search'),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: labels.webVisualSearch,
              ),
              onChanged: (v) => setState(() {
                _query = v;
                _visible = widget.initialVisible;
              }),
            );
            final sort = DropdownButton<WebVisualSort>(
              key: const Key('web-visual-library-sort'),
              value: _sort,
              items: [
                DropdownMenuItem(value: WebVisualSort.newest,
                  child: Text(labels.webVisualSortNewest)),
                DropdownMenuItem(value: WebVisualSort.title,
                  child: Text(labels.webVisualSortTitle)),
                DropdownMenuItem(value: WebVisualSort.progress,
                  child: Text(labels.webVisualSortProgress)),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _sort = v);
              },
            );
            if (constraints.maxWidth < 520) {
              return Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [field, const SizedBox(height: 6),
                  Row(children: [sort, IconButton(
                    tooltip: '정렬 방향 변경',
                    onPressed: () => setState(() => _reverse = !_reverse),
                    icon: Icon(_reverse ? Icons.arrow_upward : Icons.arrow_downward),
                  )])]);
            }
            return Row(children: [
              Expanded(child: field),
              const SizedBox(width: 14),
              sort,
              IconButton(
                tooltip: '정렬 방향 변경',
                onPressed: () => setState(() => _reverse = !_reverse),
                icon: Icon(_reverse ? Icons.arrow_upward : Icons.arrow_downward),
              ),
            ]);
          }),
          const SizedBox(height: 15),
        ],
        if (all.isEmpty)
          HypEmptyState(
            icon: widget.icon,
            title: widget.title,
            message: widget.emptyMessage,
          )
        else
          LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = width >= 1100 ? 5 :
                width >= 850 ? 4 : width >= 620 ? 3 :
                width >= 335 ? 2 : 1;
            return GridView.builder(
              key: const Key('web-visual-cover-grid'),
              itemCount: shown.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 12, mainAxisSpacing: 12,
                childAspectRatio: columns == 1 ? 1.15 : 0.68,
              ),
              itemBuilder: (context, index) => WebVisualCard(
                store: widget.store, entry: shown[index],
                selectionMode: _selecting,
                selected: _selectedIds.contains(shown[index].id),
                onSelect: () => _toggleSelected(shown[index].id),
                onLongPress: widget.onDeleteSelected == null ? null : () {
                  if (!_selecting) setState(() => _selecting = true);
                  _toggleSelected(shown[index].id);
                }),
            );
          }),
        if (all.length > shown.length)
          Align(alignment: Alignment.center,
            child: TextButton.icon(
              onPressed: () => setState(() => _visible += 36),
              icon: const Icon(Icons.expand_more),
              label: Text(labels.webVisualShowMore),
            )),
      ],
    );
  }
}
