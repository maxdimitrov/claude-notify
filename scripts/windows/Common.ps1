# Common library for the claude-notify Windows backend. Dot-source it; do not run it.
# Runs under Windows PowerShell 5.1. Pure ASCII.

$CnAppId = 'maxdimitrov.ClaudeNotify'
$CnGroup = 'claude-code'

# Parse a UTF-8 key=value record (one per line, split on the first '=') into a hashtable.
function Read-CnRecord([byte[]]$Bytes) {
    $r = @{}
    if (-not $Bytes) { return $r }
    $text = (New-Object System.Text.UTF8Encoding($false)).GetString($Bytes)
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    foreach ($line in ($text -split "`n")) {
        $line = $line.TrimEnd("`r")
        $i = $line.IndexOf('=')
        if ($i -gt 0) { $r[$line.Substring(0, $i)] = $line.Substring($i + 1) }
    }
    return $r
}

# Read raw stdin bytes (no console code page involved) and parse them.
function Read-CnStdinRecord {
    $ms = New-Object System.IO.MemoryStream
    $in = [Console]::OpenStandardInput()
    $in.CopyTo($ms)
    return (Read-CnRecord $ms.ToArray())
}

function Get-CnLink([hashtable]$Record) {
    return 'claude-focus:?root=' + [Uri]::EscapeDataString("$($Record['root'])") +
        '&session=' + [Uri]::EscapeDataString("$($Record['session'])")
}

function ConvertTo-CnXml([string]$s) {
    $s = [regex]::Replace($s, '[\x00-\x08\x0B\x0C\x0E-\x1F]', '')
    return [System.Security.SecurityElement]::Escape($s)
}

function New-CnToastXml([hashtable]$Record, [string]$Link) {
    $l = ConvertTo-CnXml $Link
    $t = ConvertTo-CnXml "$($Record['title'])"
    $a = ConvertTo-CnXml "$($Record['line1'])"
    $b = ConvertTo-CnXml "$($Record['line2'])"
    if ("$($Record['event'])" -eq 'done') {
        $open = "<toast duration=`"long`" activationType=`"protocol`" launch=`"$l`">"
        $actions = ''
    } else {
        $open = "<toast scenario=`"reminder`" activationType=`"protocol`" launch=`"$l`">"
        $actions = "<actions><action content=`"Go to session`" activationType=`"protocol`" arguments=`"$l`"/>" +
            "<action content=`"Dismiss`" activationType=`"system`" arguments=`"dismiss`"/></actions>"
    }
    return "$open<visual><binding template=`"ToastGeneric`"><text>$t</text><text>$a</text><text>$b</text></binding></visual>" +
        "$actions<audio silent=`"true`"/></toast>"
}

# True when the foreground window is the session's VS Code window and its first title
# segment (a possibly truncated editor tab title) is a prefix of the session's tab title.
function Test-CnWatching([string]$ForegroundTitle, [string]$Root, [string]$TabTitle) {
    if (-not $TabTitle -or -not $ForegroundTitle -or -not $Root) { return $false }
    $tail = " - $Root - Visual Studio Code"
    if (-not $ForegroundTitle.EndsWith($tail, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    $first = ($ForegroundTitle -split ' - ', 2)[0]
    if ($first.EndsWith([string][char]0x2026)) { $first = $first.Substring(0, $first.Length - 1) }
    elseif ($first.EndsWith('...')) { $first = $first.Substring(0, $first.Length - 3) }
    elseif ($first.EndsWith('.')) { $first = $first.Substring(0, $first.Length - 1) }
    if (-not $first) { return $false }
    return $TabTitle.StartsWith($first, [StringComparison]::OrdinalIgnoreCase)
}

# Create the key if needed and set a value only when it differs.
function Set-CnRegValue([string]$Key, [string]$Name, [string]$Value) {
    if (-not (Test-Path -LiteralPath $Key)) { New-Item -Path $Key -Force | Out-Null }
    $cur = $null
    try { $cur = (Get-ItemProperty -LiteralPath $Key -ErrorAction Stop).$Name } catch {}
    if ($null -eq $cur -or "$cur" -ne $Value) {
        Set-ItemProperty -LiteralPath $Key -Name $Name -Value $Value
    }
}

function Register-CnHandlers([string]$PluginRoot, [string]$ClassesKey = 'HKCU:\Software\Classes') {
    $aum = "$ClassesKey\AppUserModelId\$CnAppId"
    Set-CnRegValue $aum 'DisplayName' 'Claude Code'
    Set-CnRegValue $aum 'IconUri' "$PluginRoot\assets\icon.png"
    $proto = "$ClassesKey\claude-focus"
    Set-CnRegValue $proto '(default)' 'URL:Claude Code focus'
    Set-CnRegValue $proto 'URL Protocol' ''
    $focus = "$PluginRoot\scripts\windows\Focus.ps1"
    Set-CnRegValue "$proto\shell\open\command" '(default)' ('conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}" "%1"' -f $focus)
}

if (-not ('CcWin' -as [type])) {
    Add-Type -TypeDefinition @"
using System; using System.Collections.Generic; using System.Text; using System.Runtime.InteropServices;
public static class CcWin {
    delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [StructLayout(LayoutKind.Sequential)] struct FLASHWINFO { public uint cbSize; public IntPtr hwnd; public uint dwFlags; public uint uCount; public uint dwTimeout; }
    [DllImport("user32.dll")] static extern bool FlashWindowEx(ref FLASHWINFO fi);

    public static string Title(IntPtr h) {
        var sb = new StringBuilder(1024); GetWindowText(h, sb, 1024); return sb.ToString();
    }
    public static IntPtr Foreground() { return GetForegroundWindow(); }

    public static IntPtr[] FindAll(string root) {
        string tail = " - " + root + " - Visual Studio Code";
        string bare = root + " - Visual Studio Code";
        var found = new List<IntPtr>();
        EnumWindows(delegate (IntPtr h, IntPtr l) {
            if (!IsWindowVisible(h)) return true;
            string t = Title(h);
            if (t.EndsWith(tail, StringComparison.OrdinalIgnoreCase) || t.Equals(bare, StringComparison.OrdinalIgnoreCase)) found.Add(h);
            return true;
        }, IntPtr.Zero);
        return found.ToArray();
    }

    static void FlashWith(IntPtr h, uint flags) {
        var fi = new FLASHWINFO();
        fi.cbSize = (uint)Marshal.SizeOf(typeof(FLASHWINFO));
        fi.hwnd = h; fi.dwFlags = flags;
        FlashWindowEx(ref fi);
    }
    // FLASHW_TRAY | FLASHW_TIMERNOFG: taskbar button flashes until the window is focused.
    public static void Flash(IntPtr h) { FlashWith(h, 2 | 12); }
    // FLASHW_STOP
    public static void StopFlash(IntPtr h) { FlashWith(h, 0); }

    public static bool Focus(IntPtr h) {
        if (IsIconic(h)) ShowWindow(h, 9); // SW_RESTORE
        if (SetForegroundWindow(h) && GetForegroundWindow() == h) return true;
        uint fg = GetWindowThreadProcessId(GetForegroundWindow(), IntPtr.Zero);
        uint me = GetCurrentThreadId();
        if (fg != me) AttachThreadInput(me, fg, true);
        BringWindowToTop(h); SetForegroundWindow(h);
        if (fg != me) AttachThreadInput(me, fg, false);
        if (GetForegroundWindow() == h) return true;
        keybd_event(0x12, 0, 0, UIntPtr.Zero); keybd_event(0x12, 0, 2, UIntPtr.Zero);
        SetForegroundWindow(h);
        return GetForegroundWindow() == h;
    }
}
"@
}
