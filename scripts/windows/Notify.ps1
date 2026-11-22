# Show the toast + flash + sound for one record on stdin. Windows PowerShell 5.1. Pure ASCII.
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

$rec = @{}
try { $rec = Read-CnStdinRecord } catch { Write-CnLog "stdin error: $($_.Exception.Message)"; exit 0 }
$ev = "$($rec['event'])"
$session = "$($rec['session'])"
$root = "$($rec['root'])"
if (-not $ev) { Write-CnLog 'empty record'; exit 0 }

# Window-title name: the worktree folder when it has its own window, else the repo root.
$match = $root
try { $match = Resolve-CnRoot $root "$($rec['rawroot'])" } catch { Write-CnLog "resolve failed: $($_.Exception.Message)" }

# Silent while the user is looking at this session's tab.
try {
    $fg = [CcWin]::Title([CcWin]::Foreground())
    if (Test-CnWatching $fg $match "$($rec['tabtitle'])") { Write-CnLog "watching event=$ev session=$session"; exit 0 }
} catch { Write-CnLog "watch check failed: $($_.Exception.Message)" }

try { Register-CnHandlers (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) } catch { Write-CnLog "register failed: $($_.Exception.Message)" }

$tag = $session
if ($tag.Length -gt 64) { $tag = $tag.Substring(0, 64) }
try {
    [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
    $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
    $doc.LoadXml((New-CnToastXml $rec (Get-CnLink $rec)))
    $toast = New-Object Windows.UI.Notifications.ToastNotification $doc
    $toast.Tag = $tag
    $toast.Group = $CnGroup
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($CnAppId).Show($toast)
    Write-CnLog "toast event=$ev session=$session root=$root match=$match"
} catch { Write-CnLog "toast failed: $($_.Exception.Message)" }

# The session may have moved on while this script started (clear ran before Show):
# the marker is gone, so take the toast back down and skip flash and sound.
try {
    if (Test-CnStaleToast $ev "$($rec['marker'])") {
        [Windows.UI.Notifications.ToastNotificationManager]::History.Remove($tag, $CnGroup, $CnAppId)
        Write-CnLog "stale: marker gone, removed toast session=$session"
        exit 0
    }
} catch { Write-CnLog "stale check failed: $($_.Exception.Message)" }

try {
    $n = 0
    if ($match) { foreach ($h in [CcWin]::FindAll($match)) { [CcWin]::Flash($h); $n++ } }
    Write-CnLog "flashed $n"
} catch { Write-CnLog "flash failed: $($_.Exception.Message)" }

try {
    $wav = if ($ev -eq 'done') { 'Windows Notify Email.wav' } else { 'Windows Notify Messaging.wav' }
    $path = Join-Path $env:WINDIR "Media\$wav"
    if (Test-Path $path) {
        (New-Object System.Media.SoundPlayer $path).PlaySync()
    } else {
        [System.Media.SystemSounds]::Exclamation.Play()
        Start-Sleep -Milliseconds 600
    }
} catch { Write-CnLog "sound failed: $($_.Exception.Message)" }
exit 0
