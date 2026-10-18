# HYP Viewer v0.4.11 – Windows stability and tray behavior

The code is designed for Windows EXE installers. Flutter unit tests and
Actions builds do **not** prove Windows shell timing or resolve a native crash
without a device reproduction.

## Current issue (observed on v0.4.9)

1. Clicking the Windows update download sometimes closes/crashes the app as
   the download begins.
2. With **X closes the application** enabled, the X button can take several
   seconds even on a fresh start with no downloads.

The prior Windows code kept `windowManager.setPreventClose(true)` even when
the user's setting was **X quits**. The updater also set
`setInstallerDownloadActive(true)` without resetting it in its own
`finally`; the reset was incorrectly located in an unrelated offline
gallery-download cleanup.

## New lifecycle

- Default **X hides to tray**: native close interception stays enabled.
- **X quits** and no downloads: native close interception is disabled.
  Windows is allowed to close the app directly; no async destroy callback.
- **X quits** while transfers are active: interception is temporarily
  enabled; prompt the user before stopping. A canceled prompt preserves the
  work. On confirmation, hide first and then tear down the tray and window.
- Guard changes are serialized to avoid older asynchronous plugin responses
  re-enabling an obsolete close policy.
- Explicit **Quit completely** from the tray always closes the process.
- One click toggles hide/show (280ms single/double-click debounce);
  double-click always restores and focuses. Right click opens a native menu.

## Native Windows tray menu

- Current downloaded work ID and progress (page count and percent), or
  updater progress when an in-app installer download was explicitly selected.
- Transfer pause/resume while an active gallery supports it; this is a
  per-work pause, **not** a pause of the entire queued batch.
- Cancel all downloads only after user confirmation; already saved files stay.
- Continue most recently opened gallery; disabled/omitted when unavailable.
- Open Downloads, Check for updates, Show/Hide window, Quit completely.
- Korean, English and Japanese text for all newly added menu controls.
- One native notification for a successful batch **only while hidden**.
  Clicking the notification opens the Downloads screen. Notification errors
  are isolated from the transfers. Windows toast permission/settings may
  prevent them from appearing.

## Windows update safety

- Default update dialog action for Windows: **download official GitHub EXE in
  the external browser**. It avoids the in-process download path implicated
  in v0.4.9. Browser downloads are not SHA-256 verified by HYP Viewer; compare
  against SHA256SUMS.txt on the GitHub Release when needed.
- The in-app resume/hash-verified downloader remains available as a separate
  **diagnostic** option. Its original SHA-256 and safe-resume logic is retained.
- New phase logs: checksum, storage, HTTP request, response headers,
  first byte, complete bytes, SHA-256 verified, normal/failed exit.
- Previous incomplete update attempt is reported at next launch without
  collecting cookies, URLs, downloaded content, passwords, or gallery data.
- `setInstallerDownloadActive(false)` now executes in the updater's
  `finally`; unrelated gallery code no longer modifies that flag.

## Manual verification on Windows (after CI and release)

1. Install v0.4.11 **over** v0.4.10. Back up library to JSON first.
2. With **X closes the app** enabled, launch freshly and press X without any
   download. Measure visible window disappearance (<0.5s target) and process
   exit (<2s target), repeat 10 times. The targets are not observed results.
3. Disable the option and test X -> tray; single click hide/show, double-click
   focus, right-click menu, Quit completely.
4. Start two queued downloads, hide to tray, confirm ID/progress, pause/resume,
   verify cancel confirmation, and check the successful hidden-batch toast.
5. Read a gallery, return to home, hide to tray, choose Continue reading;
   confirm the same work resumes and page history is retained.
6. Open Check for updates from the tray, test browser download of the official
   EXE, and test in-app verified download on a controlled environment.
7. Simulate a network outage during the in-app download; verify it does not
   exit, produces an error/retry, and can resume later.
8. Use the previous v0.4.9 binary separately to confirm the original bug.
   Replacing the app with v0.4.11 cannot retroactively fix old v0.4.9 code.

## Diagnostics

- Windows close: `%LOCALAPPDATA%\\HYP_Viewer\\diagnostics\\window_exit.log`
- Updater: the `hyp_updates/update_diagnostics.log` file under the
  application's support directory, as with v0.4.9.
- Windows native crashes may instead be visible in Event Viewer ->
  Windows Logs -> Application, or Windows Error Reporting records.
- If a test fails, record the Windows version, HYP Viewer version, action,
  time-to-close, and the last non-sensitive diagnostic log stages.

## Compatibility guarantees

No modification to shelf JSON schema, reading history format, saved library,
existing offline CBZ files, backup format, or Android download service.
Only app version, Windows tray lifecycle, optional toast integration,
and Windows updater diagnostics/actions changed. Keep version in 0.x.
