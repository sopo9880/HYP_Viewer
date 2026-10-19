# Windows GoodbyeDPI bootstrap diagnostics (v0.4.19)

When HYP Viewer shows a Windows DPI error, it is not necessarily caused by
administrator approval. Earlier versions reported **elevation-timeout** if
`status.txt` remained at `starting` for 50 seconds, even if PowerShell
never launched or exited immediately.

The v0.4.19 supervisor records these stages in each session's `status.txt`:

| Status | Meaning |
| --- | --- |
| `starting` | The Flutter app created the session; PowerShell unverified |
| `supervisor-started` | Windows PowerShell executed the shipping script |
| `elevation-requested` | PowerShell requested administrator approval |
| `supervisor-elevated` | The elevated supervisor found the original session |
| `engine-starting` | The engine executable launch is in progress |
| `running:<pid>` | The app-owned GoodbyeDPI process is running |
| `error:<code>` | A structured startup or runtime failure |
| `stopped` | The app-owned GoodbyeDPI engine stopped |

The launching process passes an **explicit absolute session path** to both
non-elevated and elevated PowerShell instances. This avoids an admin profile
accidentally looking inside its own `%APPDATA%` folder instead of the user's.

The app keeps the non-elevated PowerShell launcher attached long enough to
collect its exit code and bounded stdout/stderr in `launcher-log.txt`; an
elevated script writes its exception to `supervisor-error.txt`, locally.
Both are inside `%APPDATA%\HYP Viewer\dpi_runtime\<session-id>`. The app's
Settings → DPI panel exposes the current attempt's **View DPI diagnostics**
action. Logs are not uploaded or shared automatically.

Timeouts are stage-specific: `supervisor-no-start` (8 seconds without
PowerShell acknowledgment), `elevation-approval-timeout` (50 seconds waiting
for approval), and `engine-start-timeout` (50 seconds after elevation).
On a failure, the app signals cancellation before any late elevation can
start the engine. The script also verifies the parent process ID and only
stops its own GoodbyeDPI child.

CI checks PowerShell parsing and the real script's session-path acknowledgment
under a simulated different `APPDATA`, *without invoking UAC or WinDivert*.
A successful CI build **does not verify administrator prompts or filtering on
a real Windows PC**. Users can retry and inspect diagnostics after updating.

Observed October 19 reproduction:
- All three reported sessions remained at `starting`.
- Original status file write delays were 2–3 ms.
- Two had a `stop.signal`; these observations alone do not prove which
  PowerShell or Windows security policy error caused the failure.
