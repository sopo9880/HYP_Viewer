import 'package:flutter/material.dart';

import '../core/web_viewer_store.dart';
import '../l10n/app_localizations.dart';
import 'hyp_theme.dart';

/// Shared searchable history sheet for the WEB and SERIES browsers.
/// Old entries without a timestamp remain readable and are never fabricated.
class WebVisitHistorySheet extends StatefulWidget {
  final WebViewerStore store;
  const WebVisitHistorySheet({super.key, required this.store});

  static Future<String?> open(BuildContext context, WebViewerStore store) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(child: SizedBox(
        height: MediaQuery.sizeOf(sheet).height * 0.78,
        child: WebVisitHistorySheet(store: store),
      )),
    );

  @override
  State<WebVisitHistorySheet> createState() => _WebVisitHistorySheetState();
}

class _WebVisitHistorySheetState extends State<WebVisitHistorySheet> {
  String _query = '';

  String _date(DateTime? time) {
    if (time == null) return '';
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _clearAll() async {
    final labels = AppLocalizations.of(context)!;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(labels.webVisitClearAllTitle),
        content: Text(labels.webVisitClearAllHelp),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
            child: Text(labels.cancel)),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
            child: Text(labels.webVisitClearAll)),
        ],
      ),
    );
    if (accepted != true) return;
    await widget.store.clearRecentPages();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final labels = AppLocalizations.of(context)!;
    final term = _query.trim().toLowerCase();
    final pages = widget.store.recentPages.where((page) =>
      term.isEmpty || page.name.toLowerCase().contains(term) ||
      page.url.toLowerCase().contains(term)).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(children: [
          const Icon(Icons.history_rounded),
          const SizedBox(width: 9),
          Expanded(child: Text(labels.webViewerRecentTabs,
            style: Theme.of(context).textTheme.titleLarge)),
          if (widget.store.recentPages.isNotEmpty)
            TextButton.icon(
              onPressed: _clearAll,
              icon: const Icon(Icons.delete_sweep_outlined),
              label: Text(labels.webVisitClearAll),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: TextField(
          key: const Key('web-history-search'),
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: labels.webVisitSearch,
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
      ),
      Expanded(child: pages.isEmpty
        ? Center(child: Text(term.isEmpty
            ? labels.webViewerNoRecentTabs : labels.webVisitNoSearchResults))
        : ListView.separated(
            itemCount: pages.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = pages[index];
              return ListTile(
                key: Key('web-history-entry-' + index.toString()),
                leading: const Icon(Icons.public, color: HypColors.muted),
                title: Text(item.name, maxLines: 1,
                  overflow: TextOverflow.ellipsis),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.url, maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                    if (item.visitedAt != null)
                      Text(_date(item.visitedAt),
                        style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
                onTap: () => Navigator.pop(context, item.url),
                trailing: IconButton(
                  tooltip: labels.webVisitDelete,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await widget.store.removeRecentPage(item.url);
                    if (mounted) setState(() {});
                  },
                ),
              );
            },
          )),
    ]);
  }
}
