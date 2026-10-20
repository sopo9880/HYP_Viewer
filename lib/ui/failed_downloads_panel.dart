import 'package:flutter/material.dart';

import '../core/download_failure_store.dart';
import '../l10n/app_localizations.dart';
import 'hyp_theme.dart';

/// Only the terminal-failure journal is shown or cleared here.
/// Clearing entries never deletes a library work, archive or queued job.
class FailedDownloadsPanel extends StatefulWidget {
  @override
  State<FailedDownloadsPanel> createState() => _FailedDownloadsPanelState();
  final Map<String, FailedDownload> failedDownloads;
  final Future<void> Function(String workId)? onRetry;
  final Future<void> Function(String workId)? onDismiss;
  final Future<void> Function()? onClearAll;
  final Future<void> Function()? onRetryAll;

  const FailedDownloadsPanel({
    super.key,
    required this.failedDownloads,
    this.onRetry,
    this.onDismiss,
    this.onClearAll,
    this.onRetryAll,
  });

}

class _FailedDownloadsPanelState extends State<FailedDownloadsPanel> {
  bool _expanded = false;
  bool _retrying = false;

  Future<void> _confirmRetryAll(BuildContext context) async {
    if (_retrying || widget.onRetryAll == null || widget.failedDownloads.isEmpty) return;
    final labels = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: Text(labels.downloadRetryAll),
        content: Text(labels.downloadRetryAllConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel)),
          FilledButton(key: const Key('confirm-retry-all-failed-downloads'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(labels.downloadRetryAll)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _retrying = true);
    try { await widget.onRetryAll!(); }
    finally { if (mounted) setState(() => _retrying = false); }
  }

  Future<void> _confirmClearAll(BuildContext context) async {
    if (widget.onClearAll == null || widget.failedDownloads.isEmpty) return;
    final labels = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(labels.downloadFailedClearAll),
        content: Text(labels.downloadFailedClearAllConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(MaterialLocalizations.of(dialogContext).cancelButtonLabel),
          ),
          FilledButton(
            key: const Key('confirm-clear-all-failed-downloads'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(labels.downloadFailedClearAll),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) await widget.onClearAll!();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.failedDownloads.isEmpty) return const SizedBox.shrink();
    final labels = AppLocalizations.of(context)!;
    return HypPanel(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 2,
          children: [
            Text('${labels.downloadFailedHeading} (${widget.failedDownloads.length})',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            IconButton(
              key: const Key('toggle-failed-downloads'),
              tooltip: _expanded ? labels.downloadFailedCollapse : labels.downloadFailedExpand,
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            ),
            if (widget.onRetryAll != null)
              TextButton.icon(
                key: const Key('retry-all-failed-downloads'),
                onPressed: _retrying ? null : () => _confirmRetryAll(context),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(labels.downloadRetryAll),
              ),
            if (widget.onClearAll != null)
              TextButton.icon(
                key: const Key('clear-all-failed-downloads'),
                onPressed: () => _confirmClearAll(context),
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: Text(labels.downloadFailedClearAll),
              ),
          ],
        ),
        if (_expanded) ...[
        const SizedBox(height: 6),
        Text(labels.downloadFailedHelp),
        const SizedBox(height: 8),
        for (final failed in widget.failedDownloads.values.toList().reversed.take(25))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(child: Text(
                labels.downloadFailedDetail(failed.workId, failed.code),
                key: Key('failed-download-' + failed.workId),
              )),
              TextButton(
                key: Key('retry-failed-' + failed.workId),
                onPressed: widget.onRetry == null ? null : () => widget.onRetry!(failed.workId),
                child: Text(labels.downloadFailedRetry),
              ),
              if (widget.onDismiss != null)
                IconButton(
                  key: Key('dismiss-failed-' + failed.workId),
                  tooltip: labels.downloadFailedDismiss,
                  onPressed: () => widget.onDismiss!(failed.workId),
                  icon: const Icon(Icons.close_rounded),
                  iconSize: 19,
                ),
            ]),
          ),
        ],
      ],
    ));
  }
}
