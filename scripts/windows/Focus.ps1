# Handler for claude-focus: links (toast click). Windows PowerShell 5.1. Pure ASCII.
# claude-focus:?root=<repo folder name>&session=<session uuid>&ep=<entrypoint>&raw=<uncut folder name>
# Window name: raw (worktree window) when it differs from root and exactly one window has it, else root.
# 0 windows: log. >1: focus the first, log ambiguous, no reveal.
# 1 window: focus; reveal only for VS Code sessions (ep=claude-vscode): wait 1000 ms,
# then reveal the session tab only if still foreground.
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
$root = $p['root']; $session = $p['session']; $ep = "$($p['ep'])"; $raw = "$($p['raw'])"
if (-not $root) { Write-CnLog "no root in link"; exit 0 }

$match = $root
try { $match = Resolve-CnRoot $root $raw } catch { Write-CnLog "resolve failed: $($_.Exception.Message)" }

$wins = @([CcWin]::FindAll($match))
if ($wins.Count -eq 0) { Write-CnLog "no window for root '$match'"; exit 0 }

$h = $wins[0]
$ok = [CcWin]::Focus($h)
if ($wins.Count -gt 1) { Write-CnLog "ambiguous: $($wins.Count) windows for root '$match' focused=$ok"; exit 0 }
Write-CnLog "root='$match' session='$session' ep='$ep' focused=$ok"
if (-not $ok) { exit 0 }

# Terminal / other sessions: the reveal link would open a duplicate of the session in VS Code.
if ($ep -ne 'claude-vscode') { Write-CnLog "no reveal: entrypoint=$ep"; exit 0 }

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
