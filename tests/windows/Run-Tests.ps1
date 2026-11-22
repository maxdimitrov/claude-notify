# Tests for scripts/windows/Common.ps1. Run under Windows PowerShell 5.1:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/windows/Run-Tests.ps1
# Pure ASCII: Cyrillic is built from code points.
$ErrorActionPreference = 'Stop'
$script:fail = 0
function Assert-Eq($Name, $Actual, $Expected) {
    if ("$Actual" -ceq "$Expected") { Write-Host "ok   $Name" }
    else { Write-Host "FAIL $Name`n  expected: [$Expected]`n  actual:   [$Actual]"; $script:fail++ }
}
function Assert-True($Name, $Cond) { Assert-Eq $Name ([bool]$Cond) 'True' }

. (Join-Path $PSScriptRoot '..\..\scripts\windows\Common.ps1')
. (Join-Path $PSScriptRoot '..\..\scripts\windows\Common.ps1')   # second dot-source must not throw
Assert-True 'CcWin type loaded' ('CcWin' -as [type])

$cyr = -join ([char[]](0x0410,0x043D,0x0430,0x043B,0x0438,0x0437,0x20,0x043D,0x0430,0x20,0x0441,0x043C,0x0435,0x0442,0x043A,0x0430))

# Read-CnRecord
$text = "event=done`nsession=abc`nline1=x - $cyr`nline2=a=b`n"
$rec = Read-CnRecord ([Text.Encoding]::UTF8.GetBytes($text))
Assert-Eq 'record cyrillic line1' $rec['line1'] "x - $cyr"
Assert-Eq 'record split on first =' $rec['line2'] 'a=b'
Assert-Eq 'record event' $rec['event'] 'done'
$rec2 = Read-CnRecord ([Text.Encoding]::UTF8.GetBytes("event=done`r`nroot=claude`r`n"))
Assert-Eq 'record CRLF tolerated' $rec2['root'] 'claude'

# Get-CnLink
Assert-Eq 'link' (Get-CnLink @{ root = 'my repo'; session = 'sid-1'; entrypoint = 'claude-vscode'; rawroot = 'wt 1' }) 'claude-focus:?root=my%20repo&session=sid-1&ep=claude-vscode&raw=wt%201'
Assert-Eq 'link without ep/raw' (Get-CnLink @{ root = 'r'; session = 's' }) 'claude-focus:?root=r&session=s&ep=&raw='

# Resolve-CnRoot (fake finder: name -> handles)
$wins = @{ 'repo' = @([IntPtr]1, [IntPtr]2); 'wt1' = @([IntPtr]3); 'wt2' = @([IntPtr]4, [IntPtr]5) }
$finder = { param($n) if ($wins.ContainsKey($n)) { $wins[$n] } else { @() } }
Assert-Eq 'resolve rawroot with one window' (Resolve-CnRoot 'repo' 'wt1' $finder) 'wt1'
Assert-Eq 'resolve rawroot with no window' (Resolve-CnRoot 'repo' 'wt9' $finder) 'repo'
Assert-Eq 'resolve rawroot with two windows' (Resolve-CnRoot 'repo' 'wt2' $finder) 'repo'
Assert-Eq 'resolve rawroot equals root' (Resolve-CnRoot 'repo' 'repo' $finder) 'repo'
Assert-Eq 'resolve empty rawroot' (Resolve-CnRoot 'repo' '' $finder) 'repo'
Assert-Eq 'resolve null finder output' (Resolve-CnRoot 'repo' 'wt1' { param($n) $null }) 'repo'

# Test-CnStaleToast
$mk = Join-Path ([IO.Path]::GetTempPath()) ("cn-test-{0}.pending" -f $PID)
Set-Content -Path $mk -Value 'toast'
Assert-Eq 'stale: marker present' (Test-CnStaleToast 'permission' $mk) 'False'
Remove-Item -Path $mk -Force
Assert-Eq 'stale: marker gone' (Test-CnStaleToast 'permission' $mk) 'True'
Assert-Eq 'stale: ping marker gone' (Test-CnStaleToast 'ping' $mk) 'True'
Assert-Eq 'stale: done never' (Test-CnStaleToast 'done' $mk) 'False'
Assert-Eq 'stale: no marker path' (Test-CnStaleToast 'permission' '') 'False'

# New-CnToastXml
$link = Get-CnLink @{ root = 'claude'; session = 's1' }
$perm = @{ event = 'permission'; title = 'Claude needs permission'; line1 = "claude - $cyr"; line2 = 'Allow Bash?' }
$x = [xml](New-CnToastXml $perm $link)
Assert-Eq 'permission scenario' $x.toast.scenario 'reminder'
Assert-Eq 'permission launch' $x.toast.launch $link
Assert-Eq 'permission activationType' $x.toast.activationType 'protocol'
$acts = @($x.toast.actions.action)
Assert-Eq 'permission action count' $acts.Count 2
Assert-Eq 'go action content' $acts[0].content 'Go to session'
Assert-Eq 'go action arguments' $acts[0].arguments $link
Assert-Eq 'dismiss action type' $acts[1].activationType 'system'
Assert-Eq 'dismiss action args' $acts[1].arguments 'dismiss'
Assert-Eq 'audio silent' $x.toast.audio.silent 'true'
Assert-Eq 'cyrillic text node' (@($x.toast.visual.binding.text)[1]) "claude - $cyr"
$q = [xml](New-CnToastXml @{ event = 'question'; title = 't'; line1 = 'l'; line2 = 'l2' } $link)
Assert-Eq 'question scenario' $q.toast.scenario 'reminder'
$p = [xml](New-CnToastXml @{ event = 'ping'; title = 'Claude needs you'; line1 = 'l'; line2 = 'l2' } $link)
Assert-Eq 'ping scenario' $p.toast.scenario 'reminder'
Assert-Eq 'ping go action' ((@($p.toast.actions.action))[0].content) 'Go to session'
$done = [xml](New-CnToastXml @{ event = 'done'; title = 'Claude is done'; line1 = 'r'; line2 = 'x' } $link)
Assert-Eq 'done duration' $done.toast.duration 'long'
Assert-Eq 'done no scenario' ($done.toast.HasAttribute('scenario')) 'False'
Assert-Eq 'done launch' $done.toast.launch $link
Assert-Eq 'done no actions' (@($done.toast.SelectNodes('actions')).Count) '0'
Assert-Eq 'done audio silent' $done.toast.audio.silent 'true'
$raw = '<b> & "q" ''a'''
$e = [xml](New-CnToastXml @{ event = 'done'; title = 't'; line1 = 'l'; line2 = $raw } 'claude-focus:?root=a&session=b')
Assert-Eq 'escaped text roundtrip' (@($e.toast.visual.binding.text)[2]) $raw
Assert-Eq 'escaped link roundtrip' $e.toast.launch 'claude-focus:?root=a&session=b'

$esc = [string][char]27
$cx = [xml](New-CnToastXml @{ event = 'done'; title = 't'; line1 = 'l'; line2 = ($esc + '[31mred' + $esc + '[0m' + [char]7 + 'x') } 'l')
Assert-Eq 'control chars stripped' (@($cx.toast.visual.binding.text)[2]) '[31mred[0mx'

# Test-CnWatching
Assert-True 'watch unicode ellipsis' (Test-CnWatching ('Desktop and audio' + [char]0x2026 + ' - claude - Visual Studio Code') 'claude' 'Desktop and audio notifications')
Assert-True 'watch truncated title' (Test-CnWatching 'Desktop and audio notifi. - claude - Visual Studio Code' 'claude' 'Desktop and audio notifications for input')
Assert-True 'watch exact title' (Test-CnWatching 'Notifications - claude - Visual Studio Code' 'claude' 'Notifications')
Assert-True 'watch case-insensitive' (Test-CnWatching 'notifications - CLAUDE - visual studio code' 'claude' 'Notifications')
Assert-True 'watch ellipsis' (Test-CnWatching 'Desktop and audio... - claude - Visual Studio Code' 'claude' 'Desktop and audio notifications')
Assert-True 'not watching other file' (-not (Test-CnWatching 'notify.ps1 - claude - Visual Studio Code' 'claude' 'Notifications'))
Assert-True 'not watching other root' (-not (Test-CnWatching 'Notifications - mailroom - Visual Studio Code' 'claude' 'Notifications'))
Assert-True 'not watching empty tab title' (-not (Test-CnWatching 'Notifications - claude - Visual Studio Code' 'claude' ''))
Assert-True 'not watching non-vscode' (-not (Test-CnWatching 'Notifications - Firefox' 'claude' 'Notifications'))

# Every backend script parses under this PowerShell (5.1).
foreach ($f in 'Common.ps1', 'Notify.ps1', 'Clear.ps1', 'Focus.ps1') {
    $errs = $null; $tokens = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot "..\..\scripts\windows\$f"), [ref]$tokens, [ref]$errs)
    Assert-Eq "parses: $f" (@($errs).Count) '0'
}

# Register-CnHandlers (override key only; never the real Classes)
$testRoot = 'HKCU:\Software\ClaudeNotifyTest'
$ck = "$testRoot\Classes"
try {
    Register-CnHandlers 'C:\p\1' $ck
    $cmd = (Get-ItemProperty "$ck\claude-focus\shell\open\command").'(default)'
    Assert-True 'command has Focus.ps1 path' ($cmd.Contains('C:\p\1\scripts\windows\Focus.ps1'))
    Assert-True 'command has conhost headless' ($cmd.StartsWith('conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File'))
    Assert-True 'command ends with %1' ($cmd.EndsWith('"%1"'))
    Assert-Eq 'protocol default' (Get-ItemProperty "$ck\claude-focus").'(default)' 'URL:Claude Code focus'
    Assert-True 'URL Protocol present' ($null -ne (Get-ItemProperty "$ck\claude-focus").'URL Protocol')
    $aum = Get-ItemProperty "$ck\AppUserModelId\$CnAppId"
    Assert-Eq 'aumid DisplayName' $aum.DisplayName 'Claude Code'
    Assert-Eq 'aumid IconUri' $aum.IconUri 'C:\p\1\assets\icon.png'
    Register-CnHandlers 'C:\p\2' $ck
    $cmd = (Get-ItemProperty "$ck\claude-focus\shell\open\command").'(default)'
    Assert-True 're-registered to new root' ($cmd.Contains('C:\p\2\scripts\windows\Focus.ps1') -and -not $cmd.Contains('C:\p\1'))
    Assert-Eq 'icon repointed' (Get-ItemProperty "$ck\AppUserModelId\$CnAppId").IconUri 'C:\p\2\assets\icon.png'
} finally {
    Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
Assert-True 'test key removed' (-not (Test-Path $testRoot))

if ($script:fail -gt 0) { Write-Host "$script:fail FAILED"; exit 1 }
Write-Host 'ALL PASSED'; exit 0
