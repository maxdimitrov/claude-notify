# Remove the session's toast and stop the taskbar flash. Windows PowerShell 5.1. Pure ASCII.
param([string]$Session, [string]$Root)
$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'Common.ps1')

$logDir = Join-Path $env:TEMP 'claude-notify'
$log = Join-Path $logDir 'notify.log'
function Write-CnLog([string]$s) {
    try {
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        Add-Content -Path $log -Value ("{0} {1}" -f (Get-Date -Format s), $s)
    } catch {}
}

try {
    [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    $tag = "$Session"
    if ($tag.Length -gt 64) { $tag = $tag.Substring(0, 64) }
    [Windows.UI.Notifications.ToastNotificationManager]::History.Remove($tag, $CnGroup, $CnAppId)
    Write-CnLog "cleared session=$Session"
} catch { Write-CnLog "clear failed: $($_.Exception.Message)" }

try {
    if ($Root) { foreach ($h in [CcWin]::FindAll($Root)) { [CcWin]::StopFlash($h) } }
} catch { Write-CnLog "stopflash failed: $($_.Exception.Message)" }
exit 0
