# Dev only: types one line into DST's console (the ` key) in the running game, and closes the console again.
#   powershell -File tools/devtest/console.ps1 -Line 'kleiloadlua("../mods/proxcomms_devtest/retake.lua")()'
param([string]$Line)
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win2 {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int cmd);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
}
"@
$p = Get-Process dontstarve_steam_x64 -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
if (-not $p) { Write-Output "DST is not running"; exit 1 }
$h = $p.MainWindowHandle
[Win2]::ShowWindow($h, 9) | Out-Null
[Win2]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
[Win2]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
[Win2]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 400
function Key($vk) {
    [Win2]::keybd_event($vk, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 40
    [Win2]::keybd_event($vk, 0, 2, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
}
Key 0xC0                                                      # ` : the console
Start-Sleep -Milliseconds 400
# (SendKeys: + ^ % ~ ( ) { } [ ] are its own; escaped in braces)
$escaped = ($Line.ToCharArray() | ForEach-Object { if ('+^%~(){}[]'.Contains([string]$_)) { "{$_}" } else { [string]$_ } }) -join ''
[System.Windows.Forms.SendKeys]::SendWait($escaped)
Start-Sleep -Milliseconds 200
Key 0x0D                                                      # Enter
Start-Sleep -Milliseconds 400
Key 0xC0                                                      # ` : closed
Write-Output "typed: $Line"
