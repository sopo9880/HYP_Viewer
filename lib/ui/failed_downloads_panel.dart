import 'package:flutter/material.dart';

import '../core/download_failure_store.dart';
import '../l10n/app_localizations.dart';
import 'hyp_theme.dart';

/// Only the terminal-failure journal is shown or cleared here.
/// Clearing entries never deletes a library work, archive or queued job.
class FailedDownloadsPanel extends StatelessWidget {
  final Map<String, FailedDownload> failedDownloads;
  final Future<void> Function(String workId)? onRetry;
  final Future<void> Function(String workId)? onDismiss;
  final Future<void> Function()? onClearAll;

  const FailedDownloadsPanel({
    super.key,
    required this.failedDownloads,
    this.onRetry,
    this.onDismiss,
    this.onClearAll,
  });

  Future<void> _confirmClearAll(BuildContext context) async {
    if (onClearAll == null || failedDownloads.isEmpty) return;
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
    if (confirmed == true && context.mounted) await onClearAll!();
  }

  @override
  Widget build(BuildContext context) {
    if (failedDownloads.isEmpty) return const SizedBox.shrink();
    final labels = AppLocalizations.of(context)!;
    return HypPanel(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 2,
          children: [
            Text(labels.downloadFailedHeading,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            if (onClearAll != null)
              TextButton.icon(
                key: const Key('clear-all-failed-downloads'),
                onPressed: () => _confirmClearAll(context),
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: Text(labels.downloadFailedClearAll),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(labels.downloadFailedHelp),
        const SizedBox(height: 8),
        for (final failed in failedDownloads.values.toList().reversed.take(25))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(child: Text(
                labels.downloadFailedDetail(failed.workId, failed.code),
                key: Key('failed-download-' + failed.workId),
              )),
              TextButton(
                key: Key('retry-failed-' + failed.workId),
                onPressed: onRetry == null ? null : () => onRetry!(failed.workId),
                child: Text(labels.downloadFailedRetry),
              ),
              if (onDismiss != null)
                IconButton(
                  key: Key('dismiss-failed-' + failed.workId),
                  tooltip: labels.downloadFailedDismiss,
                  onPressed: () => onDismiss!(failed.workId),
                  icon: const Icon(Icons.close_rounded),
                  iconSize: 19,
                ),
            ]),
          ),
      ],
    ));
  }
}
