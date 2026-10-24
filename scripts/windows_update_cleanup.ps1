# v0.4.25 Inno pre-install: stop only HYP Viewer processes installed at
# this exact application path and GoodbyeDPI children recorded by its own
# DPI supervisor sessions. Never stop arbitrary GoodbyeDPI, WinDivert
# services, WebView2 processes, or programs belonging to other installations.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$AppExecutable,
  [Parameter(Mandatory=$true)][string]$DpiExecutable,
  [Parameter(Mandatory=$true)][string]$RuntimeRoot,
  [switch]$DiagnosticProbe
)

$ErrorActionPreference = 'Stop'
function Canonical([string]$value) {
  try { return [IO.Path]::GetFullPath($value).TrimEnd('\') }
  catch { return '' }
}
$appPath = Canonical $AppExecutable
$dpiPath = Canonical $DpiExecutable
$runtimePath = Canonical $RuntimeRoot
if (-not $appPath -or -not $dpiPath -or -not $runtimePath) { exit 2 }
if (-not [string]::Equals([IO.Path]::GetFileName($appPath), 'hyp_viewer.exe',
    [StringComparison]::OrdinalIgnoreCase)) { exit 2 }
if (-not [string]::Equals($dpiPath,
    (Canonical (Join-Path (Split-Path -Parent $appPath) 'tools\goodbyedpi.exe')),
    [StringComparison]::OrdinalIgnoreCase)) { exit 2 }
if (-not [string]::Equals([IO.Path]::GetFileName($runtimePath),
    'dpi_runtime', [StringComparison]::OrdinalIgnoreCase)) { exit 2 }
if (-not [string]::Equals([IO.Path]::GetFileName(
    (Split-Path -Parent $runtimePath)), 'HYP Viewer',
    [StringComparison]::OrdinalIgnoreCase)) { exit 2 }

# CI probe never enumerates or terminates processes.
if ($DiagnosticProbe) {
  Write-Output 'diagnostic-ready'
  exit 0
}

function IsExactOwnedProcess([int]$ProcessId, [string]$ExpectedPath) {
  if ($ProcessId -lt 1) { return $false }
  try {
    $candidate = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction Stop
    if ($null -eq $candidate -or -not $candidate.ExecutablePath) { return $false }
    return [string]::Equals((Canonical $candidate.ExecutablePath),
      $ExpectedPath, [StringComparison]::OrdinalIgnoreCase)
  } catch { return $false }
}

function GetInstalledAppPids() {
  $out = @()
  try {
    foreach ($candidate in @(Get-CimInstance -ClassName Win32_Process -Filter "Name='hyp_viewer.exe'")) {
      if ($null -ne $candidate -and (IsExactOwnedProcess ([int]$candidate.ProcessId) $appPath)) {
        $out += [int]$candidate.ProcessId
      }
    }
  } catch { throw 'Unable to inspect HYP Viewer processes safely.' }
  return @($out | Select-Object -Unique)
}

function GetOwnedDpiSessions() {
  $entries = @()
  if (-not (Test-Path -LiteralPath $runtimePath -PathType Container)) { return @() }
  foreach ($folder in @(Get-ChildItem -LiteralPath $runtimePath -Directory -ErrorAction Stop)) {
    if ($folder.Name -notmatch '^[0-9a-f]{32}$') { continue }
    $status = Join-Path $folder.FullName 'status.txt'
    if (-not (Test-Path -LiteralPath $status -PathType Leaf)) { continue }
    $stage = [IO.File]::ReadAllText($status).Trim()
    if ($stage -notmatch '^running:([0-9]{1,10})$') { continue }
    $childPid = [int]$Matches[1]
    if (IsExactOwnedProcess $childPid $dpiPath) {
      $entries += [pscustomobject]@{ Pid = $childPid; Folder = $folder.FullName }
    }
  }
  return @($entries)
}

try {
  # Signal existing sessions before closing the parent. Their privileged
  # supervisors can then shut down only their own child without escalation.
  $ownedDpi = @(GetOwnedDpiSessions)
  foreach ($entry in $ownedDpi) {
    [IO.File]::WriteAllText((Join-Path $entry.Folder 'stop.signal'), 'stop')
  }

  $appPids = @(GetInstalledAppPids)
  foreach ($id in $appPids) {
    if (-not (IsExactOwnedProcess $id $appPath)) { continue }
    try {
      $process = Get-Process -Id $id -ErrorAction Stop
      [void]$process.CloseMainWindow()
    } catch {}
  }
  # X may hide to tray. Allow graceful shutdown first; then force ONLY an
  # exact installed HYP Viewer executable when updating is user-approved.
  for ($attempt = 0; $attempt -lt 12; $attempt++) {
    if (@(GetInstalledAppPids).Count -eq 0) { break }
    Start-Sleep -Milliseconds 250
  }
  foreach ($id in @(GetInstalledAppPids)) {
    if (IsExactOwnedProcess $id $appPath) {
      Stop-Process -Id $id -Force -ErrorAction Stop
    }
  }
  Start-Sleep -Milliseconds 350
  if (@(GetInstalledAppPids).Count -gt 0) {
    throw 'HYP Viewer is still running; retry the installer.'
  }

  for ($attempt = 0; $attempt -lt 24; $attempt++) {
    $running = @($ownedDpi | Where-Object { IsExactOwnedProcess $_.Pid $dpiPath })
    if ($running.Count -eq 0) { break }
    Start-Sleep -Milliseconds 250
  }
  # Only processes proven to be HYP's session-owned bundled DPI engine may
  # be forced; never delete WinDivert64.sys or terminate shared drivers.
  foreach ($entry in $ownedDpi) {
    if (IsExactOwnedProcess $entry.Pid $dpiPath) {
      Stop-Process -Id $entry.Pid -Force -ErrorAction Stop
    }
  }
  Start-Sleep -Milliseconds 400
  foreach ($entry in $ownedDpi) {
    if (IsExactOwnedProcess $entry.Pid $dpiPath) {
      throw 'HYP-owned DPI engine is still using WinDivert; close it or reboot.'
    }
  }
  Write-Output 'hyp-cleanup-ready'
  exit 0
} catch {
  Write-Error ('HYP update cleanup failed: ' + $_.Exception.Message)
  exit 3
}
