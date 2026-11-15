#!/bin/sh
# One automated in-game run (dev only): installs the mod and the dev test mod, starts a silent test Koetama (debug
# build, this repo's profile, chat translated into English, and a "spoken" line piped in SPOKEN_AFTER s after the
# session starts), then DST, which hosts an offline world on save slot 9, spawns and runs the scripted session
# (proxcomms_devtest/modmain.lua). Prints the [PCTEST] lines and Lua errors at the end; Koetama's own status lines are
# in <scratch>/koetama_test.txt. Needs modsettings.lua to ForceEnableMod both mods. DST starts without taking the focus
# and its screenshots are Windows Graphics Capture frames of its window (tools/devtest/dstwin.py: no window brought up,
# no key pressed; the old Steam-F12 way, tools/devtest/shots.ps1, brought DST to the top for every shot).
# Run from the repo root (Git Bash on Windows): KOETAMA=<path to a koetama build> sh tools/devtest/run.sh <scratch dir>
# (DST: the default Steam folder unless DST is set; the log: DST's folder in this user's Documents, wherever Windows
# keeps it.)
OUT="${1:?a scratch folder}"
SPOKEN_AFTER="${SPOKEN_AFTER:-14}"
DST="${DST:-/c/Program Files (x86)/Steam/steamapps/common/Don't Starve Together}"
KOETAMA="${KOETAMA:?set KOETAMA to a koetama build (e.g. koetama/app/target/debug/koetama.exe)}"
DOCS="$(cygpath -u "$(powershell -NoProfile -Command "[Environment]::GetFolderPath('MyDocuments')" | tr -d '\r')")"
LOG="$DOCS/Klei/DoNotStarveTogether/client_log.txt"
# (a python with windows_capture and opencv: the screenshots by Windows Graphics Capture, tools/devtest/dstwin.py)
WINPY="${WINPY:-/c/Users/seann/miniconda3/envs/teardown/python.exe}"
taskkill //IM dontstarve_steam_x64.exe //F >/dev/null 2>&1
sleep 2
rm -f "$LOG"
sh tools/install.sh
rm -rf "$DST/mods/proxcomms_devtest" && cp -r tools/devtest/proxcomms_devtest "$DST/mods/"
# (SCENE_DIR=<folder>: scenes of another mod's repo too, e.g. the Chatty Slime's tools/devtest)
[ -n "$SCENE_DIR" ] && cp "$SCENE_DIR"/*.lua "$DST/mods/proxcomms_devtest/"
# (SHOTS=1: the screenshots' scenes; each SHOT line's frame captured from the DST window - into $OUT/shots)
# (SCENE=<name>: tools/devtest/proxcomms_devtest/<name>.lua instead of the checks, with its screenshots too)
[ -n "$SHOTS" ] && SCENE=shots
if [ -n "$SCENE" ]; then
    echo "$SCENE" > "$DST/mods/proxcomms_devtest/$SCENE.txt"
    "$WINPY" tools/devtest/dstwin.py shots --log "$(cygpath -w "$LOG")" --out "$(cygpath -w "$OUT/shots")"         --seconds 400 > "$OUT/shots.txt" 2>&1 &
fi
mkdir -p "$OUT/kprof" && cp koetama/dont-starve-together-proximity-comms.json "$OUT/kprof/"
# (TEST_PORT=<port>, default 47181: the test Koetama and the game on their own port - a Koetama the user runs keeps the
# profile's 47170; TEST_PORT=47170 for the profile's own)
TEST_PORT="${TEST_PORT:-47181}"
# (a profile file whose id a built-in profile has is skipped - Koetama has this one built in: on another port the copy
# gets an id of its own, and the test Koetama plays that)
GAME_ID=dont-starve-together-proximity-comms
if [ "$TEST_PORT" != 47170 ]; then
    GAME_ID=dst-proxcomms-devtest       # (a profile id: 3-40 of a-z 0-9 -)
    sed -i "s/\"port\": 47170/\"port\": $TEST_PORT/; s/\"id\": \"dont-starve-together-proximity-comms\"/\"id\": \"$GAME_ID\"/" \
        "$OUT/kprof/dont-starve-together-proximity-comms.json"
fi
echo "return $TEST_PORT" > "$DST/mods/proxcomms_devtest/port.lua"
# (FAKE_LLM=1: Koetama's agents ask tools/devtest/fake_llm.py - SCENE=agents)
LLM_ARGS=""
if [ -n "$FAKE_LLM" ]; then
    LLM_PORT=47999
    ( python tools/devtest/fake_llm.py $LLM_PORT > "$OUT/fake_llm.txt" 2>&1 & )
    export KOETAMA_LLM_KEY=sk-fake
    LLM_ARGS="--llm-model fake-model --llm-url http://127.0.0.1:$LLM_PORT"
fi
spoken() {
    j=0
    while [ $j -lt 400 ] && ! grep -aq 'PCTEST. start' "$LOG" 2>/dev/null; do sleep 1; j=$((j + 1)); done
    sleep "$SPOKEN_AFTER"
    echo "hello from koetama this is a spoken test line"
    # (until the session is done, not a fixed wait: nothing of this run is left holding the output open after it)
    j=0
    while [ $j -lt 300 ] && ! grep -aq 'PCTEST. DONE' "$LOG" 2>/dev/null; do sleep 2; j=$((j + 1)); done
}
( spoken 2>/dev/null | KOETAMA_PROFILES_DIR="$(cygpath -w "$OUT/kprof")" "$KOETAMA" --cli --game "$GAME_ID" \
    --type --volume 0 --lang en --translate-into en --seconds 600 $LLM_ARGS > "$OUT/koetama_test.txt" 2>&1 & )
sleep 2
# (DST's exe straight, its window not activated: it doesn't take the user's screen - the user, 2026-11-06)
"$WINPY" tools/devtest/dstwin.py launch
sleep 30
i=0
while [ $i -lt 200 ]; do
  grep -aq 'PCTEST. DONE' "$LOG" 2>/dev/null && break
  i=$((i + 1))
  sleep 3
done
grep -a 'PCTEST\|LUA ERROR\|Proximity Comms\]' "$LOG"
sleep 3       # (the last screenshot saved before its watcher goes)
# (what this run started: the fake model and the test Koetama - matched by their command lines, so a Koetama the user
# runs is never touched)
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { \$_.CommandLine -like '*tools/devtest/fake_llm.py*' -or \$_.CommandLine -like '*--cli --game *--seconds 600*' -or \$_.CommandLine -like '*devtest*shots.ps1*' -or \$_.CommandLine -like '*devtest*dstwin.py*' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }" >/dev/null 2>&1
