import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/update_apk_cleanup.dart';
import '../l10n/app_localizations.dart';
import 'hyp_theme.dart';

/// The HYP, WEB and SERIES settings share this panel. The scan is confined to
/// this app's private hyp_updates directory, not the public Downloads folder.
class UpdateApkCleanupPanel extends StatefulWidget {
  final bool downloadInProgress;
  const UpdateApkCleanupPanel({
    super.key, this.downloadInProgress = false,
  });

  @override
  State<UpdateApkCleanupPanel> createState() => _UpdateApkCleanupPanelState();
}

class _UpdateApkCleanupPanelState extends State<UpdateApkCleanupPanel> {
  final UpdateApkCleanup _cleanup = const UpdateApkCleanup();
  Future<UpdateApkInventory>? _scan;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) _scan = _cleanup.scan();
  }

  void _refresh() {
    setState(() => _scan = _cleanup.scan());
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return bytes.toString() + ' B';
    if (bytes < 1024 * 1024) {
      return (bytes / 1024).toStringAsFixed(1) + ' KiB';
    }
    return (bytes / (1024 * 1024)).toStringAsFixed(1) + ' MiB';
  }

  Future<void> _remove(UpdateApkInventory found) async {
    if (_busy || widget.downloadInProgress || found.count == 0) return;
    final labels = AppLocalizations.of(context)!;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(labels.updateApkCleanupTitle),
        content: Text(
          labels.updateApkCleanupConfirm + '\n\n' +
          labels.updateApkFiles + ': ' + found.count.toString() +
          ' · ' + formatBytes(found.bytes),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(labels.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(labels.updateApkCleanupAction),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted || widget.downloadInProgress) return;
    setState(() => _busy = true);
    try {
      // Never trust a hard-coded target version as proof of installation.
      final installed = (await PackageInfo.fromPlatform()).version;
      final result = await _cleanup.cleanup(
        installedVersion: installed,
        downloadInProgress: widget.downloadInProgress,
      );
      if (!mounted) return;
      final status = result.blocked
          ? labels.updateApkCleanupBlocked
          : result.failed > 0
              ? labels.updateApkCleanupFailed
              : labels.updateApkCleanupDone + ': ' +
                  result.removed.toString() + ' · ' +
                  formatBytes(result.bytes);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(status)),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) return const SizedBox.shrink();
    final labels = AppLocalizations.of(context)!;
    return HypPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.cleaning_services_outlined,
              color: HypColors.lightPurple),
            const SizedBox(width: 10),
            Expanded(child: Text(labels.updateApkCleanupTitle,
              style: Theme.of(context).textTheme.titleMedium)),
            IconButton(
              key: const Key('update-apk-refresh'),
              tooltip: labels.updateApkCleanupScan,
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ]),
          const SizedBox(height: 6),
          Text(labels.updateApkCleanupHelp,
            style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          FutureBuilder<UpdateApkInventory>(
            future: _scan,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(snapshot.error.toString());
              }
              if (!snapshot.hasData) {
                return const LinearProgressIndicator();
              }
              final found = snapshot.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    Chip(label: Text(labels.updateApkFiles + ': ' +
                      found.count.toString())),
                    Chip(label: Text(labels.updateApkSize + ': ' +
                      formatBytes(found.bytes))),
                  ]),
                  const SizedBox(height: 10),
                  if (found.count == 0)
                    Text(labels.updateApkNoFiles,
                      style: Theme.of(context).textTheme.bodySmall),
                  Align(alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const Key('update-apk-cleanup-button'),
                      onPressed: _busy || widget.downloadInProgress ||
                          found.count == 0 ? null : () => _remove(found),
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: Text(labels.updateApkCleanupAction),
                    )),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
