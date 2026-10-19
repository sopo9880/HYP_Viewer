import 'dart:async';

import 'package:flutter/material.dart';

import '../core/android_dpi.dart';
import '../l10n/app_localizations.dart';

/// Android DPI settings: app-only or user-consented local device VPN.
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

  Future<void> _chooseExcludedApps() async {
    await _run(() async {
      final apps = await manager.availableVpnApps();
      if (!mounted) return;
      final selected = manager.preferences.excludedApps.toSet();
      final next = await showDialog<List<String>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, updateDialog) => AlertDialog(
            title: Text(AppLocalizations.of(dialogContext)!.androidDpiExcludeApps),
            content: SizedBox(
              width: 440, height: 390,
              child: apps.isEmpty
                  ? const Text('No launchable applications found')
                  : ListView.builder(
                      itemCount: apps.length,
                      itemBuilder: (context, index) {
                        final app = apps[index];
                        final id = app['package'] ?? '';
                        return CheckboxListTile(
                          dense: true,
                          title: Text(app['name'] ?? id),
                          subtitle: Text(id),
                          value: selected.contains(id),
                          onChanged: (checked) => updateDialog(() {
                            if (checked == true) {
                              if (selected.length < 100) selected.add(id);
                            } else {
                              selected.remove(id);
                            }
                          }),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(MaterialLocalizations.of(dialogContext).cancelButtonLabel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, selected.toList()),
                child: Text(MaterialLocalizations.of(dialogContext).okButtonLabel),
              ),
            ],
          ),
        ),
      );
      if (next != null) await manager.setExcludedApps(next);
    });
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
        key: ValueKey('android-dpi-scope-' + pref.scope),
        initialValue: pref.scope,
        decoration: InputDecoration(labelText: l.androidDpiScope),
        items: [
          DropdownMenuItem(value: 'app',
              child: Text(l.androidDpiScopeApp)),
          DropdownMenuItem(value: 'device',
              child: Text(l.androidDpiScopeDevice)),
        ],
        onChanged: locked ? null : (value) {
          if (value != null) _run(() => manager.setScope(value));
        },
      ),
      if (pref.scope == 'device') ...[
        const SizedBox(height: 8),
        Text(l.androidDpiVpnNotice,
            style: Theme.of(context).textTheme.bodySmall),
        OutlinedButton.icon(
          key: const Key('android-dpi-vpn-excluded'),
          onPressed: locked ? null : _chooseExcludedApps,
          icon: const Icon(Icons.apps_outlined),
          label: Text(l.androidDpiExcludeApps +
              ' (' + pref.excludedApps.length.toString() + ')'),
        ),
      ],
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        key: ValueKey('android-dpi-preset-' + pref.preset),
        initialValue: pref.preset,
        isExpanded: true,
        decoration: InputDecoration(labelText: l.dpiPreset),
        items: [
          const DropdownMenuItem(value: 'russia_blacklist',
              child: Text('russia_blacklist')),
          const DropdownMenuItem(value: 'russia_blacklist_dnsredir',
              child: Text('russia_blacklist_dnsredir')),
          const DropdownMenuItem(value: 'all',
              child: Text('all')),
          DropdownMenuItem(value: 'all_dnsredir',
              child: Text(l.androidDpiRecommendedPreset)),
          const DropdownMenuItem(value: 'all_dnsredir_hardcore',
              child: Text('all_dnsredir_hardcore')),
        ],
        onChanged: locked ? null : (preset) {
          if (preset != null) {
            _run(() => manager.setPreset(preset));
          }
        },
      ),
      const SizedBox(height: 8),
      Text(l.dpiPreview),
      SelectableText(AndroidDpiPreferences.options[pref.preset] ?? '-s 1'),
      if (pref.needsAlternativeDns)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(l.androidDpiDnsNotice,
              style: Theme.of(context).textTheme.bodySmall),
        ),
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
