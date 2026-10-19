# Run on Windows GitHub Actions without UAC or WinDivert.
# Probes the shipped script path handling and first status acknowledgment.
$ErrorActionPreference = 'Stop'
$runner = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$script = Join-Path $PSScriptRoot 'windows_dpi_supervisor.ps1'
$id = [guid]::NewGuid().ToString('N')
$root = Join-Path ([System.IO.Path]::GetTempPath()) ("hyp_dpi_ci_" + $id)
$session = Join-Path (Join-Path (Join-Path $root 'HYP Viewer') 'dpi_runtime') $id
$fakeSession = Join-Path (Join-Path $root 'unexpected') $id
try {
  [System.IO.Directory]::CreateDirectory($session) | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $session 'status.txt'), 'starting')
  # Simulates another account's environment; explicitly passed session path
  # must still win, even when APPDATA points elsewhere.
  $originalAppdata = $env:APPDATA
  $env:APPDATA = Join-Path $root 'different-admin-profile'
  try {
    & $runner -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script -SessionId $id -SessionPath $session -ParentPid $PID -DiagnosticProbe
    if ($LASTEXITCODE -ne 0) {
      throw "Supervisor probe failed: exit $LASTEXITCODE"
    }
  } finally {
    $env:APPDATA = $originalAppdata
  }
  $actual = (Get-Content -LiteralPath (Join-Path $session 'status.txt') -Raw).Trim()
  if ($actual -ne 'diagnostic-ready') {
    throw "Supervisor did not acknowledge the original session; got $actual"
  }
  [System.IO.Directory]::CreateDirectory($fakeSession) | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $fakeSession 'status.txt'), 'starting')
  & $runner -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script -SessionId $id -SessionPath $fakeSession -ParentPid $PID -DiagnosticProbe
  if ($LASTEXITCODE -ne 2) {
    throw "Invalid parent folder was accepted: exit $LASTEXITCODE"
  }
  if ((Get-Content -LiteralPath (Join-Path $fakeSession 'status.txt') -Raw).Trim() -ne 'starting') {
    throw 'Invalid session path was modified'
  }
  Write-Host 'HYP Windows DPI supervisor session-path/ack smoke tests passed.'
} finally {
  if (Test-Path -LiteralPath $root) {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
  }
}
