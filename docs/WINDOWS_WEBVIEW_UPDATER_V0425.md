# HYP Viewer v0.4.25: Windows web search and installer handoff

## Reproduced user symptoms (v0.4.24)

- Home and library display normally, but opening **Search on web** creates a grey screen on Windows.
- WebView2 Evergreen Runtime 155.0.4283.62 is installed and child processes respond.
- Starting a fresh instance with `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--disable-gpu` does not fix it.
- Setting **Web search ad blocking → Off** restores the page.
- A previous Windows installer reported `WinDivert64.sys: DeleteFile failed; code 5` while replacing files.

## Browser compatibility path

Manual and automatic Hitomi WebViews now explicitly share a WebView2 environment
created under `getApplicationSupportDirectory()/hitomi_web_search_webview2`.
If environment creation fails, the manual search shows an error, retry and
external browser action rather than constructing a native view.

On Windows, native request interception, content blockers and document-start
injection are disabled **even when Standard or Strong is selected**. The
existing post-load DOM cleanup and pop-up restrictions are retained. This is
**cosmetic filtering only, not network-level ad blocking**; the app labels the
limitation in Settings. Android keeps network and document-start filtering.
We prefer reliable access over claims of blocking traffic that can cause a
grey native WebView. Windows full network blocking needs a separately proven
engine or plugin fix.

The manual screen includes a bounded 15-second load warning with retry and
external-browser actions. Native crashes cannot be proven prevented by unit
tests; verify on a real Windows machine after official release.

## Windows installer pre-install cleanup

`installer/hyp_viewer.iss` uses `PrepareToInstall` and extracts
`scripts/windows_update_cleanup.ps1` to the installer temporary directory.
The helper:
1. Validates an exact `hyp_viewer.exe` application path and the corresponding
   bundled `tools/goodbyedpi.exe` path.
2. Enumerates only processes whose executable path exactly matches that
   installed HYP Viewer executable; tries a normal window close first and
   forcibly stops only those remaining.
3. Signals `stop.signal` only for matching 32-hex HYP-owned DPI supervisor
   sessions whose recorded `running:PID` still points to the exact bundled
   DPI engine; waits for the privileged supervisor, then forces only those
   verified children if needed.
4. Refuses to proceed on a failure rather than silently skipping locked files.

The helper never deletes `WinDivert64.sys`, alters the WinDivert service,
or stops arbitrary `goodbyedpi.exe`, `msedgewebview2.exe`, or other user
processes. Elevated DPI processes that cannot be stopped without permission
may still require user action or a restart.

For in-app updates, SHA-256-verification happens first. Active downloads
defer installation, retaining the verified installer and persisted transfers.
If no download is running, HYP explicitly stops its own DPI supervisor
before launching Inno; the installer performs scoped cleanup again to handle
manual installations and older versions.

No library, cache of downloaded images, reader settings or user library schema
is changed by the installer cleanup. The 0.x versioning and one signed
Android APK per main-CI-commit release pipeline remain unchanged.

## Checks and post-release validation

CI: Dart tests for platform policy, routing and source-level invariants;
PowerShell AST validation and diagnostic-only identity-validation probe;
Inno Setup compilation; Android tests; Windows Release compilation.

After v0.4.25 is officially released, on a real Windows machine:
- Open Hitomi manual search with Off, Standard and Strong and verify visible UI.
  Standard and Strong hide ad DOM after load but do **not** block requests.
- Verify automatic search with a query and manual search with an empty query.
- Start an in-app update while a gallery is actively downloading and ensure
  installation is deferred without discarding already downloaded pages.
- With no active download, enable app-owned DPI, install an update, verify no
  `WinDivert64.sys` lock error and normal postinstall restart.
- Repeat with HYP hidden in the tray and with HYP already running from the
  currently installed path.
- Verify independent GoodbyeDPI/WinDivert and unrelated WebView2 processes
  remain running; verify the saved library and settings remain unchanged.
