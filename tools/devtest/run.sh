#!/bin/sh
# One automated in-game run (dev only): installs the mod and the dev test mod, starts a silent test Koetama (debug
# build, this repo's profile, chat translated into English, and a "spoken" line piped in SPOKEN_AFTER s after the
# session starts), then DST, which hosts an offline world on save slot 9, spawns and runs the scripted session
# (proxcomms_devtest/modmain.lua). Prints the [PCTEST] lines and Lua errors at the end; Koetama's own status lines are
# in <scratch>/koetama_test.txt. It turns the mods on in modsettings.lua for the run (ForceEnableMod, put back after).
# DST starts without taking the focus
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
# (ENABLE_MODS="chattyslime ...": more mods to turn on for the run, besides proxcomms and proxcomms_devtest)
# The test turn: run it through the teardown-mods repo's broker (tools/turn.py run --what "..." --minutes 8 -- sh ...),
# which queues it with the Teardown runs (one GPU, one screen capture) and never starts it while the user plays. This
# script keeps to the same rules: it refuses while any DST runs (it never kills DST by name: that could be the user's
# game - the user, 2026-11-15), closes only the DST it started (by its PID), and puts mods/modsettings.lua back.
if tasklist //FI "IMAGENAME eq dontstarve_steam_x64.exe" 2>/dev/null | grep -qi dontstarve; then
    echo "DST is running (the user's game?) - not started"
    exit 2
fi
# (modsettings.lua: the mods forced on for this run, put back afterwards - a trap; and a backup left over from a run
# killed with no trap run (the broker's time cap kills with taskkill /F) is put back first)
MS="$DST/mods/modsettings.lua"
MSBAK="$MS.devtest-backup"
[ -f "$MSBAK" ] && cp "$MSBAK" "$MS" && rm -f "$MSBAK" && echo "modsettings.lua: put back from an earlier run's backup"
cp "$MS" "$MSBAK"
# (what a run starts besides DST: the fake model, the test Koetama, the screenshot watcher - matched by their command
# lines, so a Koetama the user runs is never touched; not the sweep itself, whose command line has the patterns. At the
# start too: a run killed at the broker's cap leaves them running - they are started detached, outside its tree)
sweep() {
    powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { \$_.ProcessId -ne \$PID -and (\$_.CommandLine -like '*tools/devtest/fake_llm.py*' -or \$_.CommandLine -like '*--cli --game *--seconds 600*' -or \$_.CommandLine -like '*devtest*shots.ps1*' -or \$_.CommandLine -like '*devtest*dstwin.py*') } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }" >/dev/null 2>&1
}
sweep
DSTPID=""
cleanup() {
    [ -n "$DSTPID" ] && taskkill //PID "$DSTPID" //F >/dev/null 2>&1
    [ -f "$MSBAK" ] && cp "$MSBAK" "$MS" && rm -f "$MSBAK"
    sweep
}
trap cleanup EXIT
trap 'exit 130' INT TERM
{
    echo ""
    echo "-- (tools/devtest/run.sh, this run only: put back when it ends)"
    for m in proxcomms proxcomms_devtest $ENABLE_MODS; do echo "ForceEnableMod(\"$m\")"; done
} >> "$MS"
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
DSTPID="$("$WINPY" tools/devtest/dstwin.py launch | sed -n 's/.* pid \([0-9]*\)$/\1/p')"
echo "DST started, pid ${DSTPID:-?}"
sleep 30
i=0
while [ $i -lt 200 ]; do
  grep -aq 'PCTEST. DONE' "$LOG" 2>/dev/null && break
  if [ -n "$DSTPID" ] && ! tasklist //FI "PID eq $DSTPID" 2>/dev/null | grep -q " $DSTPID "; then
    echo "DST (pid $DSTPID) closed before the session was done - its log's last lines:"
    tail -5 "$LOG"
    DSTPID=""
    break
  fi
  i=$((i + 1))
  sleep 3
done
grep -a 'PCTEST\|LUA ERROR\|Proximity Comms\]' "$LOG"
sleep 3       # (the last screenshot saved before its watcher goes)
echo "output: $OUT (koetama_test.txt, shots/)"
