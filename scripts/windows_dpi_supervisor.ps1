# HYP Viewer v0.4.17: bundled GoodbyeDPI Windows UAC supervisor.
# The user approves elevation. Stops only its own child, when the parent
# application exits or when that application places a stop signal.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [ValidatePattern('^[0-9a-f]{32}$')]
  [string] $SessionId,
  [Parameter(Mandatory=$true)]
  [ValidateRange(1,2147483647)]
  [int] $ParentPid
)

$ErrorActionPreference = 'Stop'
$baseDir = Join-Path $env:APPDATA 'HYP Viewer\dpi_runtime'
$session = Join-Path $baseDir $SessionId
$statusFile = Join-Path $session 'status.txt'
$stopFile = Join-Path $session 'stop.signal'

function Status([string] $value) {
  if (Test-Path -LiteralPath $session -PathType Container) {
    [System.IO.File]::WriteAllText($statusFile, $value,
      (New-Object System.Text.UTF8Encoding($false)))
  }
}

function IsElevated {
  $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
  $user = New-Object System.Security.Principal.WindowsPrincipal($identity)
  return $user.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Path -LiteralPath $session -PathType Container)) {
  exit 2
}

if (-not (IsElevated)) {
  try {
    # Safe parameters are restricted to hex session ID and numeric parent PID.
    $argLine = '-NoProfile -NonInteractive -ExecutionPolicy Bypass ' +
      '-WindowStyle Hidden -File "' + $PSCommandPath + '" ' +
      '-SessionId ' + $SessionId + ' -ParentPid ' + $ParentPid
    Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $argLine -WindowStyle Hidden -Verb RunAs | Out-Null
  } catch {
    Status 'error:elevation-denied'
    exit 3
  }
  exit 0
}

$child = $null
$finished = $false
try {
  Status 'starting'
  $parent = Get-Process -Id $ParentPid -ErrorAction Stop
  if ($parent.ProcessName -ne 'hyp_viewer') { throw 'invalid-parent' }
  $configPath = Join-Path $session 'arguments.json'
  if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw 'missing-options'
  }
  $cfg = (Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop)
  $preset = [string] $cfg.preset

  switch ($preset) {
    'recommended' { $argsList = @('-9') }
    'russia_blacklist' {
      $argsList = @('-9','--blacklist','russia-blacklist.txt')
    }
    'russia_blacklist_dnsredir' {
      $argsList = @('-9','--blacklist','russia-blacklist.txt',
        '--dns-addr','77.88.8.8','--dns-port','1253')
    }
    'all' { $argsList = @('-1') }
    'all_dnsredir' {
      $argsList = @('-1','--dns-addr','77.88.8.8','--dns-port','1253')
    }
    'all_dnsredir_hardcore' {
      $argsList = @('-1','-a','-m','--dns-addr','77.88.8.8','--dns-port','1253')
    }
    'custom' {
      $raw = [string] $cfg.custom
      if ($raw.Length -lt 2 -or $raw.Length -gt 240) {
        throw 'invalid-custom-arguments'
      }
      $argsList = @($raw.Trim() -split '\s+')
      if ($argsList.Count -gt 30) { throw 'too-many-arguments' }
      $noValue = @('-1','-2','-3','-4','-5','-6','-7','-8','-9',
        '-p','-q','-r','-s','-m','-n','-a','--reverse-frag',
        '--wrong-seq','--wrong-chksum','--auto-ttl')
      $numberValue = @('-f','-k','-e','--dns-port','--max-payload',
        '--set-ttl','--min-ttl')
      for ($i = 0; $i -lt $argsList.Count; $i++) {
        $item = [string] $argsList[$i]
        if ($noValue -contains $item) { continue }
        if ($numberValue -contains $item) {
          $i++
          if ($i -ge $argsList.Count -or $argsList[$i] -notmatch '^\d{1,5}$') {
            throw 'invalid-numeric-argument'
          }
          continue
        }
        if ($item -eq '--dns-addr') {
          $i++
          if ($i -ge $argsList.Count -or
              $argsList[$i] -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
            throw 'invalid-dns-address'
          }
          continue
        }
        if ($item -eq '--blacklist') {
          $i++
          if ($i -ge $argsList.Count -or
              $argsList[$i] -notmatch '^[A-Za-z0-9_-]{1,50}\.txt$') {
            throw 'invalid-blacklist-file'
          }
          continue
        }
        throw 'unsupported-goodbyedpi-argument'
      }
    }
    default { throw 'unsupported-preset' }
  }

  $engine = Join-Path $PSScriptRoot 'goodbyedpi.exe'
  foreach ($file in @('goodbyedpi.exe', 'WinDivert.dll', 'WinDivert64.sys')) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $file) -PathType Leaf)) {
      throw 'missing-bundled-engine'
    }
  }
  $child = Start-Process -FilePath $engine -WorkingDirectory $PSScriptRoot -ArgumentList $argsList -WindowStyle Hidden -PassThru -ErrorAction Stop
  Start-Sleep -Milliseconds 250
  $child.Refresh()
  if ($child.HasExited) { throw 'engine-exited-at-startup' }
  Status ('running:' + $child.Id)
  while ($true) {
    if (Test-Path -LiteralPath $stopFile -PathType Leaf) { break }
    if (-not (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue)) { break }
    $child.Refresh()
    if ($child.HasExited) { throw 'engine-exited' }
    Start-Sleep -Milliseconds 500
  }
  $finished = $true
} catch {
  # Fixed text codes only: no profile paths or command lines.
  $allowed = @('invalid-parent','missing-options','invalid-custom-arguments',
    'too-many-arguments','invalid-numeric-argument','invalid-dns-address',
    'invalid-blacklist-file','unsupported-goodbyedpi-argument',
    'unsupported-preset','missing-bundled-engine','engine-exited-at-startup',
    'engine-exited')
  $reason = [string] $_.Exception.Message
  if ($allowed -notcontains $reason) { $reason = 'startup-failed' }
  Status ('error:' + $reason)
} finally {
  if ($null -ne $child) {
    try {
      $child.Refresh()
      if (-not $child.HasExited) {
        Stop-Process -Id $child.Id -Force -ErrorAction SilentlyContinue
        $child.WaitForExit(3000) | Out-Null
      }
    } catch {}
  }
  if ($finished) { Status 'stopped' }
}
