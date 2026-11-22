# Handler for claude-focus: links (toast click). Windows PowerShell 5.1. Pure ASCII.
# claude-focus:?root=<workspace folder name>&session=<session uuid>
# 0 windows: log. >1: focus the first, log ambiguous, no reveal.
# 1 window: focus, wait 1000 ms, reveal the session tab only if still foreground.
param([string]$Uri)
$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'Common.ps1')

$logDir = Join-Path $env:TEMP 'claude-notify'
$log = Join-Path $logDir 'focus.log'
function Write-CnLog([string]$s) {
    try {
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        Add-Content -Path $log -Value ("{0} {1}" -f (Get-Date -Format s), $s)
    } catch {}
}

$p = @{}
$q = ($Uri -split '\?', 2)[1]
foreach ($kv in ("$q" -split '&')) {
    $k, $v = $kv -split '=', 2
    if ($k) { $p[$k] = [Uri]::UnescapeDataString("$v") }
}
$root = $p['root']; $session = $p['session']
if (-not $root) { Write-CnLog "no root in link"; exit 0 }

$wins = @([CcWin]::FindAll($root))
if ($wins.Count -eq 0) { Write-CnLog "no window for root '$root'"; exit 0 }

$h = $wins[0]
$ok = [CcWin]::Focus($h)
if ($wins.Count -gt 1) { Write-CnLog "ambiguous: $($wins.Count) windows for root '$root' focused=$ok"; exit 0 }
Write-CnLog "root='$root' session='$session' focused=$ok"
if (-not $ok) { exit 0 }

if ($session -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
    # VS Code routes URLs to the last-focused window; give it time to register the focus change.
    Start-Sleep -Milliseconds 1000
    if ([CcWin]::Foreground() -eq $h) {
        Start-Process "vscode://anthropic.claude-code/open?session=$session"
        Write-CnLog "revealed session $session"
    } else {
        Write-CnLog "focus lost before reveal; skipped"
    }
} else {
    Write-CnLog "invalid session id; no reveal"
}
exit 0
