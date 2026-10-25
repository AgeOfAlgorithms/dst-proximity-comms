# Watches DST's client_log.txt for "[PCTEST] SHOT <name>" and takes a Steam screenshot (F12) of DST for each, copied
# as <out>/<name>.jpg.
param([string]$Log, [string]$Out, [int]$Seconds = 300, [switch]$Fresh)
# (-Fresh: only lines the log gets from now on - a retake in a running game)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int cmd);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hwnd, out RECT r);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hwnd, ref POINT p);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
}
"@
New-Item -ItemType Directory -Force $Out | Out-Null
$seen = @{}
$skip = 0
if ($Fresh -and (Test-Path $Log)) { $skip = @(Get-Content $Log -ErrorAction SilentlyContinue).Count }
$until = (Get-Date).AddSeconds($Seconds)
# Steam's screenshot key (F12) on the DST window - Steam's overlay sees DST's frames, which no screen capture here
# does (ANGLE: black) - then the newest picture in Steam's DST screenshot folder, copied as <name>.jpg
$steamShots = Get-ChildItem "C:\Program Files (x86)\Steam\userdata\*\760\remote\322330\screenshots" -Directory -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName
function Newest() {
    $dirs = Get-ChildItem "C:\Program Files (x86)\Steam\userdata\*\760\remote\322330\screenshots" -Directory -ErrorAction SilentlyContinue
    $dirs | ForEach-Object { Get-ChildItem $_.FullName -File -Filter *.jpg -ErrorAction SilentlyContinue } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
}
function Shot($name) {
    $p = Get-Process dontstarve_steam_x64 -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
    if (-not $p) { Write-Output "no window for $name"; return }
    $h = $p.MainWindowHandle
    [Win]::ShowWindow($h, 9) | Out-Null                      # (restore if minimized)
    [Win]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)          # (an Alt tap lets a background process bring a window up)
    [Win]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
    [Win]::SetForegroundWindow($h) | Out-Null
    Start-Sleep -Milliseconds 250
    $before = Newest
    [Win]::keybd_event(0x7B, 0x58, 0, [UIntPtr]::Zero)       # F12 down, up
    Start-Sleep -Milliseconds 60
    [Win]::keybd_event(0x7B, 0x58, 2, [UIntPtr]::Zero)
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Milliseconds 200
        $now = Newest
        if ($now -and (-not $before -or $now.FullName -ne $before.FullName)) {
            Start-Sleep -Milliseconds 300
            Copy-Item $now.FullName (Join-Path $Out "$name.jpg") -Force
            Write-Output "shot $name <- $($now.Name)"
            return
        }
    }
    Write-Output "no Steam screenshot for $name"
}
while ((Get-Date) -lt $until) {
    if (Test-Path $Log) {
        $text = @(Get-Content $Log -ErrorAction SilentlyContinue) | Select-Object -Skip $skip
        foreach ($m in ($text | Select-String -Pattern '\[PCTEST\] SHOT (\S+)')) {
            $name = $m.Matches[0].Groups[1].Value
            if (-not $seen.ContainsKey($name)) { $seen[$name] = $true; Shot $name }
        }
        if ($text | Select-String -SimpleMatch '[PCTEST] DONE') { break }
    }
    Start-Sleep -Milliseconds 300
}
