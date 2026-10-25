#!/bin/sh
# Copies the mod (only what the game loads) into DST's mods folder as "proxcomms" (local development), named
# "... (local dev)" in the game's mod list. For playing with others, enable the Workshop copy instead.
# Run from the repo root: sh tools/install.sh
GAME="/c/Program Files (x86)/Steam/steamapps/common/Don't Starve Together"
DST="${DST:-$GAME}"
DEST="$DST/mods/proxcomms"
rm -rf "$DEST"
mkdir -p "$DEST"
cp modinfo.lua modmain.lua "$DEST/"
# (named apart from the Workshop copy: a world must run the Workshop one for others to join - DST downloads only that)
sed -i 's/^name = "\(.*\)"$/name = "\1 (local dev)"/' "$DEST/modinfo.lua"
cp -r scripts "$DEST/"
mkdir -p "$DEST/images" && cp images/pc_wheel.xml images/pc_wheel.tex images/pc_bubble.xml images/pc_bubble.tex images/NotoEmoji-OFL.txt "$DEST/images/"
mkdir -p "$DEST/fonts" && cp fonts/pc_pangolin.zip fonts/Pangolin-OFL.txt "$DEST/fonts/"
[ -f modicon.tex ] && cp modicon.tex modicon.xml "$DEST/"
diff -r scripts "$DEST/scripts" >/dev/null && echo "installed: $DEST"
