"""Dev only: DST for the in-game tests without taking the user's screen (the user, 2026-11-06: "do you have to keep
bringing the DST application to the top when you take screenshots? ... Teardown agents don't do this").

    <python with windows_capture and cv2> tools/devtest/dstwin.py launch
        starts DST's exe directly (Steam running, SteamAppId 322330) without activating its window - it doesn't take
        the focus
    <python> tools/devtest/dstwin.py shots --log <client_log.txt> --out <dir> [--seconds 400]
        for every "[PCTEST] SHOT <name>" line the log gets, the DST window's newest frame as <dir>/<name>.jpg, by
        Windows Graphics Capture (it sees the window behind others, never focused, no key pressed; as the Teardown
        mods' tools/run_test.py). Ends at "[PCTEST] DONE" or after --seconds.

The python: C:/Users/seann/miniconda3/envs/teardown/python.exe (has windows_capture and opencv).
"""
import argparse
import ctypes
import os
import re
import subprocess
import sys
import threading
import time
from ctypes import wintypes

GAME = r"C:\Program Files (x86)\Steam\steamapps\common\Don't Starve Together"
EXE = os.path.join(GAME, "bin64", "dontstarve_steam_x64.exe")
SHOT = re.compile(r"\[PCTEST\] SHOT (\S+)")

user32 = ctypes.windll.user32


def windows_of(pid):
    found = []

    @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    def each(h, _):
        p = wintypes.DWORD()
        user32.GetWindowThreadProcessId(h, ctypes.byref(p))
        if p.value == pid and user32.IsWindowVisible(h) and user32.GetWindowTextLengthW(h) > 0:
            found.append(h)
        return True
    user32.EnumWindows(each, 0)
    return found


def dst_window():
    out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq dontstarve_steam_x64.exe", "/FO", "CSV", "/NH"],
                         capture_output=True, text=True).stdout
    for line in out.splitlines():
        parts = line.strip('"').split('","')
        if len(parts) > 1 and parts[1].isdigit():
            hs = windows_of(int(parts[1]))
            if hs:
                return hs[0]
    return None


def launch():
    env = dict(os.environ, SteamAppId="322330", SteamGameId="322330", SteamOverlayGameId="322330")
    si = subprocess.STARTUPINFO()
    si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    si.wShowWindow = 4                          # (SW_SHOWNOACTIVATE: shown, the user's window stays active)
    p = subprocess.Popen([EXE], cwd=os.path.dirname(EXE), env=env, startupinfo=si,
                         creationflags=subprocess.DETACHED_PROCESS)
    # (its PID, last on the line: run.sh closes only the DST it started - never one the user plays)
    print("launched", EXE, "pid", p.pid, flush=True)


class Grabber:
    """the newest frame of one window, by Windows Graphics Capture"""
    def __init__(self, hwnd):
        from windows_capture import WindowsCapture
        self.frame, self.lock = None, threading.Lock()
        cap = WindowsCapture(cursor_capture=False, draw_border=None, window_hwnd=hwnd)

        @cap.event
        def on_frame_arrived(frame, control):
            with self.lock:
                self.frame = frame.frame_buffer.copy()

        @cap.event
        def on_closed():
            pass
        self.control = cap.start_free_threaded()

    def save(self, path):
        import cv2
        with self.lock:
            f = self.frame
        if f is None:
            return False
        cv2.imwrite(path, f[:, :, :3], [cv2.IMWRITE_JPEG_QUALITY, 92])
        return True

    def stop(self):
        try:
            self.control.stop()
        except Exception:
            pass


def shots(log, out, seconds):
    os.makedirs(out, exist_ok=True)
    t0, grab, pos, taken = time.time(), None, 0, 0
    while time.time() - t0 < seconds:
        if grab is None:
            h = dst_window()
            if h:
                try:
                    grab = Grabber(h)
                except Exception as e:          # (the window not ready yet)
                    print("capture not started:", e, flush=True)
        lines = []
        if os.path.exists(log):
            if os.path.getsize(log) < pos:      # (a new log: the game started again)
                pos = 0
            with open(log, "rb") as f:
                f.seek(pos)
                data = f.read()
            if b"\n" in data:
                cut = data.rindex(b"\n") + 1
                pos += cut
                lines = data[:cut].decode("utf-8", "replace").splitlines()
        for line in lines:
            m = SHOT.search(line)
            if m:
                time.sleep(0.15)                # (the frame the game drew after the line)
                name = os.path.join(out, m.group(1) + ".jpg")
                ok = grab is not None and grab.save(name)
                taken += ok
                print(("shot " if ok else "no frame for ") + m.group(1), flush=True)
            if "[PCTEST] DONE" in line:
                if grab:
                    grab.stop()
                print(f"done: {taken} shots", flush=True)
                return
        time.sleep(0.1)
    if grab:
        grab.stop()
    print(f"timed out: {taken} shots", flush=True)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("launch")
    s = sub.add_parser("shots")
    s.add_argument("--log", required=True)
    s.add_argument("--out", required=True)
    s.add_argument("--seconds", type=int, default=400)
    a = ap.parse_args()
    if a.cmd == "launch":
        launch()
    else:
        shots(a.log, a.out, a.seconds)
