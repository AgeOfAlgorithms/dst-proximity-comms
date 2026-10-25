# Publishing to the Steam Workshop

- **Title:** Proximity Comms: Text and Voice Chat
- **Description:** `description.txt` (Steam's BBCode), pasted on the item's page (Edit title & description).
- **Picture:** `preview.png` (512 x 512). The mod's icon in the game is `modicon.tex` / `modicon.xml` at the repo root
  (both made by `python tools/make_icon.py`; `tools/ktex.py` writes Klei's texture format).
- **Tags:** the uploader offers DST's own (e.g. "all_clients_require_mod", "utility", "tweak", "interface").

How: DST mods are uploaded with Klei's **Don't Starve Mod Tools** (Steam, Library > Tools) - its Mod Uploader picks
the mod's folder (copy only what `tools/install.sh` copies: `modinfo.lua`, `modmain.lua`, `modicon.tex`,
`modicon.xml`, `scripts/` - never `tools/`). Upload it hidden or friends-only first, try it with a friend, then make
it public. After the first upload:
- put the item's page (`https://steamcommunity.com/sharedfiles/filedetails/?id=<id>`) into Koetama's built-in
  profile `url` (`koetama/app/crates/kd-games/src/profiles/dont-starve-together-proximity-comms.json`, and the copy
  in this repo's `koetama/`) and Koetama's README table - until then they point at the Workshop's search;
- Koetama's release with the HTTP fix (100 Continue) should be out before players use voice.
