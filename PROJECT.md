# Proximity Comms for Don't Starve Together

Proximity text chat for DST (its own bubbles, modes and a per-player history), and with Koetama (the companion app,
github.com/AgeOfAlgorithms/koetama) proximity voice, live captions and offline translation. The port of the Teardown
mod Proximity Comms (github.com/AgeOfAlgorithms/teardown-prox-text-chat-mod): its design and behaviour, not its code
paths.
Started 2026-10-13 from `koetama/docs/handoff-dst-proximity-comms.md`.

## Decisions (the user, 2026-10-13)

- Name **Proximity Comms**; this repo (github.com/AgeOfAlgorithms/dst-proximity-comms). Author in modinfo and the
  Koetama profile: **McPuppetFace**, the Steam account the mods are uploaded with (the user, 2026-11-06; was
  "AgeOfAlgorithms", the GitHub name, and before that "AgeOfAlgorithms(+Opus5.5)" until the user saw it in DST's mod
  list, 2026-10-13: "that looks so weird"; Koetama's window shows each game mod's author). GitHub links stay
  AgeOfAlgorithms.
- **DST's own whisper stays** (our Whisper is dropped): the modes are Whisper (DST's), Speak, Yell (ours), Global
  (DST's Say). One mode for typing and talking.
- **Bubbles: DST's native look**, plus garbled letters at range, scrolling long lines, docking to the screen edge.
- **Ghosts:** as the base game (checked in its scripts: a ghost keeps positive health, `OnMakePlayerGhost` sets
  `RESURRECT_HEALTH`, so `talker:Say` shows its chat normally; only its talk sound is `ghost_LP`; `CraftOooh` is only
  for scripted character quips). So ghosts chat and talk as usual; their voice gets a light effect (reverb, wobble).
- **Ranges (the user, 2026-11-18, 20 % shorter: "reduce the default whisper, speak, and yell distances by 20%"):
  Whisper 6, Speak 14, Yell 26 tiles** (24 / 56 / 104 units; garbled to x1.4 / x1.4 /
  x1.375), the host's mod settings, and admins in game (`/pc range <whisper> <speak> <yell>`, the Chat page; kept in
  the world's save). Whisper < Speak < Yell (C.ranges). Was 8 / 18 / 32 (2026-10-16), before that 8 / 16 for Speak / Yell, Whisper DST's (40 units).
- **Whisper (the user, 2026-10-16: "add garbled zone"):** DST's own (TheNet:Say, whispered; DST shows it within 40
  units, chathistory.lua) in the mod's Whisper range instead: a bubble as a Speak line's (clear, garbled in its
  buffer, revealed walking in), its history line the mod's ("[W]"; DST's OnSay whisper line left out), bubbles on or
  off. Not verified: whether DST's server sends a whisper beyond 40 units at all (the garbled zone ends at 44.8).
- **Wes (the mime; the user, 2026-10-16: "no mime rule ... wrap whatever he says in brackets"):** bubbles in every
  mode, his lines and live words in [brackets] (CL.mimed; the history as said); his voice as anyone's.
- **Caves:** one voice room for the whole world (the master shard keeps it; each shard hands it to its players);
  Speak / Yell / Whisper only meet within a shard (each client lists only the players
  of its own shard as positioned speakers, so the same coordinates in the caves never mix with the surface).
- **Everything in v1:** text chat, Koetama link, voice, captions, translation, the controller wheel, test figures,
  Chinese and Russian.
- **Koetama profile: built into Koetama** (the user, 2026-10-13; koetama `kd-games/src/profiles/`, `lib.rs`
  `builtins()`); `koetama/` here keeps the same file. Its `url` is the Workshop's search for the mod until the item
  exists (then the item's page, in both copies).
- **Bubbles (the user, after trying it, 2026-10-13):** "I don't see any bubbles but I see the words on top of their
  heads. I think that's good enough (the fonts are a bit big though)" - the text is now a fifth smaller than DST's own
  chat (`pc_bubbles.lua` SIZE 28, was 35; Yell x1.2, was x1.3).
- **Bubble style (the user, 2026-10-14):** "put the words in a semi transparent speech bubble and change the font to
  something more easy to read" - the "Clear" style (the default): a dark box (`images/pc_bubble.*`, a 9-slice and a
  tail per side, drawn by `tools/make_bubble.py`, stretched by DST's NineSlice). Then (2026-10-15): "a more modern
  and/or prettier font ... compatible with chinese, russian", "the same font as the teardown prox comm mod" - Pangolin
  (`fonts/pc_pangolin.zip`, built by `tools/make_font.py` from `tools/fonts/pangolin.ttf`: Latin and Cyrillic drawn
  in, outlined as the game's fonts are; Chinese, Japanese, Korean, ∷ and ♪ from the game's outlined fallback fonts;
  loaded by modmain after the mods' prefabs, as mods with fonts do); the box's opacity a setting (0-100 %, 60 %); "the
  pointer located on the bubble where the sound is actually coming from ... moves dynamically" - the tail is on the
  side of the box the speaker is farthest beyond (below over a head; left / right / top for a docked bubble), along it
  toward them, recomputed every frame. The text size was already a setting (70-160 %). "The game's" style (Chat
  page) is the old look: TALKINGFONT, no box. The font's DST format (read from data/databundles/fonts.zip): a zip of
  `font.fnt` (BMFont XML, drawn at size 50) and `font.tex` (KTEX DXT5 with mipmaps), white letters in a black outline.
- **Agents (the user, 2026-10-25: "koetama has updated a lot ... use the teardown mod as reference to implement LLM
  service APIs"):** Koetama 0.5.10-0.5.12's agents (PROTOCOL.md "Large language models: agents") for any DST mod
  through GLOBAL.ProxComms (proxcomms/agents.lua; the Teardown mod's agents.lua and API 17-18 ported, its registry keys
  as Lua calls and callbacks). Whose Koetama: an ADMIN's whose hello names "llm" (its game says so to its shard every
  10 s; the master shard picks one - the one already chosen, else the lowest id - and tells every shard); no other
  player's game gets agents' lines. Agents are per shard (Koetama id "<id>:<shard>"); everything between an agent's
  shard and the brain's goes through the shards. Players' Whisper / Global lines reach the server through the
  speaker's own game ("heard"). Verified in game with Koetama 0.5.12 and a fake model (devtest SCENE=agents,
  tools/devtest/fake_llm.py): the brain chosen, a named line, the reply bubble and history, a function call answered,
  the follow-up. Not verified: caves (two shards), a real model, streaming live words.
- **Agent API 2 (the user, 2026-11-05: port Mochi's features to the Chatty Slime / Salamander):** the Teardown mod's
  API 19 (scores) and 20 (agents hearing agents) for Koetama 0.5.14. `criteria` + `onScores(scores, info)` (true /
  false / nil and `ProxComms.decide` later) + `onSkip`; `ProxComms.scores()` (the brain's "caps" to every shard, from
  its hello's `agent_scores`, resent every 10 s); notes and "you said" go as `context` lines (else Koetama, which never
  scores a turn with a plain event, would answer every note); a `skipped` reply says nothing and engages no one.
  `hearagents` (0-50): every agent line counts (the brain keeps each line's count: the lowest it answers + 1; a say 1),
  the others hear it 1-4 s later (`A.later`, the server's 1 s tick) while the count is at most their `hearagents`.
  The creatures' rules for it (the user, same day): they flee automatically when the AI is off or they are badly hurt,
  otherwise the AI decides between fighting and fleeing; only the host may order an attack; creatures hear each other
  by default, 10 lines in a row.
- **Agent API 3 (the user, 2026-11-15: Koetama's tool-calling update, from the koetama-0e session):** Koetama 0.5.15
  takes up to 32 functions an agent (was 16) and its hello says so (`"agent_functions": 32`; no field: 16 - and an
  agent over the limit is left out, silent). The mod keeps up to 32 (`A.FUNCTIONS_MAX`); the brain reads the hello's
  `agent_functions` (`b.maxFn`) and sends an older Koetama only an agent's first 16 (a log line once per agent);
  the caps carry `functions` to every shard: `ProxComms.agentfunctions()` (16 until then; the Teardown mod's
  `proxchat.agentfunctions`, API 21, the same day). Nothing else changed in Koetama's agent protocol since 0.5.14.
- **Agent API 4 (2026-11-16, for the AI Villagers - the dst-mods-65 session, at the user's request):** `onSay(text,
  info)` in a definition sees each reply on the agent's shard before `A.deliver`: `false` - nothing said, no other
  agent hears it, no `onReply`; a string - said instead; `nil` or an error - as it is. Why: deepseek-flash, told to keep
  quiet, says "NO" / "(NO words)" / "NO WORDS." aloud (the other agents heard and scored it) and puts its own name
  before its line. An agent with `onSay` gets no live words (`A.handle "live"` drops them): they would show what onSay
  may still hold back, and a live bubble stays up to 4 s (`CL.LIVE_LIFE`). Mods check `ProxComms.version >= 4`.
  devtest: `FAKE_LLM_PY=<file>` (another mod's scripted model), the `villagers` scene. Next (Koetama's side, the
  koetama-d4 session): a function result that ends the turn with no follow-up request.
- **Is Koetama up to date (the user, 2026-11-19):** `C.KOETAMA_LATEST` (the newest released Koetama when the mod was
  made - raise it with each Koetama release), or a newer `latest` in Koetama's hello (not sent yet - asked of the
  Koetama session): when Koetama connects, a chat line "up to date (0.5.18)" or "0.5.18 is out (you have 0.5.17)"
  (`K.updateLine`; `K_OLD` below KOETAMA_MIN), also in `/pc koetama` and the settings' Voice page.
- **Agent API 8: personas up to 32 KB, up to 64 functions (2026-11-19, the user via the AI Villagers: "8kb is still too
  small for rules. maybe it should be 32kb", "ok time to increase the functions to 64 then"):** a shard keeps a
  persona up to 32768 bytes and 64 functions; the brain sends the first `agent_persona` bytes (8192 when its hello has
  none: an older Koetama leaves out an agent over it) and the first `agent_functions`; the caps carry `persona`
  (`ProxComms.personamax()`). Definitions in a feed up to DEF_BUDGET_BIG (160 KB) to a Koetama taking 256 KB feeds
  (`b.bigFeeds`: 0.5.17 or agent_state), else DEF_BUDGET. A message to the brain over 12 KB goes in parts (A.PART; "part" RPCs,
  put together by the brain, dropped after 30 s if never whole): DST cuts a mod RPC's long string - the in-game test
  (devtest SCENE=bigdef, 2026-11-19): a 98889-byte definition in one RPC arrived as 33353 bytes; in 9 parts, whole,
  and Koetama 0.5.19 listed it. (Tested with the host as the brain; a dedicated server's RPC over the network not.)
- **Agent API 7: states up to 8 KB (2026-11-18, for the AI Villagers' "Around you" list of up to 50 kinds):** Koetama
  0.5.18 (koetama-3b) takes an agent line's state up to 8192 bytes (2048 before; a longer one becomes "" whole) and
  its hello says `"agent_state": 8192`; it keeps only the newest state in a conversation. The brain reads it
  (`b.maxState`), sends it in the caps (`state`), each shard cuts to it (`A.stateMax`, `ProxComms.statemax()`), and
  the brain cuts again in the feed (a shard's caps late). Feeds: up to 256 KB to Koetama 0.5.17 and later
  (`K.maxBody()`, by the hello's version - no field), 64 KB before.
- **Agent API 6: agents hear garbled lines in the buffer (2026-11-17, for the AI Villagers - the user: "squares in
  speeches mean they are not close enough to hear the full speech"):** `A.hear` gave a near / named / engaged agent a
  line only within the mode's range, whole. Now between the range and the reach (`S.ranges[mode]` [1] and [2]) it
  gets it garbled as a player there reads it (`T.garble`, the fraction by distance times `C.GARBLE_MAX`, moved to
  config from the client; a seed from the line, so it garbles alike for all), "from" kept, a normal line (scored like
  any; a mod's onScores sees the squares). Named / engaged detection on what it made out: a name lost in the garble
  is not heard.
- **Bubbles kept out from behind the HUD (the user, 2026-11-16: "the speech bubbles are often drawn behind the game's
  own UI when players speak off the screen, which makes them impossible to read"; "can you draw boundaries around
  these UI elements"):** the bubbles layer is at the back of the HUD (`MoveToBack`), and a docked bubble kept only 24
  px from the edge, where the HUD is. `PCBubbles:HudRects` measures the HUD 4 times a second from its widgets, not
  fixed boxes: under each of controls' anchored roots (topleft, topright, top, bottom, bottomright, left, right, the
  container roots), one box per element from its shown images (`ImageWidget:GetSize`), texts (`GetRegionSize`) and
  animations (`AnimState:GetVisualBB` - the clock, the status badges, the skill tree's eye), times `GetScale()` and
  the proportional scale, round `GetWorldPosition()`; boxes over 45 % of the screen skipped. So the HUD size, an open
  crafting menu or chest and mods' badges (Combined Status) count. Each bubble goes to the nearest place clear of
  every HUD box and of the bubbles placed before it (`freeSpot`: candidates from every box's edges at once - moving
  out of one box at a time sent a bubble back and forth between the eye and the crafting tabs). `CL.showHud = true`
  draws the boxes (dev); devtest `SCENE=hud`: eight speakers off every side, shots with and without the boxes and
  with the crafting menu open. Verified in game at 2560 x 1377, HUD scale 1.06.
- **Agent API 5 (2026-11-16, for the AI Villagers: Koetama 8eb51d6 by the koetama-d4 session, to be 0.5.16):** a
  final result ends the turn with no follow-up request - `onCall` returning `text, true`, or
  `ProxComms.result(id, text, {final = true})`; the brain sends `"final": true` in `agent_results` only to a Koetama
  whose hello's features name `agent_final` (`b.final`). `max_rounds` (1-16) in a definition, sent only then too (else
  stripped like criteria). A reply's `tokens_in/out/cached` go with its "say" and each "call" to the agent's shard:
  `info.tokens` / `call.tokens` = `{input, output, cached}`. The caps carry `final`: `ProxComms.finals()`.
- **Agents' bubbles follow them (the user, 2026-11-05: "the speech bubbles don't follow the speaker when the speaker
  moves"):** a player's bubble was placed every frame from the player entity (`CL.entity`), but an agent's only from
  where its line was said - `CL.entity` knew players and test figures, never agents. Now an agent's line and live words
  carry its entity's prefab (`A.prefabOf`, the line RPC's 12th / live's 8th argument); the client finds the nearest
  entity of that prefab within 4 m of where it was said (`CL.trackAgent`, kept while the next line is said near it) and
  `CL.entity` returns it: the bubble, its tail and the garbling distance follow the creature. (Not an entity in the RPC:
  DST's own code never sends one to a client.) None found: where it was said, as before. Two of one prefab side by
  side (two slimes): the one whose display name is the agent's (a named creature's is), never one another agent has.
- **Bubbles flickering (the user, same day: "the speech bubbles were fighting for placement and they were flickering
  rapidly"):** the stack was sorted by the heads' screen heights every frame, ties only when exactly equal - two
  speakers at nearly one height, bobbing as they hop, swapped places every frame. Now each bubble keeps the height it
  was sorted by until its head moves more than `STICK` (30 px) from it (pc_bubbles.lua); the test bobs two heads
  +-3 px for 10 frames (5 flips before, 0 now).
- **devtest (2026-11-05):** `TEST_PORT` (default 47181) - the test Koetama gets the profile on that port and the dev mod
  points the game at it (`port.lua`, read only once in the world - on the main menu Proximity Comms isn't enabled yet and
  requiring its scripts there stopped DST with a mod error), so a Koetama the user runs keeps 47170 (one did, and took
  the game's link: no agents). Koetama skips a profile file whose id a built-in has (this one is built in) and takes
  ids of 3-40 characters: the copy is `dst-proxcomms-devtest`. The run stops the fake model and the test Koetama it started at the end (one fake model had been left
  answering since 2026-10-25). Scenes: `agents2` (API 2: a scored dog answered and skipped; two villagers who hear each
  other, counted).
- **Fixed (2026-10-25): a crash 5 s after joining since DST's update of 2026-10-22** - the talk key's check asked the
  engine about every CONTROL_* value, and the update added CONTROL_CUSTOM_START (103: the start of mods' controls, no
  control) - an engine assert. Now only values below it (keys.lua).
- **Quick chat's buttons (the user, 2026-10-15; `proxcomms/wheel.lua`):** X opens a folder, or adds a line and goes
  back to the main wheel; Y takes the last piece back; A sends and closes, whatever is picked; B goes back (cancels
  on the main wheel); hold B cancels. (Before: A opened folders and, on a line, added it and sent.)
- **Workshop:** an icon (`modicon.tex` / `.xml`, drawn by `tools/make_icon.py`, written by `tools/ktex.py`) and the
  page (`tools/workshop/`). Item 3819346216 (https://steamcommunity.com/sharedfiles/filedetails/?id=3819346216):
  friends-only until 0.1.5, **public from 0.1.5 (2026-10-16, the user: "publish it to the public this time")**, its
  description then set from `description.txt`. Published by `tools/publish.py` (or the user's steam-workshop-publish
  skill), which also writes `mod.manifest` and the `version:` tag; after a publish, the skill's `download` brings the
  new version to this PC (Steam can be slow to notice).

## Layout

| path | what |
|---|---|
| `modinfo.lua` | DST mod info (api 10, all clients require it), the host's options (Speak / Yell tiles, voice on/off, voice region), en / zh / ru texts |
| `modmain.lua` | the glue: RPCs (server, client, shard), the world component, the HUD widget, `Networking_Say` and `ChatHistory.GenerateChatMessage` wrappers, the chat line hook, the talk key, the command wheel |
| `scripts/proxcomms/text.lua` | UTF-8, cleaning, garbling (⬚), ALL CAPS, units of a spoken line, word wrap (pure Lua) |
| `scripts/proxcomms/json.lua` | JSON for the Koetama link (DST's json.lua cannot write `[]` or whole numbers as ids) |
| `scripts/proxcomms/config.lua` | ranges, modes, constants |
| `scripts/proxcomms/strings.lua` | the texts in en / zh / ru, language names |
| `scripts/proxcomms/settings.lua` | each player's settings (persistent string `proxcomms_settings`) |
| `scripts/proxcomms/server.lua` | routing (who gets a line), live words, the voice room, Global voices, ranges, rate limits |
| `scripts/proxcomms/client.lua` | what this player hears (levels, timed words, reveal), history, commands, sending |
| `scripts/proxcomms/koetama.lua` | the HTTP link to Koetama: the feed, the loop, Koetama's objects, translation |
| `scripts/proxcomms/dummies.lua` | `/pc dummy`: client-side test figures with Koetama test voices |
| `scripts/proxcomms/chatinput.lua` | the ChatInputScreen extension (mode button, Tab, Up/Down, our commands, settings button) |
| `scripts/widgets/pc_bubbles.lua` | the bubbles (a see-through box or the native look, garble, scroll, dock, no overlap, ♪, translation) |
| `scripts/screens/pc_settingsscreen.lua` | Chat / Voice / Translate pages |
| `scripts/components/proxcomms_store.lua` | keeps an admin's ranges in the world's save |
| `koetama/dont-starve-together-proximity-comms.json` | the Koetama profile (HTTP on 47170, test voices 1-3) |
| `tools/test_proxcomms.lua` | offline tests (LuaJIT, mocked game, DST's strict globals): 661 checks |
| `tools/probe/` | the QueryServer probe (a client-only mod) and `stub_server.py` (a Koetama stand-in that logs every byte) |
| `tools/devtest/` | the automated in-game session: `run.sh`, the dev mod `proxcomms_devtest` (never publish) |
| `tools/install.sh` | copies the mod into DST's `mods/proxcomms`, named "... (local dev)" |
| `tools/publish.py` | stages the mod's files in `dist/proxcomms` and publishes them to Workshop item 3819346216 with change notes (`tools/workshop/notes/<version>.txt`), through the running Steam client (Steam's ISteamUGC from DST's steam_api64.dll) |
| `modicon.png`, `modicon.tex`, `modicon.xml` | the icon (128 x 128; the .tex is Klei's KTEX, DXT5 with mipmaps, as the game's own) |
| `images/pc_bubble.png`, `.tex`, `.xml` | the bubble's box (a white 9-slice and four tails, tinted in game), drawn by `tools/make_bubble.py` |
| `fonts/pc_pangolin.zip` | the bubbles' font (Pangolin, OFL: `fonts/Pangolin-OFL.txt`), built by `tools/make_font.py` from `tools/fonts/` |
| `tools/make_icon.py`, `tools/ktex.py` | draw the icon; write / read / inspect KTEX textures (checked by decoding the game's `command_wheel.tex`) |
| `tools/workshop/` | the Workshop page: `description.txt` (BBCode), `preview.png`, how to publish |

## Commands

```bash
# offline tests (all must pass)
luajit -joff tools/test_proxcomms.lua ./
# install into the game (local development)
sh tools/install.sh
# an automated in-game session (DST hosts an offline world on save slot 9 in its own process; a test Koetama, debug
# build, silent, translates into English and "says" one line); needs modsettings.lua to ForceEnableMod("proxcomms")
# and ForceEnableMod("proxcomms_devtest") - remove both after
sh tools/devtest/run.sh <scratch dir>
```

## How it works

- **Speak / Yell:** the client sends the line to its shard's server (`say` RPC); the server cleans it, checks the
  sender (DST gives the player entity: no posing as someone else), rate limits (6 at once, 1/s), and sends it only to
  the players within its outer range x1.5 (`line` client RPC, a userid list) with where it was said; it pushes
  `ontalk` on the speaker (DST's talk sound and mouth, from the server's stategraph) for typed lines, and raises
  `proxcomms_said` on the world. Each client decides what it heard: full within the words' range, garbled in the
  buffer (a fixed share of letters per line, more the closer), hidden beyond (kept while up: walking in reveals it).
  The history gets a line when the whole line was made out, or when the bubble ends (garbled, "(far)").
- **Whisper / Global** are DST's own (`TheNet:Say`); the mod wraps `Networking_Say` on clients to draw the bubble
  itself (an empty `talker:Say` keeps DST's talk sound and mouth), and keeps DST's history (`ChatHistory:OnSay`).
- **History:** DST's own chat (`ChatHistory:AddToHistory`, local only: never served to joiners by the host). The
  message colour is set by wrapping `GenerateChatMessage` (Yell orange, garbled grey, translation pink). The word
  filter (`ApplyLocalWordFilter`) runs on every received line, live words and translations.
- **Koetama (`koetama.lua`):** each client POSTs its feed to its own Koetama (`http://127.0.0.1:47170/`, profile
  above). Idle: a long poll (wait 1). Voices in play (a room and someone within Yell's reach, the talk key, talking,
  test figures): a feed every 0.1 s (positions move). The talk key and a line to translate go at once (a second
  request). No Koetama: tried every 5 s, every 15 s after 2 minutes (each failed try is a `CURL ERROR` line in DST's
  log). The link runs on `GetStaticTime` (a world hosted alone autopauses in menus).
- **Feed:** `me` = the userid, `listener` = the head + FollowCamera's axes, `speakers` = players of this shard within
  Yell's reach x1.25 by position (not those in Global), each with this player's volume (muted: 0) and
  ghosts' effects; `range` = this player's mode ([near = half the words' range, far = its outer edge]; Whisper
  [4, 16]); `max_range` = Yell's outer edge; `to` = nobody in Global (Global is text only: typed, or the
  spoken line's words - the user, 2026-10-16, as in the Teardown mod); `room` / `key` / `region`;
  `to_translate`.
- **The voice room:** Koetama offers a room; the client sends it to its server every 2 s until it hears the server's;
  the master keeps the first and sends it to every client and shard (a late shard asking gets it again). New each
  server session; never saved.
- **Spoken lines:** Koetama's `final` goes through `CL.say` in this player's mode (Speak / Yell with word times and
  `ago`, cut into 150-character pieces; Whisper / Global as DST chat). Live words go to the server every 0.25 s at
  most and only to the players in reach (not in Global). Listeners keep a 0.1 s distance log per player and show only
  the words said while they were in reach ("... the rest"), each as clearly as it was heard then.

## Verified (2026-10-13)

- **The probe (DST build 756039, main menu, client-only mod):** `TheSim:QueryServer` POSTs with `Content-Length` and
  `Content-Type: application/json`; `127.0.0.1` and `localhost` both work; several requests can be out at once (4
  held 1 s each came back together; a request sent behind a long poll came back first); 400 / 503 come back with
  their codes; a refused port gives `ok=false code=0` after up to ~3 s; a 60 KB UTF-8 answer arrives whole; the
  same works on a dedicated server. **Bodies over 1 KB also send `Expect: 100-continue`**, and libcurl held them 1 s:
  Koetama's HTTP connector now answers `100 Continue` (koetama repo, `kd-games/src/http.rs`, test
  `expect_100_continue`, PROTOCOL.md "Transport: HTTP"; ships with the next Koetama release, the mod warns with an
  older one: `C.KOETAMA_MIN` "0.5.5").
- **A dedicated server** (nullrenderer, this install, offline cluster `PCTest`) loads the mod: modmain, the three RPC
  namespaces, the world postinit.
- **In game** (the host's own process, offline world, `tools/devtest`, three runs): the server's state reaches the
  client; Koetama's voice room goes client -> server -> client; Speak and Yell lines round-trip through the server
  into bubbles; DST's Say and Whisper show in the mod's bubbles; a 45-word line wraps to three lines and scrolls; the
  test figures talk in turns; the chat line shows the mode button, Tab switches Speak -> Yell, Enter says the line in
  it; the settings screen opens on all three pages; the command wheel has Quick chat; history lines are tagged
  [S] / [Y], Yell orange, local only; **Koetama end to end:** a "spoken" line (`koetama --cli --type`) became a Speak
  line; a Spanish line was translated by Koetama (es -> en) and shown as "→ the speaker | Hello friends, where is the
  base? I have food for everyone." in pink; Koetama joined the relay room; **the voice maths** (Koetama's own status
  line with the test figures): straight ahead 0°, the one on the left -34°, the right +34°; the camera turned 180°:
  ahead 180°, the left one +146° (behind, now right) - FollowCamera's axes are right; the whisperer at 14.4 units with
  [4, 16] at 2 % (the formula: 1.7 %), the speaker at 12 units 100 %.
- Bugs found in game and fixed: an assignment to the undeclared global `_` (DST runs Lua with strict globals; the
  offline tests now enforce them too); the link stalled while a world hosted alone was autopaused (now real time);
  "translates chat into en" (now the language's own name).

## Not verified (needs a real session, ideally with a friend)

- **Seen by the user (2026-10-13):** the words over heads (fine; smaller since); then, alone in a hosted world with the
  local copy, **text and voice chat "working well, at least solo"** (Enter, Tab, the talk key, Koetama). Next: a
  controller, then friends.
- **Anything seen by me:** no screen capture tried here sees DST's frames (ANGLE: CopyFromScreen, PrintWindow and ffmpeg
  ddagrab all gave black). The bubbles' look, positions on screen, docking, the shake, the settings screen's layout
  (rows may overflow the window), the mode button and the settings button on the chat line, the wheel's labels are
  all unseen. The logs show the bubbles' texts and screen positions.
- **Two players:** routing to another client (only the host's own lines and the figures' local lines were seen),
  garbling by a real distance, timed words from a real speaker, live words, voices between two PCs, Global voice,
  the caves (two shards), the room handed to a joiner, `SendModRPCToClient` with a userid list, admins' `/pc range`.
- Controller: the wheel opened by script, not by a pad; the misc button on the chat line; the virtual keyboard path
  (Steam Deck) is left as DST's.
- The talk key (**V** by default; that DST binds nothing to V is not verified), push to talk with a real microphone.
- The mime (Wes) path keeps DST's own bubble; `mod_str_fn` (Wigfrid's umlauts, WX-78's capitals) is applied to
  native lines but not seen.
- DST's whisper range is the engine's: the mod assumes 40 units for the bubble (as chathistory.lua does) and [4, 16]
  for a whispered voice - to compare in a playtest.

## Open items

- Publish (the user: Don't Starve Mod Tools' uploader, `tools/workshop/README.md`); then the item's URL into the
  profile (both copies) and Koetama's README. The icon in DST's Mods menu is not seen yet.
- The Chinese and Russian texts are first drafts: a native speaker should read them.
- License: MIT, as the Teardown mod (the user's call to confirm).
- After a dev session, clean up: `modsettings.lua` (the ForceEnableMod lines), DST's `mods/proxcomms_devtest`, the
  save slot `Cluster_9` and a test cluster in `Documents/Klei/DoNotStarveTogether`. (Done 2026-10-13; `mods/proxcomms`
  is left installed to try from the Mods menu. DST's saves into a OneDrive-synced Documents folder failed during the runs:
  "[CRITICAL] Failed to save file ... Cluster_9" - not the mod's; worth knowing before hosting a real world here.)
- A local dedicated server can't be joined from this (online) client while it is an offline cluster (the join stops
  at "Joining server from ping response"); an online one needs a cluster token, so the dev runs host in the client.
