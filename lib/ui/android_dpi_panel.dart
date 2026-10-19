import 'dart:async';

import 'package:flutter/material.dart';

import '../core/android_dpi.dart';
import '../l10n/app_localizations.dart';

/// Android-only app-scoped DPI settings. No system VPN permissions are used.
class AndroidDpiSettingsPanel extends StatefulWidget {
  const AndroidDpiSettingsPanel({super.key});

  @override
  State<AndroidDpiSettingsPanel> createState() =>
      _AndroidDpiSettingsPanelState();
}

class _AndroidDpiSettingsPanelState extends State<AndroidDpiSettingsPanel> {
  final manager = AndroidDpiManager.instance;
  bool busy = false;
  bool? connectivity;
  String? error;

  @override
  void initState() {
    super.initState();
    manager.addListener(_refresh);
    unawaited(manager.initialize());
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    manager.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() { busy = true; error = null; connectivity = null; });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final pref = manager.preferences;
    final starting = manager.phase == AndroidDpiPhase.starting ||
        manager.phase == AndroidDpiPhase.stopping;
    final locked = busy || starting || !manager.initialized ||
        manager.phase == AndroidDpiPhase.unavailable;
    final active = manager.phase == AndroidDpiPhase.running;
    final status = switch (manager.phase) {
      AndroidDpiPhase.stopped => 'OFF',
      AndroidDpiPhase.starting => 'STARTING',
      AndroidDpiPhase.running => 'ON',
      AndroidDpiPhase.stopping => 'STOPPING',
      AndroidDpiPhase.failed => 'ERROR',
      AndroidDpiPhase.unavailable => 'UNAVAILABLE',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(l.androidDpiNotice,
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      SwitchListTile.adaptive(
        key: const Key('android-dpi-enabled'),
        contentPadding: EdgeInsets.zero,
        title: Text(l.androidDpiEnable),
        value: active,
        onChanged: locked ? null :
            (enabled) => _run(() => manager.setEnabled(enabled)),
      ),
      SwitchListTile.adaptive(
        key: const Key('android-dpi-autostart'),
        contentPadding: EdgeInsets.zero,
        title: Text(l.dpiAutoStart),
        value: pref.autoStart,
        onChanged: locked ? null :
            (enabled) => _run(() => manager.setAutoStart(enabled)),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        key: ValueKey('android-dpi-preset-' + pref.preset),
        initialValue: pref.preset,
        isExpanded: true,
        decoration: InputDecoration(labelText: l.dpiPreset),
        items: [
          DropdownMenuItem(value: 'standard',
              child: Text(l.androidDpiStandard)),
          DropdownMenuItem(value: 'strong',
              child: Text(l.androidDpiStrong)),
          DropdownMenuItem(value: 'sni',
              child: Text(l.androidDpiSni)),
        ],
        onChanged: locked ? null : (preset) {
          if (preset != null) {
            _run(() => manager.setPreset(preset));
          }
        },
      ),
      const SizedBox(height: 8),
      Text(l.dpiPreview),
      SelectableText('http://127.0.0.1 + ' +
          (AndroidDpiPreferences.options[pref.preset] ?? '-s 1')),
      const SizedBox(height: 10),
      Text(l.dpiStatus + ': ' + status,
          key: const Key('android-dpi-status')),
      if (manager.diagnostic.isNotEmpty)
        SelectableText('Code: ' + manager.diagnostic,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (error != null)
        SelectableText(error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          key: const Key('android-dpi-restart'),
          icon: const Icon(Icons.restart_alt),
          label: Text(l.dpiRestart),
          onPressed: locked || !active ? null : () => _run(() async {
            await manager.stop();
            await manager.start();
          }),
        ),
        OutlinedButton.icon(
          key: const Key('android-dpi-test'),
          icon: const Icon(Icons.wifi_tethering),
          label: Text(l.dpiTest),
          onPressed: locked || !active ? null : () => _run(() async {
            final ok = await manager.checkSite();
            if (mounted) setState(() => connectivity = ok);
          }),
        ),
      ]),
      if (connectivity != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(connectivity! ? l.dpiTestOk : l.dpiTestFail),
        ),
    ]);
  }
}
