import 'dart:async';

import 'package:flutter/material.dart';

import '../core/windows_dpi.dart';
import '../l10n/app_localizations.dart';

class WindowsDpiSettingsPanel extends StatefulWidget {
  const WindowsDpiSettingsPanel({super.key});
  @override
  State<WindowsDpiSettingsPanel> createState() =>
      _WindowsDpiSettingsPanelState();
}

class _WindowsDpiSettingsPanelState extends State<WindowsDpiSettingsPanel> {
  final manager = WindowsDpiManager.instance;
  final custom = TextEditingController();
  bool busy = false;
  bool? testResult;
  bool invalid = false;

  @override
  void initState() {
    super.initState();
    custom.text = manager.preferences.custom;
    manager.addListener(_refresh);
    unawaited(manager.initialize());
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    manager.removeListener(_refresh);
    custom.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (busy) return;
    setState(() { busy = true; invalid = false; });
    try {
      await operation();
    } catch (_) {
      if (mounted) setState(() => invalid = true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final pref = manager.preferences;
    final locked = busy || !manager.initialized ||
        manager.phase == WindowsDpiPhase.starting ||
        manager.phase == WindowsDpiPhase.stopping;
    String preview;
    try {
      preview = pref.arguments.join(' ');
    } catch (_) {
      preview = l.dpiInvalid;
    }
    final status = switch (manager.phase) {
      WindowsDpiPhase.stopped => 'OFF',
      WindowsDpiPhase.starting => 'STARTING / UAC',
      WindowsDpiPhase.running => 'ON',
      WindowsDpiPhase.stopping => 'STOPPING',
      WindowsDpiPhase.failed => 'ERROR',
      WindowsDpiPhase.unavailable => 'WINDOWS ONLY',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(l.dpiConsent, style: Theme.of(context).textTheme.bodySmall),
      SwitchListTile.adaptive(
        key: const Key('windows-dpi-enabled'),
        contentPadding: EdgeInsets.zero,
        title: Text(l.dpiEnable), value: pref.enabled,
        onChanged: locked ? null : (v) => _run(() => manager.setEnabled(v)),
      ),
      SwitchListTile.adaptive(
        key: const Key('windows-dpi-autostart'),
        contentPadding: EdgeInsets.zero,
        title: Text(l.dpiAutoStart), value: pref.autoStart,
        onChanged: locked || !pref.enabled ? null
            : (v) => _run(() => manager.setAutoStart(v)),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        key: ValueKey('windows-dpi-preset-' + pref.preset),
        isExpanded: true,
        initialValue: pref.preset,
        decoration: InputDecoration(labelText: l.dpiPreset),
        items: [
          for (final mode in WindowsDpiPreferences.presets)
            DropdownMenuItem(value: mode, child: Text(
              mode == 'recommended' ? 'Standard (-9)' :
              mode == 'all' ? 'all (legacy -1)' :
              mode == 'custom' ? l.dpiCustom : mode,
              overflow: TextOverflow.ellipsis)),
        ],
        onChanged: locked ? null : (mode) {
          if (mode != null) {
            _run(() => manager.updatePreferences(pref.copyWith(preset: mode)));
          }
        },
      ),
      if (pref.preset.contains('dnsredir')) ...[
        const SizedBox(height: 8),
        Text(l.dpiDnsWarning,
            style: Theme.of(context).textTheme.bodySmall),
      ],
      if (pref.preset == 'custom') ...[
        const SizedBox(height: 10),
        TextField(
          key: const Key('windows-dpi-custom-args'),
          controller: custom, enabled: !locked, maxLength: 240,
          decoration: InputDecoration(labelText: l.dpiCustom,
              hintText: '-9 --dns-addr 1.1.1.1 --dns-port 53'),
        ),
        Align(alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            key: const Key('windows-dpi-apply-args'),
            onPressed: locked ? null : () => _run(() =>
              manager.updatePreferences(pref.copyWith(custom: custom.text))),
            icon: const Icon(Icons.done), label: Text(l.dpiApply),
          ),
        ),
      ],
      const SizedBox(height: 10),
      Text(l.dpiPreview, style: Theme.of(context).textTheme.labelMedium),
      SelectableText(preview, key: const Key('windows-dpi-args-preview')),
      const SizedBox(height: 10),
      Text(l.dpiStatus + ': ' + status, key: const Key('windows-dpi-status')),
      if (manager.diagnostic.isNotEmpty)
        SelectableText('Code: ' + manager.diagnostic,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (invalid) Text(l.dpiInvalid,
          style: TextStyle(color: Theme.of(context).colorScheme.error)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          key: const Key('windows-dpi-restart'),
          onPressed: locked || !pref.enabled ? null
              : () => _run(manager.restart),
          icon: const Icon(Icons.restart_alt), label: Text(l.dpiRestart)),
        OutlinedButton.icon(
          key: const Key('windows-dpi-test-connection'),
          onPressed: busy ? null : () async {
            setState(() => busy = true);
            try {
              final ok = await manager.checkSite();
              if (mounted) setState(() => testResult = ok);
            } finally {
              if (mounted) setState(() => busy = false);
            }
          },
          icon: const Icon(Icons.wifi_tethering), label: Text(l.dpiTest)),
      ]),
      if (testResult != null) ...[
        const SizedBox(height: 8),
        Text(testResult! ? l.dpiTestOk : l.dpiTestFail),
      ],
    ]);
  }
}
