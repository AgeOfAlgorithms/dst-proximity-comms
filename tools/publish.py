"""Publishes the mod to its Workshop item (3819346216) through the running Steam client - the files only, with change
notes; the item's title, description, preview and visibility stay as they are.

    python tools/publish.py --notes <file with the change notes (BBCode)> [--dry-run]

Stages what the game loads in dist/proxcomms (never the repo's tools, docs or the dev test mod), checks the staged
modinfo.lua's version is the code's, then calls Steam's Workshop API (ISteamUGC: StartItemUpdate, SetItemContent,
SubmitItemUpdate) from the steam_api64.dll that ships with DST, as the logged-in Steam user (no password here). While it
runs, Steam shows the user as in Don't Starve Together. --dry-run only stages.
mod.manifest is written into the staged folder (DST's Mod Uploader makes it; DST loads a Workshop mod's scripts only
when their paths are in it - without it a server fails to start, "module 'proxcomms/config' not found", 0.1.3 on
2026-10-16): "MNFS", version 1, the file count, then each file's path hash (sdbm of the lower-case path with "/",
every file but the manifest; read from 12 Workshop mods' manifests, every hash matched).
The item's tags are kept, but for "version:<x>", which is set to the version uploaded: DST reads the mod's Workshop
version from that tag, calls a mod whose modinfo.lua differs out of date, and turns players away from a server running
it (DST's own uploader sets it; this script's 0.1.3 did not, 2026-10-16: the item stayed "updatable").
"""
import argparse
import ctypes
import os
import re
import shutil
import struct
import sys
import time

APP_ID = 322330
ITEM_ID = 3819346216
DLL = r"C:\Program Files (x86)\Steam\steamapps\common\Don't Starve Together\bin64\steam_api64.dll"
ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
STAGE = os.path.join(ROOT, "dist", "proxcomms")
FILES = ["modinfo.lua", "modmain.lua", "modicon.tex", "modicon.xml", "LICENSE", "README.md",
         "images/pc_wheel.xml", "images/pc_wheel.tex", "images/pc_bubble.xml", "images/pc_bubble.tex",
         "images/NotoEmoji-OFL.txt", "fonts/pc_pangolin.zip", "fonts/Pangolin-OFL.txt"]
DIRS = ["scripts"]
SUBMIT_RESULT = 3400 + 4      # SubmitItemUpdateResult_t's callback id (k_iSteamUGCCallbacks + 4)
QUERY_RESULT = 3400 + 1       # SteamUGCQueryCompleted_t's
K_EResultOK = 1
STATUS = {0: "invalid", 1: "preparing config", 2: "preparing content", 3: "uploading content",
          4: "uploading preview", 5: "committing changes"}


def sdbm(s):
    h = 0
    for c in s:
        h = (ord(c) + (h << 6) + (h << 16) - h) & 0xFFFFFFFF
    return h


def manifest(folder):
    """mod.manifest for a folder's files (see the top)"""
    paths = sorted(os.path.relpath(os.path.join(r, f), folder).replace("\\", "/").lower()
                   for r, _, fs in os.walk(folder) for f in fs if f.lower() != "mod.manifest")
    return b"MNFS" + struct.pack("<II", 1, len(paths)) + b"".join(struct.pack("<I", sdbm(p)) for p in paths)


def stage():
    if os.path.isdir(STAGE):
        shutil.rmtree(STAGE)
    for f in FILES:
        os.makedirs(os.path.dirname(os.path.join(STAGE, f)) or STAGE, exist_ok=True)
        shutil.copy2(os.path.join(ROOT, f), os.path.join(STAGE, f))
    for d in DIRS:
        shutil.copytree(os.path.join(ROOT, d), os.path.join(STAGE, d))
    modinfo = open(os.path.join(STAGE, "modinfo.lua"), encoding="utf-8").read()
    config = open(os.path.join(STAGE, "scripts", "proxcomms", "config.lua"), encoding="utf-8").read()
    v1 = re.search(r'^version = "([^"]+)"', modinfo, re.M).group(1)
    v2 = re.search(r'^C\.VERSION = "([^"]+)"', config, re.M).group(1)
    if v1 != v2:
        raise SystemExit(f"modinfo.lua says {v1}, config.lua says {v2}")
    if "(local dev)" in modinfo:
        raise SystemExit("the staged modinfo.lua is a local dev copy's")
    open(os.path.join(STAGE, "mod.manifest"), "wb").write(manifest(STAGE))
    n = sum(len(fs) for _, _, fs in os.walk(STAGE))
    print(f"staged {n} files in {STAGE} (version {v1})")
    return v1


class QueryCompleted(ctypes.Structure):
    _pack_ = 8
    _fields_ = [("handle", ctypes.c_uint64), ("result", ctypes.c_int32), ("returned", ctypes.c_uint32),
                ("total", ctypes.c_uint32), ("cached", ctypes.c_bool), ("cursor", ctypes.c_char * 256)]


class StringArray(ctypes.Structure):
    _pack_ = 8
    _fields_ = [("strings", ctypes.POINTER(ctypes.c_char_p)), ("count", ctypes.c_int32)]


def wait(api, utils, call, out, callback_id, progress=None):
    failed = ctypes.c_bool(False)
    t0 = time.time()
    while not api.SteamAPI_ISteamUtils_IsAPICallCompleted(utils, call, ctypes.byref(failed)):
        api.SteamAPI_RunCallbacks()
        if progress:
            progress()
        if time.time() - t0 > 600:
            raise SystemExit("no answer from Steam in 10 minutes")
        time.sleep(0.2)
    ok = api.SteamAPI_ISteamUtils_GetAPICallResult(utils, call, ctypes.byref(out), ctypes.sizeof(out), callback_id,
                                                   ctypes.byref(failed))
    if not ok or failed.value:
        raise SystemExit("Steam's call failed")
    return out


def item_tags(api, ugc, utils):
    ids = (ctypes.c_uint64 * 1)(ITEM_ID)
    q = api.SteamAPI_ISteamUGC_CreateQueryUGCDetailsRequest(ugc, ids, 1)
    try:
        r = wait(api, utils, api.SteamAPI_ISteamUGC_SendQueryUGCRequest(ugc, q), QueryCompleted(), QUERY_RESULT)
        if r.result != K_EResultOK or r.returned < 1:
            raise SystemExit(f"Steam did not return the item's tags: EResult {r.result}")
        out = []
        for i in range(api.SteamAPI_ISteamUGC_GetQueryUGCNumTags(ugc, q, 0)):
            buf = ctypes.create_string_buffer(256)
            if api.SteamAPI_ISteamUGC_GetQueryUGCTag(ugc, q, 0, i, buf, 256):
                out.append(buf.value.decode(errors="replace"))
        return out
    finally:
        api.SteamAPI_ISteamUGC_ReleaseQueryUGCRequest(ugc, q)


class SubmitItemUpdateResult(ctypes.Structure):
    _pack_ = 8
    _fields_ = [("result", ctypes.c_int32), ("needs_legal", ctypes.c_bool), ("item", ctypes.c_uint64)]


def publish(notes, version):
    os.environ["SteamAppId"] = os.environ["SteamGameId"] = str(APP_ID)
    api = ctypes.CDLL(DLL)
    api.SteamAPI_Init.restype = ctypes.c_bool
    if not api.SteamAPI_Init():
        raise SystemExit("SteamAPI_Init failed: is Steam running and logged in?")
    try:
        api.SteamAPI_SteamUGC_v015.restype = ctypes.c_void_p
        api.SteamAPI_SteamUtils_v010.restype = ctypes.c_void_p
        ugc, utils = api.SteamAPI_SteamUGC_v015(), api.SteamAPI_SteamUtils_v010()
        api.SteamAPI_ISteamUGC_StartItemUpdate.restype = ctypes.c_uint64
        api.SteamAPI_ISteamUGC_StartItemUpdate.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint64]
        api.SteamAPI_ISteamUGC_SetItemContent.restype = ctypes.c_bool
        api.SteamAPI_ISteamUGC_SetItemContent.argtypes = [ctypes.c_void_p, ctypes.c_uint64, ctypes.c_char_p]
        api.SteamAPI_ISteamUGC_SubmitItemUpdate.restype = ctypes.c_uint64
        api.SteamAPI_ISteamUGC_SubmitItemUpdate.argtypes = [ctypes.c_void_p, ctypes.c_uint64, ctypes.c_char_p]
        api.SteamAPI_ISteamUGC_GetItemUpdateProgress.restype = ctypes.c_int
        api.SteamAPI_ISteamUGC_GetItemUpdateProgress.argtypes = [ctypes.c_void_p, ctypes.c_uint64,
                                                                 ctypes.POINTER(ctypes.c_uint64), ctypes.POINTER(ctypes.c_uint64)]
        U64, P = ctypes.c_uint64, ctypes.c_void_p
        api.SteamAPI_ISteamUGC_CreateQueryUGCDetailsRequest.restype = U64
        api.SteamAPI_ISteamUGC_CreateQueryUGCDetailsRequest.argtypes = [P, ctypes.POINTER(U64), ctypes.c_uint32]
        api.SteamAPI_ISteamUGC_SendQueryUGCRequest.restype = U64
        api.SteamAPI_ISteamUGC_SendQueryUGCRequest.argtypes = [P, U64]
        api.SteamAPI_ISteamUGC_GetQueryUGCNumTags.restype = ctypes.c_uint32
        api.SteamAPI_ISteamUGC_GetQueryUGCNumTags.argtypes = [P, U64, ctypes.c_uint32]
        api.SteamAPI_ISteamUGC_GetQueryUGCTag.restype = ctypes.c_bool
        api.SteamAPI_ISteamUGC_GetQueryUGCTag.argtypes = [P, U64, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_char_p, ctypes.c_uint32]
        api.SteamAPI_ISteamUGC_ReleaseQueryUGCRequest.restype = ctypes.c_bool
        api.SteamAPI_ISteamUGC_ReleaseQueryUGCRequest.argtypes = [P, U64]
        api.SteamAPI_ISteamUGC_SetItemTags.restype = ctypes.c_bool
        api.SteamAPI_ISteamUGC_SetItemTags.argtypes = [P, U64, ctypes.POINTER(StringArray)]
        api.SteamAPI_ISteamUtils_IsAPICallCompleted.restype = ctypes.c_bool
        api.SteamAPI_ISteamUtils_IsAPICallCompleted.argtypes = [ctypes.c_void_p, ctypes.c_uint64, ctypes.POINTER(ctypes.c_bool)]
        api.SteamAPI_ISteamUtils_GetAPICallResult.restype = ctypes.c_bool
        api.SteamAPI_ISteamUtils_GetAPICallResult.argtypes = [ctypes.c_void_p, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_int,
                                                              ctypes.c_int, ctypes.POINTER(ctypes.c_bool)]
        old = item_tags(api, ugc, utils)
        tags = [t for t in old if not t.startswith("version:")] + ["version:" + version]
        print(f"tags: {old} -> {tags}")
        handle = api.SteamAPI_ISteamUGC_StartItemUpdate(ugc, APP_ID, ITEM_ID)
        if not api.SteamAPI_ISteamUGC_SetItemContent(ugc, handle, STAGE.encode("utf-8")):
            raise SystemExit("SetItemContent refused the folder")
        arr = (ctypes.c_char_p * len(tags))(*[t.encode() for t in tags])
        if not api.SteamAPI_ISteamUGC_SetItemTags(ugc, handle, ctypes.byref(StringArray(arr, len(tags)))):
            raise SystemExit("SetItemTags refused the tags")
        call = api.SteamAPI_ISteamUGC_SubmitItemUpdate(ugc, handle, notes.encode("utf-8"))
        failed = ctypes.c_bool(False)
        done, total, last = ctypes.c_uint64(), ctypes.c_uint64(), None
        t0 = time.time()
        while not api.SteamAPI_ISteamUtils_IsAPICallCompleted(utils, call, ctypes.byref(failed)):
            api.SteamAPI_RunCallbacks()
            st = api.SteamAPI_ISteamUGC_GetItemUpdateProgress(ugc, handle, ctypes.byref(done), ctypes.byref(total))
            line = f"{STATUS.get(st, st)} {done.value}/{total.value}"
            if line != last:
                print(line)
                last = line
            if time.time() - t0 > 600:
                raise SystemExit("no answer from Steam in 10 minutes")
            time.sleep(0.2)
        res = SubmitItemUpdateResult()
        ok = api.SteamAPI_ISteamUtils_GetAPICallResult(utils, call, ctypes.byref(res), ctypes.sizeof(res), SUBMIT_RESULT,
                                                       ctypes.byref(failed))
        if not ok or failed.value:
            raise SystemExit("Steam's call failed")
        if res.needs_legal:
            print("Steam says: accept the Workshop legal agreement on the item's page")
        if res.result != K_EResultOK:
            raise SystemExit(f"Steam refused the update: EResult {res.result}")
        print(f"published: https://steamcommunity.com/sharedfiles/filedetails/?id={res.item}")
    finally:
        api.SteamAPI_Shutdown()


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--notes", required=True)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    notes = open(a.notes, encoding="utf-8").read().strip()
    version = stage()
    if not a.dry_run:
        publish(notes, version)
