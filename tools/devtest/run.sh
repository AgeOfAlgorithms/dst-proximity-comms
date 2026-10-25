#!/bin/sh
# One automated in-game run (dev only): installs the mod and the dev test mod, starts a silent test Koetama (debug
# build, this repo's profile, chat translated into English, and a "spoken" line piped in SPOKEN_AFTER s after the
# session starts), then DST, which hosts an offline world on save slot 9, spawns and runs the scripted session
# (proxcomms_devtest/modmain.lua). Prints the [PCTEST] lines and Lua errors at the end; Koetama's own status lines are
# in <scratch>/koetama_test.txt. Needs modsettings.lua to ForceEnableMod both mods. (Screenshots: DST renders through
# ANGLE and no screen capture tried here sees its frames - tools/devtest/shots.ps1 is kept for a machine where one does.)
# Run from the repo root (Git Bash on Windows): KOETAMA=<path to a koetama build> sh tools/devtest/run.sh <scratch dir>
# (DST: the default Steam folder unless DST is set; the log: DST's folder in this user's Documents, wherever Windows
# keeps it.)
OUT="${1:?a scratch folder}"
SPOKEN_AFTER="${SPOKEN_AFTER:-14}"
DST="${DST:-/c/Program Files (x86)/Steam/steamapps/common/Don't Starve Together}"
KOETAMA="${KOETAMA:?set KOETAMA to a koetama build (e.g. koetama/app/target/debug/koetama.exe)}"
DOCS="$(cygpath -u "$(powershell -NoProfile -Command "[Environment]::GetFolderPath('MyDocuments')" | tr -d '\r')")"
LOG="$DOCS/Klei/DoNotStarveTogether/client_log.txt"
taskkill //IM dontstarve_steam_x64.exe //F >/dev/null 2>&1
sleep 2
rm -f "$LOG"
sh tools/install.sh
rm -rf "$DST/mods/proxcomms_devtest" && cp -r tools/devtest/proxcomms_devtest "$DST/mods/"
# (SHOTS=1: the screenshots' scenes, and Steam's screenshot key pressed at each - into $OUT/shots)
# (SCENE=<name>: tools/devtest/proxcomms_devtest/<name>.lua instead of the checks, with its screenshots too)
[ -n "$SHOTS" ] && SCENE=shots
if [ -n "$SCENE" ]; then
    echo "$SCENE" > "$DST/mods/proxcomms_devtest/$SCENE.txt"
    powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w tools/devtest/shots.ps1)" -Log "$(cygpath -w "$LOG")"         -Out "$(cygpath -w "$OUT/shots")" -Seconds 400 > "$OUT/shots.txt" 2>&1 &
fi
mkdir -p "$OUT/kprof" && cp koetama/dont-starve-together-proximity-comms.json "$OUT/kprof/"
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
    sleep 600
}
( spoken | KOETAMA_PROFILES_DIR="$(cygpath -w "$OUT/kprof")" "$KOETAMA" --cli --game dont-starve-together-proximity-comms \
    --type --volume 0 --lang en --translate-into en --seconds 600 $LLM_ARGS > "$OUT/koetama_test.txt" 2>&1 & )
sleep 2
start "" "steam://rungameid/322330"
sleep 30
i=0
while [ $i -lt 200 ]; do
  grep -aq 'PCTEST. DONE' "$LOG" 2>/dev/null && break
  i=$((i + 1))
  sleep 3
done
grep -a 'PCTEST\|LUA ERROR\|Proximity Comms\]' "$LOG"
