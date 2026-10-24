# CI smoke test: validation-only mode modifies no live process or driver.
$ErrorActionPreference = 'Stop'
$helper = Join-Path $PSScriptRoot 'windows_update_cleanup.ps1'
$app = Join-Path $env:TEMP 'HYP Viewer\hyp_viewer.exe'
$dpi = Join-Path $env:TEMP 'HYP Viewer\tools\goodbyedpi.exe'
$root = Join-Path $env:TEMP 'HYP Viewer\dpi_runtime'

$argsToProbe = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
    '-File', $helper, '-AppExecutable', $app, '-DpiExecutable', $dpi,
    '-RuntimeRoot', $root, '-DiagnosticProbe')
$valid = & powershell.exe @argsToProbe
if ($LASTEXITCODE -ne 0 -or ($valid -join '') -notmatch 'diagnostic-ready') {
  throw 'The scoped update-cleanup diagnostic probe failed.'
}

# Refuse an unrelated executable, even in diagnostic mode.
$bad = Join-Path $env:TEMP 'AnotherApp\another.exe'
$argsToProbe[7] = $bad
$null = & powershell.exe @argsToProbe
if ($LASTEXITCODE -eq 0) {
  throw 'Unsafe updater cleanup accepted an unrelated executable.'
}
Write-Output 'Windows updater scoped-cleanup probe passed.'
