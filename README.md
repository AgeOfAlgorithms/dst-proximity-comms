# Proximity Comms: Text and Voice Chat (Don't Starve Together mod)

Proximity chat for Don't Starve Together, on keyboard or controller. What you say reaches the players near you, over
your head in a speech bubble, and a little farther away it comes through garbled. With the free
[Koetama](https://github.com/AgeOfAlgorithms/koetama) app running next to the game you also get **proximity voice
chat**, **live captions** of what people say, and **offline translation** of the chat. Without Koetama the text chat
works fully.

## Modes

| mode | who gets it |
|---|---|
| **Whisper** | players within 8 tiles; garbled to 11 tiles (the game's own whisper, in the mod's range) |
| **Speak** | players within 18 tiles see your words; from 18 to 25 tiles they see them garbled (⬚ for the letters they don't make out, more real letters the closer they are). Walking up to someone while their line is up reveals it. |
| **Yell** | players within 32 tiles; garbled to 44 tiles |
| **Global** | everyone: the game's own chat |

The host chooses the three distances in the mod's settings (Whisper always shorter than Speak, Yell always farther),
and admins can change them in game (`/pc range <whisper> <speak> <yell>`, or the settings' Chat page). A Speak or
Yell line is sent only to the players near enough to hear it, plus a margin so they can walk in while it is up.
Players farther away never receive it. A whisper is the game's own, which sends it to the players it has loaded
nearby; the mod shows it within the Whisper distance, garbled a little beyond, and the chat history follows.

Wes (the mime) can talk too: his lines, and his live words, show in brackets in his bubble, in every mode, and his
voice is heard like anyone's.

**Speech bubbles** sit over a character's head in a see-through dark box, in Pangolin (the Teardown mod's round
hand; Chinese and other scripts it lacks in the game's own fonts), or in the game's own hand-drawn look (settings,
"Bubble style"). With more features:
- the bubble's tail points at the speaker from whichever side faces them, and follows them as they move;
- the box's opacity (0-100 %) and the text size are settings;
- long lines scroll (three lines show at a time);
- when the speaker is off screen, their line sits on the screen edge on their side, with their name;
- bubbles never cover each other;
- Lines have the same colours as in the chat history (Yell orange, Whisper grey, garbled lines grey). Yell is bigger,
  Whisper smaller, and a line in ALL CAPS shakes.

**Your chat history** is your own: Global lines, plus the Speak and Yell lines you were close enough to hear, as you
heard them (`[S]`, `[Y]`, and `(far)` when garbled). Every player's history is different. Ghosts chat as usual.

## Use

- **Enter** opens the chat line, and Enter sends. (The game's own Y and U keys don't, unless you switch back in the
  settings: "Open the chat with".) The mode shows where the game says "say:". **Tab** or a
  click on the mode changes it (Whisper, Speak, Yell, Global), and your choice is kept for next time. The game's
  whisper key opens the line in Whisper.
- **Up / Down** on the chat line bring back your last lines.
- **Controller:** press the command wheel's button (R3) **twice** to go straight to **Quick chat**, or once for
  the command wheel, which has a **Quick chat** folder too: Callouts, Questions, Replies, Things, Players,
  Insults, Social, Survival, each line with its own picture and label. **X** opens a folder, or adds a line to your
  message (shown in the middle) and goes back to the main wheel, so you can build sentences like "Where? Food" across
  folders; **Y** takes the last word back; **A** sends and closes; **B** goes back, or cancels on the main
  wheel; **hold B** cancels. **LT / RT** change the chat mode (shown in the middle, in its colour). The settings are in the command
  wheel's **Miscellaneous** window (also the pause menu's Server Actions).
  Lines sent from a controller start with **∷** (four dots: a pad's face buttons), as in the Teardown mod.
- **Settings:** `/pc settings`, the "Proximity Comms" button at the end of the chat line, or the wheel. Three pages:
  Chat (mode, bubbles, their style, background and text size, distances), Voice (Koetama), Translate (Koetama).
- **Players** (settings page): each other player's voice volume, 0-150 %, only for you, with Reset.
- **Commands:**
  - `/s`, `/y`, `/w` and `/g` choose the mode, or say one line in it: `/y over here!`
  - `/pc mute <name>`, `/pc unmute <name|all>`, `/pc mute` (who is muted): hides a player's lines and voice, only
    for you. The game's own mute in the player list works too.
  - `/pc volume <name> <0-150>`: one player's voice volume, only for you. `/pc volume` lists who is not at 100%.
  - `/pc dummy`: three test figures in front of you (a whisperer, a speaker and a yeller) take turns talking, so you
    can see every range alone. With Koetama they talk out loud with test voices. Only you see them.
    `/pc dummy 1|2|3`, `/pc dummy clear`.
  - `/pc koetama` (the voice link's state), `/pc range` (the distances), `/pc help`.

The interface is in English, Simplified Chinese and Russian (it follows the game's language).

## Voice chat, live captions and translation (Koetama)

[Koetama](https://github.com/AgeOfAlgorithms/koetama) is a free, open source app for Windows and Linux that runs
next to the game. With it:

- **Voice:** you hear the players near you from where they stand, louder up close, in the same modes as the text.
  Global is text only: what you say in Global is written into the Global chat, and no one hears your voice. Push to talk on **V** by default, or always on (Voice page: Microphone; always on with a controller). Hold **V** and press **Tab** to change the mode (Whisper, Speak, Yell, Global): a strip at the bottom of the screen shows it, as in the Teardown mod. Ghosts sound a little ghostly.
- **Live captions:** what you say is written, live, in your bubble and the bubbles of the players near you. Players
  without Koetama see it too, so they can follow the conversation.
- **Translation:** chat lines in a language you don't speak are translated on your PC into the one you pick in
  Koetama's window ("Translate chat into"). The translation shows under the line, in pink.

Install Koetama, start it, and pick "Don't Starve Together" in its window. The mod finds it by itself.

**Privacy.** The mod talks only to Koetama on your own PC (127.0.0.1); it never contacts anything else. Koetama
sends voices end-to-end encrypted through a relay, in a room only the players of your world know. Speech to text
and translation run on your PC.

## Install

Subscribe on the Workshop. The host enables it for the world, and players who join download it automatically.

## For mod makers

Every Speak and Yell line raises an event on the server's world:

```lua
TheWorld:ListenForEvent("proxcomms_said", function(world, data)
    -- data.player, data.userid, data.mode ("s" / "y"), data.text, data.voice (spoken with Koetama),
    -- data.x, data.z, data.range (its words' reach), data.reach (garbled to); data.agent: an agent's line (below)
end)
```

### Agents: AI characters

Your mod can put characters in the world that players talk to - typing or speaking, as they talk to anyone - and
that answer and act: a pig that follows commands, a merchant you haggle with. An **admin's**
[Koetama](https://github.com/AgeOfAlgorithms/koetama) asks their large language model (they set it up in Koetama's
**Large Language Models** card and allow it for Don't Starve Together); Proximity Comms carries everything between
your mod and it, in the forest and the caves. Players need nothing: they see the replies as speech bubbles and chat
lines. Only that admin's Koetama gets what is said near an agent.

```lua
-- server: a pig that follows whoever asks ("Pigman, follow me")
local ProxComms = GLOBAL.ProxComms               -- (ProxComms.version: 1)
ProxComms.agent("pigman", {
    persona = "You are a Pigman. You grunt a lot. You follow whoever asks politely.",  -- (who it is: up to 8 KB)
    name = "Pigman",                             -- (in bubbles and the chat)
    entity = pig,                                -- (it hears and speaks where it is; or x = .., z = ..)
    hears = "named",                             -- near (default) / named / engaged / all / none
    mode = "speak",                              -- how far its replies carry: whisper / speak / yell / global
    functions = {{name = "follow", description = "Follow a player", parameters = {type = "object",
        properties = {player = {type = "string"}}, required = {"player"}}}},
    state = function() return "day " .. GLOBAL.TheWorld.state.cycles end,   -- (what it should know now)
    onCall = function(call)                      -- (a request, never a command: check it against your rules)
        local p = findPlayer(call.args.player)   -- call.from: the userids whose lines it answered
        if not p then return "error: nobody by that name" end
        startFollowing(pig, p)
        return "ok: following " .. call.args.player   -- (or nil now, ProxComms.result(call.id, "...") later)
    end,
    onReply = function(text, info) end,          -- (its line was said: info.heard players got it)
    onError = function(code, why) end,           -- budget / queue_full / failed: say something in character
})
```

- `hears`: `near` - lines said within the line's own range of it (Whisper / Speak / Yell); `named` - near, with its
  name in the line; `engaged` - named, then anything near from a player it answered or who named it in the last
  30 s; `all` - every line, Global too; `none` - only your events.
- `ProxComms.event(id, "the alarm went off")` - a line from the game for it to hear (and answer);
  `ProxComms.note(id, "Wilson fed you")` - what it should know with its next line, once;
  `ProxComms.say(id, "Oink!")` - it says this without the model (scripted lines, a fallback; the model hears of it);
  `ProxComms.forget(id)` - its conversation starts over; `ProxComms.agent(id, nil)` - removed;
  `ProxComms.status()` - `ready`, `busy` (the admin's requests a minute reached: replies come late), `budget` (their
  month is spent), `error`, or `off` (no admin's Koetama with its language model on).
- Its replies are said like a player's line: a bubble over it, its mode's reach, garbled a bit farther, the chat
  history, translation, live words while the model writes (`stream = false` to turn that off). World events:
  `proxcomms_said` (with `.agent`), `proxcomms_agent_call`, `proxcomms_agent_error`.
- More: `max_words` (its longest reply, default 80), `character = false` (not a character in the world - a
  director, a narrator: the persona is the whole prompt).
- **Tell your players** that the characters use an AI and that what they say near them goes to the AI service the
  admin chose. Everything said near an agent ends up in its prompt: a persona can ask the model to refuse things, only
  your checks of its calls can enforce them.

## Development

- `tools/test_proxcomms.lua`: offline tests against a mocked game (with DST's strict globals). Run
  `luajit -joff tools/test_proxcomms.lua ./`; every check must pass.
- `tools/install.sh`: copies the mod into the game's `mods` folder (as "... (local dev)": a world running it can't be joined).
- `tools/publish.py --notes <file>`: publishes the mod's files to its Workshop item through the running Steam client.
- `tools/probe/`: the HTTP probe (what DST's `QueryServer` sends), with a stand-in for Koetama.
- `tools/devtest/`: an automated in-game session (dev only).
- `koetama/dont-starve-together-proximity-comms.json`: the mod's Koetama profile.

The wheel's pictures are made with [Noto Emoji](https://github.com/googlefonts/noto-emoji) (SIL Open Font
License 1.1, `images/NotoEmoji-OFL.txt`). The bubbles' font is [Pangolin](https://github.com/googlefonts/pangolin)
(SIL Open Font License 1.1, `fonts/Pangolin-OFL.txt`) with one glyph added (U+2B1A, the garbled letters' box), drawn
into the game's font format by `tools/make_font.py`.

MIT License.
