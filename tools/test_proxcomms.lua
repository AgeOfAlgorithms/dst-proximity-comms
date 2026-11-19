-- Offline tests for Proximity Comms (DST): the mod's Lua against a mocked game. Run from the repo root:
--   luajit -joff tools/test_proxcomms.lua ./
-- Every check must pass. What this cannot show: anything DST draws, its network, the real QueryServer (see
-- tools/probe), the engine's whisper range.
local ROOT = (arg and arg[1]) or "./"
package.path = ROOT .. "scripts/?.lua;" .. package.path

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1 else failed = failed + 1 print("FAIL: " .. msg) end
end
local function eq(a, b, msg) check(a == b, msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end

-- ============================================================================ the mocked game
local now = 100
function GetTime() return now end
function GetStaticTime() return now end
local function advance(dt) now = now + dt end

-- a mini Class (DST's: Class(fn) / Class(base, fn), _ctor, _base)
function Class(base, ctor)
    if type(base) == "function" then ctor, base = base, nil end
    local c = {}
    c.__index = c
    if base then setmetatable(c, {__index = base, __call = function(cls, ...) local o = setmetatable({}, cls) cls._ctor(o, ...) return o end})
    else setmetatable(c, {__call = function(cls, ...) local o = setmetatable({}, cls) cls._ctor(o, ...) return o end}) end
    c._ctor = function(self, ...) if ctor then ctor(self, ...) end end
    c._base = base
    return c
end

local function player(uid, name, x, z)
    local p = {userid = uid, name = name, x = x, z = z, tags = {}, events = {}}
    p.Transform = {GetWorldPosition = function() return p.x, 0, p.z end}
    p.AnimState = {GetSymbolPosition = function(_, _, ox, oy, oz) return p.x, 3, p.z end, GetBuild = function() return "wilson" end}
    function p:IsValid() return true end
    function p:HasTag(t) return self.tags[t] == true end
    function p:PushEvent(e, d) self.events[#self.events + 1] = e end
    p.components = {}
    return p
end

local me = player("KU_me", "Me", 0, 0)
local ana = player("KU_ana", "Ana", 10, 0)
local bob = player("KU_bob", "Bob", 40, 0)
local cid = player("KU_cid", "Cid", 60, 0)
local dee = player("KU_dee", "Dee", 300, 0)
AllPlayers = {me, ana, bob, cid, dee}
ThePlayer = me

local clientTable = {
    {userid = "KU_me", name = "Me", colour = {0.5, 0.6, 0.7, 1}, admin = false},
    {userid = "KU_ana", name = "Ana", colour = {1, 0, 0, 1}},
    {userid = "KU_bob", name = "Bob", colour = {0, 1, 0, 1}},
    {userid = "KU_cid", name = "Cid", colour = {0, 0, 1, 1}},
    {userid = "KU_dee", name = "Dee", colour = {1, 1, 0, 1}},
    {userid = "KU_eve", name = "Eve", colour = {1, 1, 1, 1}},          -- (in the caves)
}
local said = {}
TheNet = {
    GetClientTable = function() return clientTable end,
    GetClientTableForUser = function(_, uid) for _, c in ipairs(clientTable) do if c.userid == uid then return c end end end,
    GetNetIdForUser = function(_, uid) return uid end,
    Say = function(_, text, whisper) said[#said + 1] = {text = text, whisper = whisper} end,
    GetIsServer = function() return true end,
    IsDedicated = function() return false end,
}
TheWorld = {ismastershard = true, events = {}, PushEvent = function(self, e, d) self.events[#self.events + 1] = {e, d} end}
SHARDID = {MASTER = "1"}

local sentToClient, sentToServer, sentToShard = {}, {}, {}
function GetClientModRPC(ns, name) return {ns = ns, name = name} end
function GetModRPC(ns, name) return {ns = ns, name = name} end
function GetShardModRPC(ns, name) return {ns = ns, name = name} end
function SendModRPCToClient(rpc, to, ...) sentToClient[#sentToClient + 1] = {name = rpc.name, to = to, args = {...}} end
function SendModRPCToServer(rpc, ...) sentToServer[#sentToServer + 1] = {name = rpc.name, args = {...}} end
function SendModRPCToShard(rpc, shard, ...) sentToShard[#sentToShard + 1] = {name = rpc.name, shard = shard, args = {...}} end
local function lastTo(name) for i = #sentToClient, 1, -1 do if sentToClient[i].name == name then return sentToClient[i] end end end
local function lastServer(name) for i = #sentToServer, 1, -1 do if sentToServer[i].name == name then return sentToServer[i] end end end
local function countServer(name) local n = 0 for _, s in ipairs(sentToServer) do if s.name == name then n = n + 1 end end return n end

local history, responses = {}, {}
ChatTypes = {Message = 1, CommandResponse = 6}
ChatHistory = {
    AddToHistory = function(self, kind, uid, netid, sender, text, colour, icon, whisper, localonly)
        history[#history + 1] = {kind = kind, uid = uid, sender = sender, text = text, localonly = localonly}
    end,
    SendCommandResponse = function(self, t) responses[#responses + 1] = t end,
}
TEXT_FILTER_CTX_CHAT = 2
function ApplyLocalWordFilter(text) return (text:gsub("badword", "*******")) end

local persisted = {}
local queries = {}
TheSim = {
    GetPersistentString = function(_, name, cb) cb(persisted[name] ~= nil, persisted[name]) end,
    SetPersistentString = function(_, name, data) persisted[name] = data end,
    QueryServer = function(_, url, cb, method, body) queries[#queries + 1] = {url = url, cb = cb, method = method, body = body} end,
    GetScreenSize = function() return 1920, 1080 end,
    GetScreenPos = function(_, x, y, z) return 960 + x * 10, 540 - z * 10 end,
}
local heading = 0
TheCamera = {GetHeading = function() return heading end}
local controller = false
TheInput = {ControllerAttached = function() return controller end, PlatformUsesVirtualKeyboard = function() return false end,
    GetControllerID = function() return 0 end, GetLocalizedControl = function() return "(B)" end}
LANGUAGE = {RUSSIAN = 16, CHINESE_T = 21, CHINESE_S = 22, CHINESE_S_RAIL = 23}


-- DST runs Lua with strict globals (scripts/strict.lua): code that reads or writes an undeclared global errors. The
-- same here for the mod's own files (found in-game 2026-10-13: "assign to undeclared variable '_'").
do
    local declared = {}
    for k in pairs(_G) do declared[k] = true end
    local function modCode(level)
        local info = debug.getinfo(level, "S")
        local src = info and info.source or ""
        return src:find("scripts/", 1, true) ~= nil or src:find("scripts\\", 1, true) ~= nil or src:find("modmain", 1, true) ~= nil
    end
    setmetatable(_G, {
        __newindex = function(t, k, v)
            if not declared[k] and modCode(3) then error("assign to undeclared variable '" .. tostring(k) .. "'", 2) end
            declared[k] = true
            rawset(t, k, v)
        end,
        __index = function(t, k)
            if not declared[k] and modCode(3) then error("variable '" .. tostring(k) .. "' is not declared", 2) end
            return nil
        end,
    })
end

-- ============================================================================ text
local T = require "proxcomms/text"
eq(T.clean("  hi\0there\226\128\139  "), "hi there", "clean: control bytes become spaces, zero-width goes, trimmed")
eq(T.clean("\226\128\139\226\128\139"), "", "clean: nothing visible is empty")
eq(T.len(T.clean(string.rep("é", 200))), 150, "clean: at most 150 characters")
eq(T.clean("a\192\128b"), "ab", "clean: an overlong form is dropped")
eq(T.garble("hi, you!", 0, 7), "\226\172\154\226\172\154, \226\172\154\226\172\154\226\172\154!", "garble 0: boxes, punctuation and spaces stay")
eq(T.garble("hi, you!", 1, 7), "hi, you!", "garble 1: all of it")
local g1, g2 = T.garble("the quick brown fox", 0.4, 3), T.garble("the quick brown fox", 0.6, 3)
local function shown(s) local n = 0 for ch in s:gmatch(T.CHAR) do if ch ~= T.GARBLE and ch ~= " " then n = n + 1 end end return n end
check(shown(g2) >= shown(g1), "garble: a bigger share shows at least as many letters")
local us = T.units("hi 你好 there")
eq(#us, 4, "units: CJK characters are units of their own")
eq(T.join(us, 1, #us), "hi 你好 there", "units join back")
eq(T.timesHex({0, 0.5, 1.25}), "0000003200" .. "7d", "times as hex")
local ts = T.timesOf("00000032007d")
check(ts and #ts == 3 and math.abs(ts[3] - 1.25) < 1e-9, "times from hex")
check(T.timesOf("123") == nil and T.timesOf("zzzz") == nil, "bad times are nil")
check(T.allCaps("HELLO THERE") and not T.allCaps("Hello") and not T.allCaps("A") and T.allCaps("ПРИВЕТ"), "all caps, any cased script")
local lines = T.wrap("one two three four five six", 9, function(s) return #s end)
eq(#lines, 4, "wrap by width (one two / three / four five / six)")
eq(lines[1], "one two", "wrap keeps words whole")
local cut = T.wrap("abcdefghijkl", 5, function(s) return #s end)
eq(cut[1], "abcde", "wrap cuts a word longer than a line")
eq(T.cutBytes("aé", 2), "a", "cutBytes never splits a character")
eq(T.tail("abcdef", 3), "def", "tail")

-- ============================================================================ json
local J = require "proxcomms/json"
eq(J.encode({type = "feed", b = 1, a = J.array({}), c = {1.5, "x"}}), '{"type":"feed","a":[],"b":1,"c":[1.5,"x"]}', "encode: type first, sorted, [] and whole numbers")
eq(J.encode("a\"\n\255"), '"a\\"\\n\239\191\189"', "encode: escapes, invalid byte -> U+FFFD")
local d = J.decode('{"objects":[{"type":"hello","features":["speech"]}],"last":1,"x":null,"s":"\\u00e9\\ud83d\\ude00"}')
check(d and d.last == 1 and d.objects[1].features[1] == "speech" and d.x == J.NULL and d.s == "é😀", "decode")
check(J.decode("{bad") == nil and J.decode('{"a":1} x') == nil, "decode: malformed is nil")

-- ============================================================================ config
local C = require "proxcomms/config"
local r = C.ranges(8, 16)
eq(r.s[1], 32, "speak: 8 tiles = 32 units")
check(math.abs(r.s[2] - 44.8) < 1e-9 and r.y[1] == 64 and math.abs(r.y[2] - 88) < 1e-9, "the buffers")
eq(C.ranges(8, 5).yellTiles, 9, "yell always past speak")
do
    local d = C.ranges()
    check(d.whisperTiles == 6 and d.speakTiles == 14 and d.yellTiles == 26, "defaults: Whisper 6, Speak 14, Yell 26 tiles")
    eq(d.w[2], 6 * 4 * 1.4, "Whisper garbled to 40 % past it, as Speak")
    eq(C.ranges(8, 16, 12).whisperTiles, 7, "whisper always under speak")
    eq(C.voiceRange(d, "w")[2], d.w[2], "a whispered voice carries as far as its words, garbled")
end
eq(C.ranges(1, 100).speakTiles, C.TILES_MIN, "ranges clamp")
check(C.olderThan("0.5.4", "0.5.5") and not C.olderThan("0.5.5", "0.5.5") and not C.olderThan("0.6.0", "0.5.5") and C.olderThan("", "0.5.5"), "versions")
eq(C.nextMode("g"), "w", "modes go round")
eq(C.prevMode("w"), "g", "and back round (LT)")
eq(C.prevMode(C.nextMode("y")), "y", "next then back: the same")

-- ============================================================================ strings
local Strings = require "proxcomms/strings"
eq(Strings.pick(22), "zh", "Chinese (simplified)")
eq(Strings.L("SPEAK"), "说话", "a Chinese string")
eq(Strings.pick(16), "ru", "Russian")
eq(Strings.pick(1), "en", "anything else: English")
eq(Strings.langName("es"), "Español", "a language by its own name")
eq(Strings.langName("xx"), "xx", "an unknown code as it is")
for _, lang in ipairs({"zh", "ru"}) do
    local missing = {}
    for k in pairs(Strings.tables.en) do if Strings.tables[lang][k] == nil then missing[#missing + 1] = k end end
    eq(#missing, 0, lang .. " has every string (missing: " .. table.concat(missing, ", ") .. ")")
    for k, v in pairs(Strings.tables.en) do
        if type(v) == "string" then
            local _, n1 = v:gsub("%%[ds]", "")
            local _, n2 = Strings.tables[lang][k]:gsub("%%[ds]", "")
            eq(n2, n1, lang .. " " .. k .. " has the same placeholders")
        end
    end
    eq(#Strings.tables[lang].WHEEL_FOLDERS, #Strings.tables.en.WHEEL_FOLDERS, lang .. " wheel folders")
end

-- ============================================================================ server
local S = require "proxcomms/server"
S.configure(8, 16, true, "weur")
sentToClient = {}
S.onSay(me, "hello there", "s")
local m = lastTo("line")
check(m ~= nil, "a Speak line is sent")
local to = {}
for _, uid in ipairs(m.to) do to[uid] = true end
-- (speak: words 32, buffer 44.8, sent to 44.8 * 1.5 = 67.2)
check(to.KU_me and to.KU_ana and to.KU_bob and to.KU_cid and not to.KU_dee, "Speak goes to the players within its reach + margin only")
eq(m.args[3], "hello there", "the line's text")
eq(m.args[4], "s", "its mode")
eq(m.args[8], false, "typed, not spoken")
eq(me.events[#me.events], "ontalk", "a typed line: the character talks (DST's talk sound)")
check(TheWorld.events[#TheWorld.events][1] == "proxcomms_said", "the said event for other mods")
sentToClient = {}
S.onSay(me, "far", "y")
to = {}
for _, uid in ipairs(lastTo("line").to) do to[uid] = true end
check(to.KU_cid and not to.KU_dee, "Yell reaches 88 * 1.5 units")
sentToClient = {}
S.onSay(me, "x", "g") S.onSay(me, 5, "s") S.onSay({}, "x", "s") S.onSay(me, "\226\128\139", "s")
eq(#sentToClient, 0, "bad lines are dropped (Global is DST's, not a string, no player, nothing visible)")
S.onSay(me, string.rep("a", 5000), "s")
eq(#sentToClient, 0, "a huge line is dropped")
-- spoken lines: their times are checked
sentToClient = {}
now = now + 100
S.onSay(ana, "one two three", "s", 4, "000000320064", 1.5)
m = lastTo("line")
check(m and m.args[8] == true and m.args[9] == 4 and m.args[10] == "000000320064" and m.args[11] == 1.5, "a spoken line keeps its word times")
local talks = #ana.events
S.onSay(ana, "one two three", "s", 5, "0000", 1.5)
eq(lastTo("line").args[10], "", "times that do not fit the text are dropped")
eq(#ana.events, talks, "a spoken line: no talk sound (the voice is heard)")
-- rate limit
now = now + 100
sentToClient = {}
for i = 1, 20 do S.onSay(bob, "spam " .. i, "s") end
eq(#sentToClient, 6, "6 lines at once at most")
advance(2)
S.onSay(bob, "later", "s")
eq(#sentToClient, 7, "then one a second")
-- live words
sentToClient = {}
S.onLive(me, 3, "hello", "w")
to = {}
for _, uid in ipairs(lastTo("live").to) do to[uid] = true end
-- (Whisper 7 tiles here - kept under Speak's 8 - garbled to 39.2 units, sent 50 % past that: Bob at 40 in, Cid at 60 not)
check(to.KU_ana and to.KU_bob and not to.KU_cid, "whispered live words: the whisper's reach, its garbled zone and margin")
S.onLive(me, 3, "hello", "g")
eq(#sentToClient, 1, "no live words in Global")
-- the voice room: the first wins
sentToClient, sentToShard = {}, {}
S.room = nil
S.onRoom(me, "zz", "yy")
eq(S.room, nil, "a bad room is refused")
local room1, key1 = string.rep("a", 32), string.rep("b", 64)
S.onRoom(ana, room1, key1)
eq(S.room, room1, "the first room")
S.onRoom(bob, string.rep("c", 32), string.rep("d", 64))
eq(S.room, room1, "the first room stays")
local rm = lastTo("room")
check(rm and rm.to == nil and rm.args[1] == room1 and rm.args[3] == "weur", "the room goes to everyone, with the region")
check(sentToShard[#sentToShard].name == "room_set", "and to the other shards")
-- hello: the state
sentToClient = {}
S.onHello(me)
local st = lastTo("state")
check(st and st.to == "KU_me" and st.args[1] == 8 and st.args[2] == 16 and st.args[3] == room1, "hello: ranges and room to that player")
-- Global voices
sentToClient, sentToShard = {}, {}
S.onVmode(ana, "g")
eq(lastTo("global").args[1], "KU_ana", "a Global voice is announced")
S.onVmode(ana, "g")
eq(#sentToClient, 1, "only changes are announced")
S.onVmode(ana, "s")
eq(lastTo("global").args[1], "", "back to Speak")
-- a cave shard forwards to the master
TheWorld.ismastershard = false
sentToShard = {}
S.onVmode(bob, "g")
check(sentToShard[1] and sentToShard[1].name == "vmode" and sentToShard[1].shard == "1", "caves: the voice mode goes to the master")
S.onRoom(bob, string.rep("e", 32), string.rep("f", 64))
check(sentToShard[2] and sentToShard[2].name == "room_offer", "caves: a room offer goes to the master")
S.onShardRoomSet("1", string.rep("1", 32), string.rep("2", 64))
eq(S.room, string.rep("1", 32), "caves: the master's room")
TheWorld.ismastershard = true
-- ranges: admins only
S.onRanges(me, 4, 10)
eq(S.speak, 8, "not an admin: no change")
clientTable[1].admin = true
S.onRanges(me, 4, 10)
check(S.speak == 4 and S.yell == 10 and S.save().speak == 4, "an admin changes them (and they are saved)")
S.load({speak = 8, yell = 16})
eq(S.yell, 16, "loaded from the world's save")
clientTable[1].admin = false

-- ============================================================================ client
local Settings = require "proxcomms/settings"
local CL = require "proxcomms/client"
local K = require "proxcomms/koetama"
local D = require "proxcomms/dummies"
CL.K, CL.D, K.CL, K.D, D.CL = K, D, CL, D, CL
CL.init()
CL.onState(8, 16, "", "", "", "", true)
history, responses = {}, {}
-- a line from Ana (10 units: within Speak's words)
CL.onLine("KU_ana", "Ana", "hello badword", "s", 1, 10, 0, false)
local b = CL.bubbles.KU_ana.cur
eq(b.level, "full", "near: in full")
eq(b.full, "hello *******", "the word filter runs on receipt")
eq(history[#history].text, "hello *******", "in the history")
check(history[#history].sender:find("Ana") and history[#history].localonly == true, "the history line names Ana and stays local")
-- Bob at 40: in Speak's buffer
local nh = #history
CL.onLine("KU_bob", "Bob", "can you hear me", "s", 2, 40, 0, false)
b = CL.bubbles.KU_bob.cur
eq(b.level, "mumble", "the buffer: garbled")
check(CL.bubbleText(b):find(T.GARBLE, 1, true) ~= nil, "garbled letters show")
eq(#history, nh, "a garbled line waits for the history (the most made out goes in)")
-- Bob walks closer while it is up: revealed
bob.x = 20
advance(0.5)
CL.tick(0.5)
eq(b.level, "full", "walking in reveals it")
eq(history[#history].text, "can you hear me", "then it is in the history in full")
bob.x = 40
-- Cid at 60: out of reach, hidden
CL.onLine("KU_cid", "Cid", "nobody hears", "s", 3, 60, 0, false)
check(CL.bubbles.KU_cid.cur.hidden and not CL.visible(CL.bubbles.KU_cid.cur), "beyond the buffer: hidden")
-- a garbled line that stays garbled: in the history when it ends, marked far
cid.x = 40
CL.onLine("KU_cid", "Cid", "almost", "s", 4, 40, 0, false)
nh = #history
advance(20)
CL.tick(0.1)
check(#history == nh + 1 and history[#history].sender:find("(far)", 1, true), "garbled to the end: in the history as made out, marked (far)")
cid.x = 60
-- muted
Settings.muted.KU_ana = "Ana"
CL.onLine("KU_ana", "Ana", "muted line", "s", 5, 10, 0, false)
check(not (CL.bubbles.KU_ana and CL.bubbles.KU_ana.cur and CL.bubbles.KU_ana.cur.full == "muted line"), "a muted player's lines are not shown")
Settings.muted = {}
-- timed words: Bob talks, walking out of reach mid-line
CL.samples = {}
bob.x = 10
for i = 1, 10 do advance(0.1) CL.sample(now) end      -- (1 s near)
bob.x = 100
for i = 1, 10 do advance(0.1) CL.sample(now) end      -- (1 s far)
-- the line began 2 s ago: "near words" said in the first second, "far words" in the second
CL.onLine("KU_bob", "Bob", "near words far words", "s", 6, 100, 0, true, 9, T.timesHex({0.1, 0.5, 1.2, 1.6}), 2)
b = CL.bubbles.KU_bob.cur
eq(b.full, "near words ...", "timed: only the words said in reach, then ...")
check(b.fixed and b.level == "full", "and fixed as heard")
bob.x = 40
-- live words
CL.onLive("KU_ana", "Ana", 3, "hel", "s", 10, 0)
eq(CL.liveText(CL.live.KU_ana, "KU_ana"), "hel", "live words near")
CL.onLive("KU_dee", "Dee", 3, "far away", "s", 300, 0)
eq(CL.liveText(CL.live.KU_dee, "KU_dee"), nil, "live words out of reach: none")
CL.onLine("KU_ana", "Ana", "hello", "s", 7, 10, 0, true, 3, "", 0)
eq(CL.live.KU_ana, nil, "the finished line replaces the live words")
-- DST's own whisper, in the mod's Whisper range (here 7 tiles: 28 units, garbled to 39.2)
CL.onNative("KU_dee", "Dee", "psst", {1, 1, 1, 1}, true)
check(not (CL.bubbles.KU_dee and CL.bubbles.KU_dee.cur and CL.visible(CL.bubbles.KU_dee.cur)), "a whisper from 300 units: no bubble")
CL.onNative("KU_ana", "Ana", "psst", {1, 1, 1, 1}, true)
local wb = CL.bubbles.KU_ana.cur
check(wb.mode == "w" and wb.level == "full" and CL.visible(wb) and wb.hist, "a near whisper: a bubble, whole, and in the history")
bob.x = 33
CL.onNative("KU_bob", "Bob", "meet me at the base", {1, 1, 1, 1}, true)
wb = CL.bubbles.KU_bob.cur
check(wb.level == "mumble" and CL.visible(wb) and CL.bubbleText(wb):find(T.GARBLE, 1, true), "a whisper from its garbled zone: garbled letters")
check(not wb.hist, "and not in the history yet (it is, as made out, when its bubble ends)")
bob.x = 20
CL.tick(0.1)
check(wb.level == "full" and wb.hist, "walking in while it is up: the whole whisper, then in the history")
bob.x = 40
-- translations of lines heard garbled: asked too, garbled as the line is (filling in walking closer), in the history
-- as made out
do
    local asked, want = {}, K.want
    K.want = function(uid, text, b) asked[#asked + 1] = text end
    history = {}
    bob.x = 40                                           -- (Speak 8 tiles here: 32 units, garbled to 44.8)
    CL.onLine("KU_bob", "Bob", "hola amigos, vamos a la base", "s", 9100, 40, 0, false)
    local gb = CL.bubbles.KU_bob.cur
    check(gb.level == "mumble" and asked[#asked] == "hola amigos, vamos a la base", "a garbled line: translated too (the whole line)")
    CL.translated("KU_bob", "Bob", "hello friends, let's go to the base", gb)
    local shown = CL.trText(gb)
    check(shown ~= "hello friends, let's go to the base" and shown:find(T.GARBLE, 1, true), "its translation: garbled, as the line is")
    check(#history == 0, "and not in the history yet")
    bob.x = 20
    CL.tick(0.1)
    check(gb.level == "full" and CL.trText(gb) == "hello friends, let's go to the base", "walking in: the whole translation")
    check(#history == 2 and history[2].text == "hello friends, let's go to the base", "then both lines in the history, the translation after")
    -- garbled to the end: the translation in the history as made out
    history = {}
    bob.x = 40
    CL.onLine("KU_bob", "Bob", "adios amigos", "s", 9101, 40, 0, false)
    local gb2 = CL.bubbles.KU_bob.cur
    CL.translated("KU_bob", "Bob", "goodbye friends", gb2)
    advance(30)
    CL.tick(0.1)
    check(#history == 2 and history[2].text ~= "goodbye friends" and history[2].text:find(T.GARBLE, 1, true),
        "garbled to the end: the translation in the history, garbled as made out")
    bob.x = 40
    K.want = want
end
-- a mime (Wes): his bubbles in brackets, in every mode and his live words; his history lines as they are
ana.tags.mime = true
CL.onNative("KU_ana", "Ana", "shh", {1, 1, 1, 1}, true)
check(CL.visible(CL.bubbles.KU_ana.cur) and CL.bubbleText(CL.bubbles.KU_ana.cur) == "[shh]", "a mime's whisper: in brackets")
check(CL.bubbles.KU_ana.cur.full == "shh", "(the line itself, for the history, as said)")
CL.onLine("KU_ana", "Ana", "over here", "s", 4242, 10, 0, false)
eq(CL.bubbleText(CL.bubbles.KU_ana.cur), "[over here]", "a mime's Speak: in brackets")
CL.onLive("KU_ana", "Ana", 9, "hello", "s", 10, 0)
eq(CL.liveText(CL.live.KU_ana, "KU_ana"), "[hello]", "a mime's live words (his voice): in brackets")
CL.live.KU_ana = nil
ana.tags.mime = nil
-- sending
sentToServer, said = {}, {}
CL.say("hi", "s")
check(lastServer("say") and lastServer("say").args[1] == "hi" and lastServer("say").args[2] == "s" and #lastServer("say").args == 2, "Speak goes to the server")
CL.say("psst", "w")
check(said[1].text == "psst" and said[1].whisper == true, "Whisper is DST's own")
CL.say("all", "g")
check(said[2].text == "all" and said[2].whisper == false, "Global is DST's own Say")
-- a long spoken line goes in pieces, each with its own times
sentToServer = {}
local words, times = {}, {}
for i = 1, 60 do words[i] = "word" .. i times[i] = i * 0.3 end
CL.say(table.concat(words, " "), "s", {utt = 2, times = times, ago = 20})
local pieces = 0
local okTimes = true
for _, s in ipairs(sentToServer) do
    if s.name == "say" then
        pieces = pieces + 1
        if T.len(s.args[1]) > 150 then okTimes = false end
        local ts2 = T.timesOf(s.args[4])
        if not ts2 or #ts2 ~= #T.units(s.args[1]) then okTimes = false end
    end
end
check(pieces >= 3 and okTimes, "a long spoken line: pieces of at most 150 characters, times for each")
-- commands
responses, sentToServer = {}, {}
check(CL.command("/y"), "/y is ours")
eq(CL.mode, "y", "/y picks Yell")
CL.command("/s over here")
eq(lastServer("say").args[1], "over here", "/s <text> says one line")
eq(CL.mode, "y", "and keeps the mode")
check(not CL.command("/wave"), "the game's own commands are not ours")
CL.command("/pc mute an")
check(Settings.muted.KU_ana == "Ana", "/pc mute by the start of a name")
CL.command("/pc unmute all")
check(next(Settings.muted) == nil, "/pc unmute all")
CL.command("/pc volume bob 50")
eq(Settings.volumeOf("KU_bob"), 0.5, "/pc volume")
CL.command("/pc volume bob 500")
eq(Settings.volumeOf("KU_bob"), 0.5, "/pc volume out of range: refused")
CL.command("/pc mute zz")
check(responses[#responses]:find("zz"), "/pc mute nobody: says so")
CL.command("/pc range 3 4 10")
eq(lastServer("ranges"), nil, "/pc range: not an admin")
clientTable[1].admin = true
CL.command("/pc range 3 4 10")
local ra = lastServer("ranges") and lastServer("ranges").args or {}
check(ra[1] == 4 and ra[2] == 10 and ra[3] == 3, "/pc range <whisper> <speak> <yell>: an admin asks the server")
clientTable[1].admin = false
CL.setMode("s")
-- the hello and the voice mode go until the server answers
CL.init()
sentToServer = {}
CL.tick(0.1)
eq(countServer("hello"), 1, "hello at start")
CL.tick(0.1)
eq(countServer("hello"), 1, "not every frame")
advance(3.1)
CL.tick(0.1)
eq(countServer("hello"), 2, "again after 3 s without an answer")
CL.onState(8, 16, room1, key1, "", "KU_eve", true)
check(CL.room == room1 and CL.global.KU_eve, "the state: room and Global voices")
advance(1)
CL.tick(0.1)
check(lastServer("vmode") and lastServer("vmode").args[1] == "s", "the voice mode once the server is there")

-- ============================================================================ Koetama
K.online, K.polling, K.urgent, K.retryAt, K.startAt = nil, false, false, 0, nil
queries = {}
CL.tick(0.1)
eq(#queries, 1, "Koetama: a first try")
local f = J.decode(queries[1].body)
check(f and f.type == "feed" and f.me == "KU_me" and f.room == room1 and f.key == key1, "the feed: me, the room")
check(f.listener and f.listener.position[1] == 0 and math.abs(f.listener.forward[1] + 1) < 1e-9, "the listener: head, the camera's forward (heading 0: -x)")
local sp = {}
for _, e in ipairs(f.speakers) do sp[e.id] = e end
check(sp.KU_ana and sp.KU_ana.position and sp.KU_cid and not sp.KU_dee, "speakers within Yell's reach by position, not the far one")
check(not sp.KU_eve, "a Global talker (in the caves): not heard - Global is text only")
eq(sp.KU_bob.volume, 0.5, "this player's volume for Bob")
eq(f.max_range, 88, "max_range: Yell's outer edge")
check(f.range[2] == 44.8 and f.listen == "push_to_talk", "range and push to talk")
check(f.to == nil, "Speak: Koetama sends to the speakers in range (no to)")
-- refused port: offline, quietly, again in 5 s
queries[1].cb("", false, 0)
eq(K.online, false, "no Koetama: offline")
CL.tick(0.1)
eq(#queries, 1, "not again at once")
advance(5.1)
CL.tick(0.1)
eq(#queries, 2, "again after 5 s")
-- it answers: hello (an old version), then objects are acked
responses = {}
queries[2].cb(J.encode({objects = {{type = "hello", version = "0.5.4", protocol = 2, features = J.array({"speech", "voices", "rooms", "translate"})}}, first = 1, last = 1}), true, 200)
check(K.online == true and K.features.translate and K.outdated, "hello: online, features, outdated")
check(responses[1]:find("Koetama") and responses[2]:find("0.5.4"), "connected, and the update hint")
advance(0.11)
CL.tick(0.1)
eq(#queries, 3, "next request (voices in play: every 0.1 s)")
eq(J.decode(queries[3].body).ack, 1, "acks the hello")
-- the room offer: to the server until it has one
CL.room = nil
sentToServer = {}
queries[3].cb(J.encode({objects = {{type = "room", room = room1, key = key1}}, first = 2, last = 2}), true, 200)
CL.tick(0.1)
eq(countServer("room"), 1, "the room offer goes to the server")
advance(2.1)
CL.tick(0.1)
eq(countServer("room"), 2, "again until the server's room comes")
CL.onRoom(room1, key1, "")
advance(2.1)
CL.tick(0.1)
eq(countServer("room"), 2, "not once the room is known")
-- speech: live words (throttled) then the final line in the current mode
local q = queries[#queries]
sentToServer = {}
K.onObject({type = "speech", kind = "start", utt = 7})
K.onObject({type = "speech", kind = "live", utt = 7, text = "hello th"})
K.liveTick(now)
K.onObject({type = "speech", kind = "live", utt = 7, text = "hello there"})
K.liveTick(now + 0.1)
eq(countServer("live"), 1, "live words at most every 0.25 s")
K.liveTick(now + 0.3)
eq(countServer("live"), 2, "then the newest")
K.onObject({type = "speech", kind = "final", utt = 7, text = "hello there friend", times = J.array({0.1, 0.4, 0.8}), ago = 1.2})
local fs = lastServer("say")
check(fs and fs.args[1] == "hello there friend" and fs.args[3] == 7 and fs.args[4] == T.timesHex({0.1, 0.4, 0.8}) and fs.args[5] == 1.2, "the final line goes as a spoken Speak line")
eq(CL.live.KU_me, nil, "own live words cleared")
-- Global mode: text only - the voice to no one (what is said still comes back as words, for Global chat)
CL.mode = "g"
f = K.feed(0)
check(type(f.to) == "table" and #f.to == 0 and f.listen ~= "off", "Global: the voice to no one, the microphone still on (its words)")
CL.global.KU_ana = true
f = K.feed(0)
local heard = false
for _, e in ipairs(f.speakers) do if e.id == "KU_ana" then heard = true end end
check(not heard, "a player in Global nearby: not heard either")
CL.global.KU_ana = nil
CL.mode = "s"
-- translation: a line wanted -> to_translate -> the reply under it
K.into = "en"
history = {}
CL.onLine("KU_ana", "Ana", "hola amigos", "s", 20, 10, 0, false)
f = K.feed(0)
check(f.to_translate and f.to_translate[1].text == "hola amigos", "a line heard in full is sent to translate")
local tid = f.to_translate[1].id
K.onObject({type = "translation", id = tid, text = "hello friends", from = "es", to = "en"})
check(history[#history].text == "hello friends" and history[#history].sender:find("Ana"), "the translation is in the history under Ana's name")
eq(CL.bubbles.KU_ana.cur.tr, "hello friends", "and in the bubble")
f = K.feed(0)
eq(f.to_translate, nil, "answered: no longer sent")
CL.onLine("KU_ana", "Ana", "hola amigos", "s", 21, 10, 0, false)
check(history[#history].text == "hello friends" and K.feed(0).to_translate == nil, "the same text again: the translation reused, not asked")
K.into = ""
CL.onLine("KU_ana", "Ana", "otra cosa", "s", 22, 10, 0, false)
eq(K.feed(0).to_translate, nil, "translation off in Koetama: nothing asked")
-- objects arrive once (two requests in flight can both carry one)
K.ack = 10
responses = {}
K.onAnswer(J.encode({objects = {{type = "voice", state = "unreachable"}}, first = 10, last = 10}), true, 200)
eq(#responses, 0, "an object already had is skipped")
K.onAnswer(J.encode({objects = {{type = "voice", state = "unreachable"}}, first = 11, last = 11}), true, 200)
check(responses[1] and K.voiceState == "unreachable", "a new one is handled")
-- talk key: an urgent request
K.polling, K.urgent = true, false
local nq = #queries
K.setTalk(true)
eq(#queries, nq + 1, "the talk key goes at once")
check(J.decode(queries[#queries].body).talk_key == true, "with the key down")
-- controller: always on
controller = true
eq(K.listen(), "always", "a controller: the microphone always on")
controller = false
-- gone
responses = {}
K.onAnswer("", false, 0)
check(K.online == false and responses[1]:find("disconnected"), "Koetama gone: one line")
-- the quiet pointer: once, after 20 s, in at most 3 sessions
Settings.pointed = 0
K.said = {}
K.startAt = now - 25
K.polling = false
K.retryAt = now + 100
responses = {}
K.tick(now)
check(responses[1] and responses[1]:find("github"), "the pointer to Koetama")
K.tick(now)
eq(#responses, 1, "once")
eq(Settings.pointed, 1, "counted")
-- after two minutes without Koetama: tried every 15 s (each failed try is a line in DST's log)
K.startAt = now - 200
eq(K.retryEvery(), 15, "later: a try every 15 s")
K.startAt = now - 10
eq(K.retryEvery(), 5, "at first: every 5 s")

-- ============================================================================ test figures
local made = {}
function CreateEntity()
    local e = {tags = {}}
    e.entity = {AddTransform = function() e.Transform = {SetPosition = function(_, x, y, z) e.x, e.z = x, z end, GetWorldPosition = function() return e.x, 0, e.z end} end,
        AddAnimState = function() e.AnimState = {SetBank = function() end, SetBuild = function() end, PlayAnimation = function(_, a) e.anim = a end,
            SetMultColour = function() end, GetSymbolPosition = function() return e.x, 3, e.z end} end}
    function e:AddTag(t) self.tags[t] = true end
    function e:IsValid() return not self.removed end
    function e:Remove() self.removed = true end
    function e:DoTaskInTime() end
    made[#made + 1] = e
    return e
end
heading = 0
D.command("")
eq(#D.list, 3, "three figures")
check(D.list[2].x < -10 and D.list[2].x > -14, "ahead of the player (heading 0: -x)")
local spk = D.speakers()
check(#spk == 3 and spk[1].test_voice == 1 and spk[3].test_voice == 3, "each a test voice")
advance(10)
D.nextAt = 0
D.tick(now)
local who = D.list[D.turn].uid
check(CL.bubbles[who] and CL.bubbles[who].cur, "a figure's line shows")
check(D.speakers()[D.turn].talking == true, "its test voice plays during its turn")
eq(CL.entity("pcdummy2"), D.list[2].ent, "the bubbles find the figures")
D.command("clear")
eq(#D.list, 0, "cleared")

-- ============================================================================ agents (AI characters for any mod)
do
    local AG = require "proxcomms/agents"
    AG.S, AG.CL, AG.K = S, CL, K
    S.A, K.A = AG, AG
    local function ups(kind)
        local out, parts = {}, {}
        for _, m in ipairs(sentToClient) do
            if m.name == "agent_up" and m.args[1] == "part" then     -- (a long message in parts: put together)
                local id, i, n, k, piece = m.args[2]:match("^([^|]+)|(%d+)|(%d+)|([^|]+)|(.*)$")
                parts[id] = parts[id] or {n = tonumber(n), ps = {}, got = 0}
                parts[id].ps[tonumber(i)], parts[id].got = piece, parts[id].got + 1
                if parts[id].got == parts[id].n and (kind == nil or k == kind) then
                    out[#out + 1] = {to = m.to, kind = k, t = J.decode(table.concat(parts[id].ps)), parts = parts[id].n}
                end
            elseif m.name == "agent_up" and (kind == nil or m.args[1] == kind) then
                out[#out + 1] = {to = m.to, kind = m.args[1], t = J.decode(m.args[2])}
            end
        end
        return out
    end
    local function downs(kind)
        local out = {}
        for _, m in ipairs(sentToServer) do
            if m.name == "agent_down" and (kind == nil or m.args[1] == kind) then out[#out + 1] = J.decode(m.args[2]) end
        end
        return out
    end
    -- off until an admin's Koetama has its language model on
    check(ProxCommsStatus == nil and AG.status() == "off", "agents: off with no brain")
    sentToClient, sentToServer, sentToShard = {}, {}, {}
    AG.onLlm(ana, true)
    check(AG.owner == nil, "a player who is not an admin is never the brain")
    clientTable[2].admin = true
    AG.onLlm(ana, true)
    eq(AG.owner, "KU_ana", "an admin's Koetama with its language model on: the brain")
    check(lastTo("agent_owner") and lastTo("agent_owner").to == "KU_ana" and lastTo("agent_owner").args[1] == true, "told so")
    check(sentToShard[#sentToShard].name == "llm_owner" and sentToShard[#sentToShard].args[1] == "KU_ana", "and every shard")
    eq(AG.status(), "ready", "agents: ready")
    -- a mod's agent
    local calls, replies = {}, {}
    local pig = {Transform = {GetWorldPosition = function() return 12, 0, 0 end}, IsValid = function() return true end}
    sentToClient = {}
    local ok = AG.define("pigking", {persona = "You are the Pig King. You trade gold for meat.", name = "Pig King", entity = pig,
        hears = "engaged", functions = {{name = "follow", description = "Follow a player",
            parameters = {type = "object", properties = {player = {type = "string"}}, required = {"player"}}}},
        state = function() return "day 3; the king is hungry" end,
        onCall = function(c) calls[#calls + 1] = c return "ok: following " .. tostring(c.args.player) end,
        onReply = function(text, info) replies[#replies + 1] = {text = text, heard = info.heard} end})
    local d = ups("def")[1]
    check(ok and d and d.to == "KU_ana" and d.t.kid == "pigking:1" and d.t.functions[1].name == "follow", "defined: its definition to the brain")
    check(not AG.define("bad id!", {persona = "x"}) and not AG.define("x", {}), "a bad id or no persona: refused")
    -- who it hears: "engaged" - named, then a conversation for 30 s
    sentToClient = {}
    AG.hear("KU_bob", "Bob", "hello there", "s", 11, 0)
    eq(#ups("line"), 0, "engaged: a line without its name is not for it")
    AG.hear("KU_bob", "Bob", "Pig King, follow me!", "s", 11, 0)
    local l = ups("line")[1]
    check(l and l.t.kid == "pigking:1" and l.t.text == "Pig King, follow me!" and l.t.from.id == "KU_bob"
        and l.t.state == "day 3; the king is hungry", "named near it: the line, who said it, its state, to the brain")
    sentToClient = {}
    AG.hear("KU_bob", "Bob", "and bring gold", "s", 11, 0)
    eq(#ups("line"), 1, "then a conversation without its name")
    sentToClient = {}
    AG.hear("KU_cid", "Cid", "Pig King, hi", "s", 60, 0)
    eq(#ups("line"), 0, "too far for Speak: not heard")
    -- the brain (this game): the definition and lines in Koetama's feed until Koetama has them
    sentToServer = {}
    AG.onOwner(true)
    eq(#downs("sync"), 1, "the brain asks every shard for the definitions")
    AG.onHello({llm = true})
    AG.onUp("def", J.encode(d.t))
    AG.onUp("line", J.encode(l.t))
    local f = {}
    AG.feed(f)
    check(f.agents and f.agents[1].id == "pigking:1" and f.agents[1].version == 1 and f.agents[1].persona:find("Pig King"),
        "the feed: the definition (versioned)")
    check(f.to_agent and f.to_agent[1].agent == "pigking:1" and f.to_agent[1].from.name == "Bob", "and the line")
    local lineId = f.to_agent[1].id
    AG.onKnown({agents = {{id = "pigking:1", version = 1}}})
    AG.onReceived({to_agent = {lineId}})
    f = {}
    AG.feed(f)
    check(not f.agents and not f.to_agent, "Koetama has both: neither is sent again")
    -- its reply: said by its server (as a player's line), its call to the mod, the result back
    sentToServer = {}
    AG.onReply({type = "agent_reply", final = true, ids = {lineId}, agent = "pigking:1", text = "Follow? Bring meat first!",
        calls = {{call = "call_1", name = "follow", args = {player = "Bob"}}}, error = ""})
    local say, call = downs("say")[1], downs("call")[1]
    check(say and say.text == "Follow? Bring meat first!" and say.from[1] == "KU_bob", "the brain: its words to its server")
    check(call and call.call == "call_1" and call.args.player == "Bob" and call.from[1] == "KU_bob", "and its call")
    sentToClient = {}
    AG.handle("say", say)
    local ln = lastTo("line")
    check(ln and ln.args[1] == "agent:pigking:1" and ln.args[2] == "Pig King" and ln.args[3] == "Follow? Bring meat first!"
        and ln.args[4] == "s", "the server: said as a Speak line from it")
    eq(ln.args[12], "", "with its entity's prefab (this one has none)")
    local to = {}
    for _, u in ipairs(ln.to) do to[u] = true end
    check(to.KU_me and to.KU_ana and not to.KU_dee, "to the players within its reach")
    check(replies[1] and replies[1].heard >= 2, "the mod's onReply: what it said, how many heard it")
    sentToClient = {}
    AG.handle("call", call)
    check(calls[1] and calls[1].name == "follow" and calls[1].args.player == "Bob" and calls[1].from[1] == "KU_bob", "the mod's onCall")
    local r = ups("result")[1]
    check(r and r.t.call == "call_1" and r.t.result == "ok: following Bob", "its answer back to the brain")
    AG.onUp("result", J.encode(r.t))
    f = {}
    AG.feed(f)
    check(f.agent_results and f.agent_results[1].call == "call_1", "the brain: the result in the feed")
    AG.onReply({type = "agent_reply", final = true, ids = {lineId}, agent = "pigking:1", text = "Fine.", calls = {}, error = ""})
    f = {}
    AG.feed(f)
    check(not f.agent_results, "the follow-up came: the result is done")
    -- the client: an agent's line shows as anyone's (its own uid)
    CL.onLine("agent:pigking:1", "Pig King", "Oink!", "s", 77001, 12, 0, false)
    check(CL.bubbles["agent:pigking:1"] and CL.bubbles["agent:pigking:1"].cur.level == "full", "the client: its bubble")
    -- its bubble follows the entity it speaks from (the user, 2026-11-05): the line carries its prefab, the client
    -- finds the nearest of it there and keeps it
    local function ent(prefab, x, z)
        local e = {prefab = prefab, x = x, z = z, IsValid = function() return true end}
        e.Transform = {GetWorldPosition = function() return e.x, 0, e.z end}
        return e
    end
    local kingFar, king, other = ent("pigking", 15, 0), ent("pigking", 12.5, 0), ent("pigman", 12, 0)
    local findCalls = 0
    TheSim.FindEntities = function(_, x, y, z, r)
        findCalls = findCalls + 1
        local out = {}
        for _, e in ipairs({kingFar, king, other}) do if (e.x - x) ^ 2 + (e.z - z) ^ 2 <= r * r then out[#out + 1] = e end end
        return out
    end
    CL.onLine("agent:pigking:1", "Pig King", "Oink oink!", "s", 77004, 12, 0, false, 0, "", 0, "pigking")
    eq(CL.entity("agent:pigking:1"), king, "an agent's line with its prefab: the nearest of it is its entity")
    king.x = 14
    eq(CL.entity("agent:pigking:1"), king, "it walks off: still its entity (the bubble follows it)")
    check(CL.distTo("agent:pigking:1", 12, 0) and math.abs(CL.distTo("agent:pigking:1", 12, 0) - CL.distTo("agent:pigking:1", 14, 0)) < 1e-6,
        "the distance from where it is now")
    local n0 = findCalls
    CL.onLive("agent:pigking:1", "Pig King", 2, "Oi", "s", 13.5, 0, "pigking")
    check(findCalls == n0 and CL.entity("agent:pigking:1") == king, "the next line near it: the same one, not looked for again")
    king.x = 40
    CL.onLine("agent:pigking:1", "Pig King", "Far!", "s", 77005, 15, 0, false, 0, "", 0, "pigking")
    eq(CL.entity("agent:pigking:1"), kingFar, "its line far from the one it had: found again")
    CL.onLine("agent:pigking:1", "Pig King", "Nowhere", "s", 77006, 100, 100, false, 0, "", 0, "pigking")
    eq(CL.entity("agent:pigking:1"), nil, "none of it there: none (the bubble stays where it was said)")
    CL.onLine("KU_bob", "Bob", "hi", "s", 77007, 12, 0, false, 0, "", 0, "pigking")
    eq(CL.agentEnts.KU_bob, nil, "a player's line: never tracked as an agent")
    -- (two of one prefab side by side - two slimes; the user saw their bubbles fight): the one with the agent's name,
    -- never one another agent has
    local blub, gummy, e1, e2 = ent("chattyslime", 20, 0), ent("chattyslime", 20.5, 0), ent("pigman", 30, 0), ent("pigman", 30.3, 0)
    blub.GetDisplayName = function() return "Blub" end
    gummy.GetDisplayName = function() return "Gummy" end
    TheSim.FindEntities = function(_, x, y, z, r)
        local out = {}
        for _, e in ipairs({blub, gummy, e1, e2}) do if (e.x - x) ^ 2 + (e.z - z) ^ 2 <= r * r then out[#out + 1] = e end end
        return out
    end
    CL.onLine("agent:gummy:1", "Gummy", "Hi", "s", 77010, 20, 0, false, 0, "", 0, "chattyslime")
    CL.onLine("agent:blub:1", "Blub", "Hey", "s", 77011, 20.5, 0, false, 0, "", 0, "chattyslime")
    check(CL.entity("agent:gummy:1") == gummy and CL.entity("agent:blub:1") == blub,
        "two slimes side by side: each its own (by name, not by the nearest)")
    CL.onLine("agent:gus:1", "Gus", "Hi", "s", 77012, 30, 0, false, 0, "", 0, "pigman")
    CL.onLine("agent:mira:1", "Mira", "Hi", "s", 77013, 30, 0, false, 0, "", 0, "pigman")
    check(CL.entity("agent:gus:1") == e1 and CL.entity("agent:mira:1") == e2, "no names: never one another agent has")
    TheSim.FindEntities = nil
    history = {}
    CL.onLine("agent:pigking:1", "Pig King", "Hear ye, all!", "g", 77002, 0, 0, false)
    check(#history == 1 and history[1].text == "Hear ye, all!", "its Global line: in the history")
    CL.onLine("KU_bob", "Bob", "sneaky global", "g", 77003, 0, 0, false)
    eq(#history, 1, "a player's Global through the mod's lines: refused (DST's own chat carries it)")
    -- errors: Koetama lost it - the definition and the lines again, once; then the mod is told
    AG.onUp("line", J.encode({kid = "pigking:1", text = "again?", from = {id = "KU_bob", name = "Bob"}}))
    f = {}
    AG.feed(f)
    local id2 = f.to_agent[1].id
    AG.onReply({type = "agent_reply", final = true, ids = {id2}, agent = "pigking:1", text = "", calls = {}, error = "unknown_agent"})
    f = {}
    AG.feed(f)
    check(f.agents and f.to_agent and f.to_agent[1].id ~= id2 and f.to_agent[1].text == "again?", "unknown_agent: its definition and the line again")
    eq(AG.brain.lineFrom[f.to_agent[1].id], "KU_bob", "who said it: kept under its new id (a reply's from, a call's)")
    sentToServer = {}
    AG.onReply({type = "agent_reply", final = true, ids = {f.to_agent[1].id}, agent = "pigking:1", text = "", calls = {},
        error = "budget", why = "the month's tokens are used up"})
    local e = downs("error")[1]
    check(e and e.error == "budget", "another error: to the mod")
    local errs = {}
    AG.agents.pigking.onError = function(code) errs[#errs + 1] = code end
    AG.handle("error", e)
    eq(errs[1], "budget", "the mod's onError")
    -- status, scripted lines, notes
    sentToServer = {}
    AG.onStatus({state = "busy"})
    AG.handle("status", downs("status")[1])
    eq(AG.status(), "busy", "agent_status: to every shard (ProxComms.status)")
    sentToClient = {}
    check(AG.say("pigking", "Oink oink.") and lastTo("line").args[3] == "Oink oink.", "say: without the model")
    AG.note("pigking", "Bob gave you meat")
    sentToClient = {}
    AG.hear("KU_bob", "Bob", "Pig King, happy now?", "s", 11, 0)
    local lines = ups("line")
    check(#lines == 3 and lines[1].t.text == "you said: Oink oink." and lines[2].t.text == "Bob gave you meat"
        and lines[3].t.text == "Pig King, happy now?", "its next line: what it said and the note first, once")
    -- ---- API 2: scores (the Teardown mod's API 19)
    local function upsFor(kind, kid)
        local out = {}
        for _, u in ipairs(ups(kind)) do if u.t.kid == kid then out[#out + 1] = u end end
        return out
    end
    local function feedFor(kid)
        local fd = {}
        AG.feed(fd)
        local def, lines = nil, {}
        for _, x in ipairs(fd.agents or {}) do if x.id == kid then def = x end end
        for _, x in ipairs(fd.to_agent or {}) do if x.agent == kid then lines[#lines + 1] = x end end
        return fd, def, lines
    end
    eq(AG.API, 8, "agents: API 8")
    AG.note("pigking", "a note")
    eq(AG.noted("pigking"), 1, "noted: a note waiting")
    AG.note("pigking", nil)
    check(AG.noted("pigking") == 0 and AG.noted("nobody") == 0, "note(id, nil): taken back")
    local scored, skips = {}, {}
    sentToClient = {}
    local okD, warn = AG.define("dog", {persona = "You are Rex, a dog.", name = "Rex", entity = pig, hears = "near",
        criteria = {{name = "topic", description = "Rex is the topic"}, {name = "food", description = "it is about food"}},
        onScores = function(sc, info) scored[#scored + 1] = {sc = sc, info = info} return sc.topic >= 0.5 end,
        onSkip = function(info) skips[#skips + 1] = info end})
    local dd = upsFor("def", "dog:1")[1]
    check(okD and not warn and dd and dd.t.criteria and #dd.t.criteria == 2 and dd.t.criteria[1].name == "topic",
        "criteria: in its definition")
    local okB, warnB = AG.define("dog2", {persona = "x", criteria = {{name = "Bad Name", description = "d"}}})
    check(okB and warnB and warnB:find("nothing is scored") and AG.agents.dog2.criteria == nil,
        "bad criteria: defined, nothing scored, the mod told why")
    check(select(2, AG.define("dog2", {persona = "x", criteria = {{name = "a"}}})) ~= nil, "a criterion without a description: told")
    AG.define("dog2", nil)
    -- the brain sends criteria only to a Koetama that scores, and tells every shard whether it does
    sentToServer = {}
    AG.onHello({llm = true})
    AG.onUp("def", J.encode(dd.t))
    local _, dogDef = feedFor("dog:1")
    check(dogDef and dogDef.criteria == nil, "a Koetama that doesn't score: no criteria in the feed")
    check(downs("caps")[1] and downs("caps")[1].scores == false, "caps: it doesn't score")
    sentToServer = {}
    AG.onHello({llm = true, agent_scores = true})
    _, dogDef = feedFor("dog:1")
    check(dogDef and dogDef.criteria and dogDef.criteria[2].name == "food", "one that scores: the criteria")
    local caps = downs("caps")[1]
    check(caps and caps.scores == true, "caps: it scores - to every shard")
    check(not AG.scoring(), "(before the shard hears it: not yet)")
    AG.onDown(ana, "caps", J.encode(caps))
    check(AG.scoring(), "ProxComms.scores(): true")
    -- (API 3) functions: up to 32 kept; a Koetama whose hello has no agent_functions gets the first 16 (more would leave
    -- the agent out), one that says 32 gets them all; the shards hear the limit in the caps
    eq(AG.agentFunctions(), 16, "agentfunctions(): 16 before Koetama says more")
    local many = {}
    for i = 1, 70 do many[i] = {name = "f" .. i, description = "d" .. i, parameters = {type = "object", properties = {}}} end
    AG.define("cat", {persona = "x", functions = many})
    local cd = upsFor("def", "cat:1")[1]
    check(cd and #cd.t.functions == 64 and cd.t.functions[64].name == "f64", "functions: the first 64 of 70 kept (API 8)")
    AG.onUp("def", J.encode(cd.t))
    local _, catDef = feedFor("cat:1")
    check(catDef and #catDef.functions == 16 and catDef.functions[16].name == "f16" and catDef.criteria == nil,
        "a Koetama without agent_functions: the first 16 functions")
    check(#AG.brain.defs["cat:1"].def.functions == 64, "(the brain keeps all 64)")
    sentToServer = {}
    AG.onHello({llm = true, agent_scores = true}, {type = "hello", agent_functions = 32})
    _, catDef = feedFor("cat:1")
    check(catDef and #catDef.functions == 32 and catDef.functions[32].name == "f32", "Koetama 0.5.15 (agent_functions 32): the first 32")
    local _, dogAgain = feedFor("dog:1")
    check(dogAgain and dogAgain.criteria and #dogAgain.criteria == 2, "(criteria still go with a cut-free definition)")
    local caps32 = downs("caps")[1]
    check(caps32 and caps32.functions == 32 and caps32.scores == true, "caps: 32 functions - to every shard")
    AG.onDown(ana, "caps", J.encode(caps32))
    eq(AG.agentFunctions(), 32, "agentfunctions(): 32")
    AG.onDown(ana, "caps", J.encode({scores = true, functions = 999}))
    eq(AG.agentFunctions(), 64, "agentfunctions(): never over 64")
    AG.onDown(ana, "caps", J.encode({scores = true}))
    eq(AG.agentFunctions(), 16, "caps without functions (an older brain): 16")
    sentToServer = {}
    AG.onHello({llm = true, agent_scores = true}, {type = "hello", agent_functions = 64})
    _, catDef = feedFor("cat:1")
    check(catDef and #catDef.functions == 64, "a Koetama that says 64: all 64 (API 8)")
    local caps64 = downs("caps")[1]
    check(caps64 and caps64.functions == 64, "caps: 64 functions")
    AG.onDown(ana, "caps", J.encode(caps64))
    eq(AG.agentFunctions(), 64, "agentfunctions(): 64")
    sentToServer = {}
    AG.onHello({llm = true, agent_scores = true}, {type = "hello", agent_functions = 32})
    AG.onDown(ana, "caps", J.encode(caps32))
    -- (API 7) states: cut at 2048 until the brain's Koetama says more (0.5.18: "agent_state": 8192), in the caps to
    -- every shard; the brain cuts too, to its own Koetama's (a shard's caps late)
    AG.onDown(ana, "caps", J.encode({scores = true, functions = 32}))
    eq(AG.stateBytes(), 2048, "statemax(): 2048 before Koetama says more")
    local bigState = string.rep("a", 9000)
    AG.define("owl", {persona = "x", hears = "all", state = function() return bigState end})
    local function owlLine(text)
        sentToClient = {}
        AG.hear("KU_bob", "Bob", text, "g", 11, 0)
        local u = upsFor("line", "owl:1")[1]
        return u and u.t
    end
    local ol = owlLine("hi owl")
    eq(ol and #ol.state, 2048, "a state of 9000 bytes: cut at 2048")
    AG.onDown(ana, "caps", J.encode({scores = true, functions = 32, state = 8192}))
    eq(AG.stateBytes(), 8192, "statemax(): 8192 when the caps say so")
    ol = owlLine("hi again owl")
    eq(ol and #ol.state, 8192, "then cut at 8192")
    AG.onDown(ana, "caps", J.encode({scores = true, functions = 32, state = 99999}))
    eq(AG.stateBytes(), 8192, "statemax(): never over 8192")
    AG.onUp("def", J.encode(upsFor("def", "owl:1")[1] and upsFor("def", "owl:1")[1].t or {}))
    sentToServer = {}
    AG.onHello({llm = true, agent_scores = true}, {type = "hello", agent_functions = 32})
    AG.onUp("line", J.encode(ol))
    local _, _, owlLines = feedFor("owl:1")
    eq(owlLines[1] and #owlLines[1].state, 2048, "the brain's Koetama without agent_state: the feed's state cut at 2048")
    local capsOld = downs("caps")[1]
    check(capsOld and capsOld.state == 2048, "caps: state 2048")
    sentToServer = {}
    AG.onHello({llm = true, agent_scores = true}, {type = "hello", agent_functions = 32, agent_state = 8192})
    AG.onUp("line", J.encode(ol))
    _, _, owlLines = feedFor("owl:1")
    local longest = 0
    for _, x in ipairs(owlLines) do longest = math.max(longest, #(x.state or "")) end
    eq(longest, 8192, "Koetama 0.5.18 (agent_state 8192): the whole 8 KB state")
    local caps8 = downs("caps")[1]
    check(caps8 and caps8.state == 8192, "caps: state 8192 - to every shard")
    AG.onDown(ana, "caps", J.encode({scores = true, functions = 32}))
    eq(AG.stateBytes(), 2048, "caps without state (an older brain): 2048")
    AG.define("owl", nil)
    AG.onUp("remove", J.encode({kid = "owl:1"}))
    -- (API 8) personas: up to 32 KB kept; a Koetama whose hello has no agent_persona gets the first 8192 (a longer one
    -- would leave the agent out), one that says 32768 gets it all; the shards hear the limit in the caps
    eq(AG.personaBytes(), 8192, "personamax(): 8192 before Koetama says more")
    AG.define("sage", {persona = string.rep("r", 40000)})
    local sd = upsFor("def", "sage:1")[1]
    eq(sd and #sd.t.persona, 32768, "a persona of 40000 bytes: 32768 kept")
    -- (a message over A.PART goes to the brain in parts - DST drops an RPC with a long string: the in-game test of
    --  2026-11-19, a ~99 KB definition arrived cut to 33353 bytes)
    local partMsgs, longest = {}, 0
    for _, m in ipairs(sentToClient) do
        if m.name == "agent_up" and m.args[1] == "part" then partMsgs[#partMsgs + 1] = m.args[2] longest = math.max(longest, #m.args[2]) end
    end
    check(sd and sd.parts == #partMsgs and #partMsgs == 3 and longest <= AG.PART + 64,
        "a 32 KB definition: in parts of at most 12 KB (" .. #partMsgs .. " parts, the longest " .. longest .. ")")
    local pieces = AG.pieces("ab" .. "\226\148\128" .. "cd", 3)
    check(pieces[1] == "ab" and pieces[2] == "\226\148\128" and pieces[3] == "cd", "parts never split a character")
    eq(table.concat(AG.pieces(string.rep("x", 25), 10)), string.rep("x", 25), "parts: all of it, in order")
    -- the brain puts them together - out of order too; a part twice counts once; one never whole is dropped
    AG.onUp("part", partMsgs[3])
    AG.onUp("part", partMsgs[1])
    AG.onUp("part", partMsgs[1])
    check(AG.brain.defs["sage:1"] == nil, "(two of three parts: not yet)")
    AG.onUp("part", partMsgs[2])
    eq(AG.brain.defs["sage:1"] and #AG.brain.defs["sage:1"].def.persona, 32768, "the brain: the parts put together")
    AG.onUp("part", "9.9|1|2|def|{")
    advance(AG.PART_LIFE + 1)
    AG.onUp("part", "9.10|1|2|def|{")
    check(AG.brain.parts["9.9"] == nil and AG.brain.parts["9.10"] ~= nil, "a message never whole: dropped after 30 s")
    AG.brain.parts = {}
    AG.onUp("def", J.encode(sd.t))
    sentToServer = {}
    AG.onHello({llm = true, agent_scores = true}, {type = "hello", version = "0.5.18", agent_functions = 32, agent_state = 8192})
    local _, sageDef = feedFor("sage:1")
    eq(sageDef and #sageDef.persona, 8192, "a Koetama without agent_persona: the first 8192 bytes")
    eq(#AG.brain.defs["sage:1"].def.persona, 32768, "(the brain keeps all 32768)")
    check(downs("caps")[1] and downs("caps")[1].persona == 8192, "caps: persona 8192")
    sentToServer = {}
    AG.onHello({llm = true, agent_scores = true}, {type = "hello", version = "0.5.19", agent_functions = 32,
        agent_state = 8192, agent_persona = 32768})
    _, sageDef = feedFor("sage:1")
    eq(sageDef and #sageDef.persona, 32768, "agent_persona 32768: the whole persona")
    local capsP = downs("caps")[1]
    check(capsP and capsP.persona == 32768, "caps: persona 32768 - to every shard")
    AG.onDown(ana, "caps", J.encode(capsP))
    eq(AG.personaBytes(), 32768, "personamax(): 32768")
    AG.onDown(ana, "caps", J.encode({scores = true, functions = 32, persona = 1e6}))
    eq(AG.personaBytes(), 32768, "personamax(): never over 32768")
    AG.onDown(ana, "caps", J.encode({scores = true, functions = 32}))
    eq(AG.personaBytes(), 8192, "caps without persona (an older brain): 8192")
    -- (several 32 KB definitions: a Koetama taking 256 KB feeds gets up to DEF_BUDGET_BIG of them in one, an older one
    --  DEF_BUDGET - one at a time)
    AG.define("sage2", {persona = string.rep("s", 32768)})
    AG.define("sage3", {persona = string.rep("t", 32768)})
    AG.onUp("def", J.encode(upsFor("def", "sage2:1")[1].t))
    AG.onUp("def", J.encode(upsFor("def", "sage3:1")[1].t))
    local function sages(f)
        local n = 0
        for _, x in ipairs(f.agents or {}) do if x.id:find("^sage") then n = n + 1 end end
        return n
    end
    local fd = feedFor("sage:1")
    eq(sages(fd), 3, "256 KB feeds: three 32 KB personas in one feed")
    sentToServer = {}
    AG.onHello({llm = true, agent_scores = true}, {type = "hello", version = "0.5.16", agent_functions = 32})
    fd = feedFor("sage:1")
    local allCut = true
    for _, x in ipairs(fd.agents or {}) do if x.id:find("^sage") and #x.persona ~= 8192 then allCut = false end end
    check(sages(fd) == 3 and allCut, "an older Koetama: the three cut to 8 KB, in one feed (under 36 KB)")
    for _, id in ipairs({"sage", "sage2", "sage3"}) do
        AG.define(id, nil)
        AG.onUp("remove", J.encode({kid = id .. ":1"}))
    end
    AG.onHello({llm = true, agent_scores = true}, {type = "hello", agent_functions = 32})
    AG.onDown(ana, "caps", J.encode(caps32))
    AG.define("cat", nil)
    AG.onUp("remove", J.encode({kid = "cat:1"}))
    -- (API 5) a final result ends the turn (no follow-up request), max_rounds, the tokens a reply used - each only
    -- for a Koetama whose hello names agent_final (0.5.16); ProxComms.finals() says so on every shard
    local henInfo = {}
    AG.define("hen", {persona = "x", max_rounds = 99, functions = {{name = "gather", description = "gather"}},
        onCall = function(call) henInfo.call = call return "ok: gathering 6 grass", true end,
        onReply = function(text, info) henInfo.reply = info end})
    local hd = upsFor("def", "hen:1")[1]
    check(hd and hd.t.max_rounds == 16, "max_rounds: at most 16")
    AG.define("hen2", {persona = "x"})
    check(upsFor("def", "hen2:1")[1] and upsFor("def", "hen2:1")[1].t.max_rounds == nil, "no max_rounds: none (no limit)")
    AG.define("hen2", nil)
    AG.onUp("def", J.encode(hd.t))
    sentToServer = {}
    AG.onHello({llm = true, agent_scores = true}, {type = "hello", agent_functions = 32})
    local _, henDef = feedFor("hen:1")
    check(henDef and henDef.max_rounds == nil and #AG.brain.defs["hen:1"].def.functions == 1,
        "a Koetama without agent_final: no max_rounds in the feed")
    local capsNo = downs("caps")[1]
    check(capsNo and capsNo.final == false, "caps: final false")
    AG.onDown(ana, "caps", J.encode(capsNo))
    eq(AG.finals(), false, "ProxComms.finals(): false")
    sentToServer = {}
    AG.onHello({llm = true, agent_scores = true, agent_final = true}, {type = "hello", agent_functions = 32})
    _, henDef = feedFor("hen:1")
    eq(henDef and henDef.max_rounds, 16, "agent_final: max_rounds in the feed")
    local capsYes = downs("caps")[1]
    check(capsYes and capsYes.final == true and capsYes.scores == true and capsYes.functions == 32, "caps: final true")
    AG.onDown(ana, "caps", J.encode(capsYes))
    eq(AG.finals(), true, "ProxComms.finals(): true")
    -- the reply: its words and its call carry the tokens it used; onCall returning text, true: a final result
    sentToServer = {}
    AG.onReply({type = "agent_reply", agent = "hen:1", final = true, ids = {}, text = "On it!", error = "",
        calls = {{call = "c_hen1", name = "gather", args = {what = "grass"}}},
        tokens_in = 5200, tokens_out = 12, tokens_cached = 4400})
    local hs, hc = downs("say")[1], downs("call")[1]
    check(hs and hs.tokens and hs.tokens.input == 5200 and hs.tokens.output == 12 and hs.tokens.cached == 4400,
        "the reply's tokens with its words")
    check(hc and hc.tokens and hc.tokens.input == 5200, "and with its call")
    sentToClient = {}
    AG.handle("say", hs)
    check(henInfo.reply and henInfo.reply.tokens and henInfo.reply.tokens.cached == 4400, "onReply: info.tokens")
    AG.handle("call", hc)
    check(henInfo.call and henInfo.call.tokens and henInfo.call.tokens.output == 12, "onCall: call.tokens")
    local hr = ups("result")[#ups("result")]
    check(hr and hr.t.call == "c_hen1" and hr.t.final == true, "onCall returning text, true: a final result")
    AG.onUp("result", J.encode(hr.t))
    local fdR = {}
    AG.feed(fdR)
    local rr
    for _, x in ipairs(fdR.agent_results or {}) do if x.call == "c_hen1" then rr = x end end
    check(rr and rr.final == true and rr.result == "ok: gathering 6 grass", "the feed: the result, final")
    -- ProxComms.result(callId, text, {final = true}) later; a plain one stays plain
    AG.calls.c_hen2 = {id = "hen", t = 0}
    AG.calls.c_hen3 = {id = "hen", t = 0}
    check(AG.result("c_hen2", "ok: done", {final = true}) and AG.result("c_hen3", "ok: started"), "result(id, text, opts)")
    local r2, r3
    for _, u in ipairs(ups("result")) do
        if u.t.call == "c_hen2" then r2 = u.t elseif u.t.call == "c_hen3" then r3 = u.t end
    end
    check(r2 and r2.final == true and r3 and r3.final == nil, "{final = true}: final; none: not")
    AG.onUp("result", J.encode(r2))
    -- a Koetama without agent_final never gets "final" (it would be a field it doesn't know)
    AG.onHello({llm = true, agent_scores = true}, {type = "hello", agent_functions = 32})
    local fdOld = {}
    AG.feed(fdOld)
    local oldFinal = false
    for _, x in ipairs(fdOld.agent_results or {}) do if x.final ~= nil then oldFinal = true end end
    check(not oldFinal, "an older Koetama: no final in agent_results")
    -- (a feed is at most 64 KB: the user's AI Villagers, 2026-11-17 - four villagers of ~16.5 KB each made every feed
    --  ~70 KB, refused whole, so only the one defined alone got through. Definitions go over several feeds instead,
    --  at most A.DEF_BUDGET in one, each until a feed carrying it is answered)
    do
        AG.onHello({llm = true, agent_scores = true, agent_final = true}, {type = "hello", agent_functions = 32})
        local big = {}
        local fns = {}
        for i = 1, 30 do
            fns[i] = {name = "act" .. i, description = string.rep("does a thing in the world ", 9),
                parameters = {type = "object", properties = {what = {type = "string", description = "what it acts on"}}}}
        end
        for i = 1, 4 do
            big[i] = "vil" .. i
            AG.define(big[i], {persona = string.rep("A villager who lives by the camp. ", 240), functions = fns})
            AG.onUp("def", J.encode(upsFor("def", big[i] .. ":1")[#upsFor("def", big[i] .. ":1")].t))
        end
        local size1 = #J.encode(AG.brain.defs["vil1:1"].def)
        check(size1 > 15000 and size1 < 20000, "(a villager's definition: ~16.5 KB - " .. size1 .. ")")
        AG.onKnown({agents = {}})                         -- (Koetama knows none of them)
        local known, feeds, worst = {}, 0, 0
        for _ = 1, 6 do
            local fd = {}
            AG.feed(fd)
            if not fd.agents then break end
            feeds = feeds + 1
            worst = math.max(worst, #J.encode(fd.agents))
            AG.fed(true)                                  -- (answered)
            for _, d in ipairs(fd.agents) do known[#known + 1] = {id = d.id, version = d.version} end
            AG.onKnown({agents = known})
        end
        local got = {}
        for _, k in ipairs(known) do got[k.id] = true end
        check(got["vil1:1"] and got["vil2:1"] and got["vil3:1"] and got["vil4:1"], "all four definitions reach Koetama")
        check(feeds >= 2 and worst <= AG.DEF_BUDGET + 20000, "over several feeds, none over the budget (" .. feeds .. " feeds, "
            .. math.floor(worst / 1024) .. " KB of definitions at most)")
        -- (a feed that is not answered: its definitions go again; before agents_known each goes until answered)
        AG.brain.defs["vil1:1"].okAt = nil
        AG.onKnown({agents = {}})
        AG.brain.known = nil
        AG.brain.sentAt = AG.brain.sentAt + 0.001
        local fd1 = {}
        AG.feed(fd1)
        AG.fed(false)
        local fd2 = {}
        AG.feed(fd2)
        local again = false
        for _, d in ipairs(fd2.agents or {}) do if d.id == (fd1.agents or {})[1].id then again = true end end
        check(fd1.agents and again, "a feed not answered: its definitions go again")
        AG.fed(true)
        for i = 1, 4 do AG.define(big[i], nil) AG.onUp("remove", J.encode({kid = big[i] .. ":1"})) end
    end
    -- (back as the scores tests had it)
    AG.onHello({llm = true, agent_scores = true}, {type = "hello", agent_functions = 32})
    AG.onDown(ana, "caps", J.encode(downs("caps")[#downs("caps")]))
    AG.define("hen", nil)
    AG.onUp("remove", J.encode({kid = "hen:1"}))
    AG.brain.results = {}
    -- a note goes as context (no reason by itself to answer: the turn stays scored); the line, count 0
    AG.note("dog", "Bob petted you")
    sentToClient = {}
    AG.hear("KU_bob", "Bob", "good boy Rex", "s", 11, 0)
    local dl = upsFor("line", "dog:1")
    check(#dl == 2 and dl[1].t.context == true and dl[1].t.text == "Bob petted you" and dl[2].t.context == nil
        and dl[2].t.depth == 0, "the note as context, then the line (count 0)")
    for _, x in ipairs(dl) do AG.onUp("line", J.encode(x.t)) end
    local _, _, fl = feedFor("dog:1")
    check(#fl == 2 and fl[1].context == true and fl[1].from == nil and fl[2].context == nil and fl[2].from.id == "KU_bob",
        "the feed: the note with context, the line without")
    -- Koetama's scores: to its shard, whose mod decides; the decision in the feed until Koetama has it
    sentToServer = {}
    AG.onScores({type = "agent_scores", agent = "dog:1", turn = 7, ids = {fl[1].id, fl[2].id},
        scores = {topic = 0.9, food = 0.1, ["bad key"] = 1, big = 3}})
    local sd = downs("scores")[1]
    check(sd and sd.kid == "dog:1" and sd.turn == 7 and sd.scores.topic == 0.9 and sd.scores["bad key"] == nil
        and sd.scores.big == 1 and sd.from[1] == "KU_bob" and #sd.from == 1, "agent_scores: to its shard (who said it)")
    check(sd and sd.text[1] == "[Bob petted you]" and sd.text[2] == "Bob: good boy Rex", "with what was said")
    AG.onScores({agent = "nobody:1", turn = 1, ids = {}, scores = {}})
    eq(#downs("scores"), 1, "scores for an agent it doesn't know: dropped")
    sentToClient = {}
    AG.handle("scores", sd)
    check(scored[1] and scored[1].sc.topic == 0.9 and scored[1].info.turn == 7 and scored[1].info.from[1] == "KU_bob"
        and scored[1].info.text[2] == "Bob: good boy Rex", "the mod's onScores")
    local dc = upsFor("decide", "dog:1")[1]
    check(dc and dc.t.turn == 7 and dc.t.answer == true, "it returned true: answer, back to the brain")
    AG.onUp("decide", J.encode(dc.t))
    local fd = feedFor("dog:1")
    check(fd.agent_decisions and fd.agent_decisions[1].agent == "dog:1" and fd.agent_decisions[1].turn == 7
        and fd.agent_decisions[1].answer == true, "the feed: agent_decisions")
    check(AG.busy(), "a decision waiting: feed often")
    AG.onReceived({agent_decisions = {7}})
    fd = feedFor("dog:1")
    check(not fd.agent_decisions, "Koetama has it: not sent again")
    AG.onUp("decide", J.encode({kid = "dog:1", turn = 7, answer = false}))
    fd = feedFor("dog:1")
    check(not fd.agent_decisions, "a decision for a turn not waiting: ignored")
    -- answered: said, count 1 (the note doesn't count); the turn over
    sentToServer = {}
    AG.onReply({type = "agent_reply", final = true, ids = {fl[1].id, fl[2].id}, agent = "dog:1", text = "Woof!", calls = {}, error = ""})
    local ds = downs("say")[1]
    check(ds and ds.text == "Woof!" and ds.depth == 1 and ds.from[1] == "KU_bob", "answered: said, count 1")
    eq(#AG.brain.decisions, 0, "its turn over: the decision dropped")
    -- skipped: low scores, nothing said, no engagement, the mod told
    sentToClient = {}
    AG.hear("KU_cid", "Cid", "nice weather", "s", 11, 0)
    local l3 = upsFor("line", "dog:1")[1]
    AG.onUp("line", J.encode(l3.t))
    local id3 = AG.brain.n
    sentToServer = {}
    AG.onScores({agent = "dog:1", turn = 8, ids = {id3}, scores = {topic = 0.1, food = 0}})
    sentToClient = {}
    AG.handle("scores", downs("scores")[1])
    local dc2 = upsFor("decide", "dog:1")[1]
    check(dc2 and dc2.t.turn == 8 and dc2.t.answer == false, "low scores: the mod skips")
    AG.onUp("decide", J.encode(dc2.t))
    sentToServer = {}
    AG.onReply({type = "agent_reply", agent = "dog:1", final = true, ids = {id3}, text = "", calls = {}, error = "", skipped = true})
    local sk = downs("skip")[1]
    check(#downs("say") == 0 and sk and sk.kid == "dog:1" and sk.from[1] == "KU_cid", "skipped: nothing said, the skip to its shard")
    TheWorld.events = {}
    AG.handle("skip", sk)
    check(AG.agents.dog.skipn == 1 and skips[1] and skips[1].from[1] == "KU_cid", "skipn counted, the mod's onSkip")
    check(TheWorld.events[1] and TheWorld.events[1][1] == "proxcomms_agent_skip", "and the world event")
    check(not (AG.eng.dog and AG.eng.dog.KU_cid), "not engaged with Cid for it")
    -- a decision later: onScores returns nil, then ProxComms.decide
    AG.agents.dog.onScores = function() return nil end
    sentToServer = {}
    AG.onScores({agent = "dog:1", turn = 9, ids = {id3}, scores = {topic = 0.5}})
    sentToClient = {}
    AG.handle("scores", downs("scores")[1])
    eq(#upsFor("decide", "dog:1"), 0, "onScores nil: no decision yet")
    check(AG.decide("dog", 9, true) and upsFor("decide", "dog:1")[1].t.turn == 9, "ProxComms.decide: later")
    check(not AG.decide("nobody", 9, true), "decide: an unknown agent refused")
    AG.onHello({llm = true, agent_scores = true})
    eq(next(AG.brain.scorePending), nil, "a new hello: turns waiting forgotten (Koetama numbers them afresh)")
    AG.define("dog", nil)
    -- ---- API 2: agents hear agents (the Teardown mod's API 20) - counted, so their talk ends
    local spot = {Transform = {GetWorldPosition = function() return 13, 0, 0 end}, IsValid = function() return true end}
    AG.define("gus", {persona = "You are Gus.", name = "Gus", entity = spot, hears = "near", hearagents = 2})
    AG.define("mira", {persona = "You are Mira.", name = "Mira", entity = spot, hears = "near", hearagents = 2})
    AG.define("deaf", {persona = "You are deaf to agents.", name = "Deaf", entity = spot, hears = "near"})
    check(AG.agents.gus.hearagents == 2 and AG.agents.deaf.hearagents == 0, "hearagents (none: 0)")
    AG.define("big", {persona = "x", hearagents = 999})
    eq(AG.agents.big.hearagents, 50, "hearagents at most 50")
    AG.define("big", nil)
    sentToClient = {}
    AG.handle("say", {kid = "gus:1", text = "Lovely day, Mira!", from = {"KU_bob"}, lines = {}, depth = 1})
    check(#AG.later == 1 and #upsFor("line", "mira:1") == 0, "an agent's line: the others hear it after a pause to read it")
    advance(0.5)
    AG.laterTick()
    eq(#upsFor("line", "mira:1"), 0, "not yet")
    advance(5)
    AG.laterTick()
    local ml = upsFor("line", "mira:1")[1]
    check(ml and ml.t.from.id == "agent:gus:1" and ml.t.from.name == "Gus" and ml.t.depth == 1, "then Mira hears Gus (count 1)")
    eq(#upsFor("line", "gus:1"), 0, "never itself")
    eq(#upsFor("line", "deaf:1"), 0, "an agent without hearagents: not")
    eq(#upsFor("line", "pigking:1"), 0, "nor the Pig King")
    AG.onUp("line", J.encode(ml.t))
    local mid = AG.brain.n
    sentToServer = {}
    AG.onReply({type = "agent_reply", agent = "mira:1", final = true, ids = {mid}, text = "It is, Gus.", calls = {}, error = ""})
    local ms = downs("say")[1]
    check(ms and ms.depth == 2 and ms.from[1] == "agent:gus:1", "her answer: count 2 (it answers Gus)")
    sentToClient = {}
    AG.handle("say", ms)
    check(AG.eng.mira and AG.eng.mira["agent:gus:1"], "engaged with Gus")
    -- (API 6) a line from the buffer zone (between the mode's range and its reach) heard garbled, as a player there
    --  reads it; past the reach nothing; a name lost in the garble not heard
    do
        local rs = AG.S.ranges.s
        local here = {Transform = {GetWorldPosition = function() return 0, 0, 500 end}, IsValid = function() return true end}
        AG.define("ear", {persona = "x", name = "Ear", entity = here, hears = "near"})
        AG.define("nom", {persona = "x", name = "Rosalind", entity = here, hears = "named"})
        local function heardBy(kid)
            local out = {}
            for _, u in ipairs(upsFor("line", kid)) do if not u.t.context then out[#out + 1] = u.t end end
            return out
        end
        sentToClient = {}
        AG.hear("KU_bob", "Bob", "the berries are over by the big rock", "s", rs[1] - 1, 500)
        local l1 = heardBy("ear:1")[1]
        check(l1 and l1.text == "the berries are over by the big rock" and l1.from.id == "KU_bob", "within the range: whole")
        sentToClient = {}
        AG.hear("KU_bob", "Bob", "the berries are over by the big rock", "s", (rs[1] + rs[2]) / 2, 500)
        local l2 = heardBy("ear:1")[1]
        check(l2 and l2.text:find(T.GARBLE, 1, true) and l2.text ~= "the berries are over by the big rock" and l2.from.name == "Bob",
            "in the buffer: garbled, as a player there reads it (who said it kept)")
        sentToClient = {}
        AG.hear("KU_bob", "Bob", "the berries are over by the big rock", "s", rs[2] + 2, 500)
        eq(#heardBy("ear:1"), 0, "past the reach: nothing")
        sentToClient = {}
        AG.hear("KU_bob", "Bob", "Rosalind, come here", "s", rs[1] - 1, 500)
        eq(#heardBy("nom:1"), 1, "a named agent near: its name heard")
        sentToClient = {}
        AG.hear("KU_cid", "Cid", "Rosalind, come here", "s", rs[2] - 0.2, 500)
        eq(#heardBy("nom:1"), 0, "its name lost in the garble (at the edge of the reach): not heard")
        AG.define("ear", nil)
        AG.define("nom", nil)
    end
    -- (API 4) onSay: a reply before it is said - false: nothing (not heard by the others either), a string: that
    -- instead, nil or an error: as it is; such an agent shows no live words
    local vetted = {}
    AG.define("vil", {persona = "You are Willow.", name = "Willow", entity = spot, hears = "near",
        onSay = function(text, info)
            vetted[#vetted + 1] = {text = text, from = info.from}
            if text:upper():find("NO WORDS") then return false end
            if text:find("^Willow: ") then return (text:gsub("^Willow: ", "")) end
            if text == "boom" then error("a broken hook") end
        end,
        onReply = function(text) vetted.said = text end})
    sentToClient = {}
    local laterN = #AG.later
    AG.handle("say", {kid = "vil:1", text = "NO WORDS.", from = {"KU_bob"}, lines = {}, depth = 1})
    check(#vetted == 1 and vetted[1].text == "NO WORDS." and vetted[1].from[1] == "KU_bob", "onSay: sees the reply and who it answers")
    check(lastTo("line") == nil and #AG.later == laterN and vetted.said == nil,
        "onSay false: nothing said, nobody (no agent) hears it, no onReply")
    AG.handle("say", {kid = "vil:1", text = "Willow: Hello, Bob.", from = {"KU_bob"}, lines = {}, depth = 1})
    check(lastTo("line") and lastTo("line").args[3] == "Hello, Bob." and vetted.said == "Hello, Bob.", "onSay a string: said instead")
    sentToClient = {}
    AG.handle("say", {kid = "vil:1", text = "Nice day.", from = {}, lines = {}, depth = 1})
    eq(lastTo("line") and lastTo("line").args[3], "Nice day.", "onSay nil: said as it is")
    sentToClient = {}
    AG.handle("say", {kid = "vil:1", text = "boom", from = {}, lines = {}, depth = 1})
    eq(lastTo("line") and lastTo("line").args[3], "boom", "onSay errors: said as it is")
    sentToClient = {}
    AG.handle("live", {kid = "vil:1", utt = 1, text = "NO WO"})
    eq(lastTo("live"), nil, "an agent with onSay: no live words")
    AG.handle("live", {kid = "gus:1", utt = 1, text = "Lovely"})
    check(lastTo("live") ~= nil, "(one without: its live words as before)")
    AG.define("vil", nil)
    advance(5)
    AG.laterTick()
    local gl = upsFor("line", "gus:1")[1]
    check(gl and gl.t.depth == 2 and gl.t.from.id == "agent:mira:1", "Gus hears it (count 2: his hearagents)")
    sentToClient = {}
    AG.handle("say", {kid = "gus:1", text = "Indeed.", from = {"agent:mira:1"}, lines = {}, depth = 3})
    advance(5)
    AG.laterTick()
    check(#AG.later == 0 and #upsFor("line", "mira:1") == 0, "count 3, past their hearagents: the talk ends")
    sentToClient = {}
    AG.say("gus", "Hm.")
    advance(5)
    AG.laterTick()
    local sl = upsFor("line", "mira:1")
    check(#sl == 1 and sl[1].t.depth == 1 and sl[1].t.text == "Hm.", "a say: count 1")
    sentToClient = {}
    AG.hear("KU_bob", "Bob", "hi all", "s", 13, 0)
    check(upsFor("line", "gus:1")[1] and upsFor("line", "gus:1")[2].t.depth == 0, "a player's line: count 0 again (after Gus's own said line)")
    AG.define("gus", nil)
    AG.define("mira", nil)
    AG.define("deaf", nil)
    -- on another shard: through the shards
    sentToClient, sentToShard = {}, {}
    local mePlayers = AllPlayers
    AllPlayers = {me, bob}
    AG.event("pigking", "the bell rings")
    check(#ups() == 0 and sentToShard[#sentToShard].name == "agent_up", "the brain on another shard: through the shards")
    AllPlayers = mePlayers
    -- removed; the brain gone
    AG.define("pigking", nil)
    check(AG.agents.pigking == nil and ups("remove")[1], "removed: the brain told")
    AG.onLlm(ana, false)
    eq(AG.owner, nil, "the admin's language model off: no brain")
    eq(AG.status(), "off", "agents: off")
    check(not AG.scoring(), "no brain: no scores")
    clientTable[2].admin = nil
    AG.onOwner(false)
end

-- ============================================================================ settings
Settings.vol = {KU_ana = 1.5}
Settings.save()
Settings.vol = {}
Settings.load()
eq(Settings.volumeOf("KU_ana"), 1.5, "settings are kept")
Settings.apply({mode = "q", mic = "loud", textSize = 99})
check(Settings.mode ~= "q" and Settings.mic ~= "loud" and Settings.textSize == 1.6, "bad settings are ignored or clamped")

-- ============================================================================ the wheel: pictures and building a message
do
    local xml = io.open(ROOT .. "images/pc_wheel.xml"):read("*a")
    local keys = {"callouts", "questions", "replies", "things", "insults", "social", "survival"}
    local missing = {}
    local function need(name) if not xml:find('name="' .. name .. '"', 1, true) then missing[#missing + 1] = name end end
    need("pc_quick.tex") need("pc_players.tex") need("pc_questions_1.tex")
    for lang, tbl in pairs(Strings.tables) do
        eq(#tbl.WHEEL_FOLDERS, #keys, lang .. ": a folder for every picture set")
        for i, f in ipairs(tbl.WHEEL_FOLDERS) do
            need("pc_" .. keys[i] .. ".tex")
            for j = 1, #f[2] do need("pc_" .. keys[i] .. "_" .. j .. ".tex") end
        end
    end
    eq(#missing, 0, "every wheel picture is in the atlas (missing: " .. table.concat(missing, ", ") .. ")")
    local tex = io.open(ROOT .. "images/pc_wheel.tex", "rb"):read("*a")
    check(tex:sub(1, 4) == "KTEX", "the wheel's sheet is a KTEX texture")

    local W = require "proxcomms/wheel"
    W.CL = CL
    local t, open, atMain, item, closed, backs, mains, openedWheel = 0, true, false, nil, 0, 0, 0, nil
    W.env = {now = function() return t end, inQuick = function() return open end, atMain = function() return atMain end,
        item = function() return item end, close = function() closed = closed + 1 open = false end,
        back = function() backs = backs + 1 end, toMain = function() mains = mains + 1 atMain = true end,
        open = function(name) openedWheel = name end, refresh = function() end}
    CONTROL_ACCEPT, CONTROL_CANCEL, CONTROL_MENU_MISC_1, CONTROL_MENU_MISC_2 = 3, 2, 68, 69
    W.clear()
    CL.setMode("y")
    -- X: the picked line into the message, back to the main wheel
    item = {pc_text = "Where?"}
    check(W.control(CONTROL_MENU_MISC_1, true), "X is ours")
    W.control(CONTROL_MENU_MISC_1, false)
    check(W.text() == "Where?" and mains == 1, "X adds the line and goes back to the main wheel")
    atMain, item = false, {pc_text = "Food"}
    W.control(CONTROL_MENU_MISC_1, true) W.control(CONTROL_MENU_MISC_1, false)
    eq(W.text(), "Where? Food", "a second folder's word")
    -- Y: the last piece back
    W.control(CONTROL_MENU_MISC_2, true) W.control(CONTROL_MENU_MISC_2, false)
    eq(W.text(), "Where?", "Y takes the last piece back")
    -- X on a folder: opens it, nothing added
    item = {nestedwheel = {name = "pc_folder3"}}
    W.control(CONTROL_MENU_MISC_1, true) W.control(CONTROL_MENU_MISC_1, false)
    check(openedWheel == "pc_folder3" and W.text() == "Where?", "X on a folder opens it")
    -- A: the message sent as it is (a picked line is not added), the wheel closed
    item = {pc_text = "Base"}
    sentToServer = {}
    check(W.control(CONTROL_ACCEPT, true), "A is ours")
    check(W.control(CONTROL_ACCEPT, false), "and its release")
    check(lastServer("say") and lastServer("say").args[1] == C.PAD_MARK .. "Where?" and lastServer("say").args[2] == "y",
        "A: the message sent, with the controller's mark, in the chat mode (the picked line not added)")
    check(closed == 1 and W.text() == "", "and the wheel closes")
    -- A on a folder: sends too
    open, item = true, {nestedwheel = {name = "pc_folder1"}}
    W.add("Hi!")
    sentToServer = {}
    check(W.control(CONTROL_ACCEPT, true) and W.control(CONTROL_ACCEPT, false), "A on a folder is ours")
    eq(lastServer("say").args[1], C.PAD_MARK .. "Hi!", "and sends the message")
    -- an A release without its press in Quick chat (the press opened Quick chat from DST's wheel): nothing sent
    open = true
    W.add("Hi!")
    sentToServer = {}
    W.control(CONTROL_ACCEPT, false)
    check(lastServer("say") == nil and open and W.text() == "Hi!", "a release whose press was elsewhere sends nothing")
    W.clear()
    -- B: one wheel back; on the main wheel: cancel
    open, atMain = true, false
    W.add("You suck")
    W.control(CONTROL_CANCEL, true) t = t + 0.1 W.control(CONTROL_CANCEL, false)
    check(backs == 1 and W.text() == "You suck", "B in a folder: one wheel back, the message kept")
    atMain = true
    sentToServer = {}
    W.control(CONTROL_CANCEL, true) t = t + 0.1 W.control(CONTROL_CANCEL, false)
    check(closed == 3 and W.text() == "" and lastServer("say") == nil, "B on the main wheel: cancelled, nothing sent")
    -- hold B: cancel from anywhere, its release swallowed
    open, atMain = true, false
    W.add("Bruh")
    W.control(CONTROL_CANCEL, true) t = t + 0.6 W.tick()
    check(closed == 4 and W.text() == "", "hold B: cancelled")
    check(W.control(CONTROL_CANCEL, false), "its release is swallowed")
    -- the command wheel's button twice: Quick chat (on the second release, while the wheel is open)
    W.lastTap = nil
    check(not W.wheelButton(true, false, 10), "a press: nothing yet")
    check(not W.wheelButton(false, false, 10.05), "the first release: DST's wheel opens as always")
    check(not W.wheelButton(true, true, 10.15), "the second press: nothing yet")
    check(W.wheelButton(false, true, 10.2), "the second release within 0.35 s: Quick chat")
    check(not W.wheelButton(false, false, 11), "a release long after: DST's own again")
    check(not W.wheelButton(false, true, 12), "and a slow second press closes the wheel as DST does")
    -- too long: not added
    W.clear()
    check(not W.add(string.rep("x", 200)), "a piece past a chat line's length is not added")
    open = true
    W.env = nil
    CL.setMode("s")
end

-- ============================================================================ the chat line (ChatInputScreen hook)
KEY_TAB, KEY_UP, KEY_DOWN = 9, 273, 274
CONTROL_MENU_MISC_2, CONTROL_CANCEL, CONTROL_ACCEPT = 1, 2, 3
STRINGS = {UI = {HELP = {BACK = "Back"}}}
TALKINGFONT = "talkingfont"
package.loaded["widgets/textbutton"] = function(name)
    local btn = {name = name}
    function btn:SetFont() end function btn:SetTextSize() end function btn:SetPosition() end
    function btn:SetText(t) self.text = t end function btn:SetTextColour() end function btn:GetSize() return 100 end
    function btn:SetOnClick(fn) self.onclick = fn end
    return btn
end
local function fakeScreen(whisper)
    local s = {whisper = whisper, closed = false}
    s.chat_type = {Hide = function() s.typeHidden = true end, SetString = function(_, t) s.typeText = t end}
    s.root = {AddChild = function(_, w) return w end}
    s.chat_edit = {str = "", GetString = function(e) return e.str end, SetString = function(e, v) e.str = v end,
        SetFocus = function() end, SetEditing = function() end, OnTextInput = function() return true end,
        OnRawKey = function() return false end}
    s.OnRawKey = function() return "base" end
    s.OnControl = function() return "base" end
    s.GetHelpText = function() return "" end
    s.Run = function() s.baseRan = true end
    s.Close = function() s.closed = true end
    return s
end
local hook = require("proxcomms/chatinput")(CL, function() end)
CL.setMode("s")
local scr = fakeScreen(false)
hook(scr)
eq(scr.pc_mode, "s", "the line opens in this player's mode")
check(scr.typeHidden and scr.pc_modebtn.text == "Speak:", "the mode button replaces say:")
scr.chat_edit:OnRawKey(KEY_TAB, true)
eq(scr.pc_mode, "y", "Tab: the next mode")
eq(CL.mode, "y", "and it is this player's mode (typing and talking)")
check(scr.chat_edit:OnTextInput("\t") == true, "a tab never goes into the text")
sentToServer = {}
scr.chat_edit.str = "  over here  "
scr:Run()
check(lastServer("say").args[1] == "over here" and lastServer("say").args[2] == "y", "Enter: the line in the mode")
scr.chat_edit.str = "/wave"
scr:Run()
check(scr.baseRan, "the game's commands still run")
scr.chat_edit:OnRawKey(KEY_UP, true)
eq(scr.chat_edit.str, "/wave", "Up: the last line")
scr.chat_edit:OnRawKey(KEY_UP, true)
eq(scr.chat_edit.str, "over here", "Up again: the one before")
-- a line sent from a controller starts with the four dots; from a keyboard it does not
controller = true
local psc = fakeScreen(false)
hook(psc)
sentToServer = {}
psc.chat_edit.str = "on my way"
psc:Run()
eq(lastServer("say").args[1], C.PAD_MARK .. "on my way", "from a controller: the four dots first")
controller = false
psc.chat_edit.str = "typed"
psc:Run()
eq(lastServer("say").args[1], "typed", "from a keyboard: no mark")
local wsc = fakeScreen(true)
hook(wsc)
eq(wsc.pc_mode, "w", "DST's whisper key opens a whisper line")
sentToServer = {}
wsc.chat_edit.str = "psst"
wsc:Run()
check(wsc.baseRan and wsc.whisper == true and lastServer("say") == nil, "Whisper goes through DST's own Run (other mods' hooks on it run)")
CL.setMode("s")
local gsc = fakeScreen(false)
hook(gsc)
gsc.chat_edit:OnRawKey(KEY_TAB, true)
gsc.chat_edit:OnRawKey(KEY_TAB, true)
eq(gsc.pc_mode, "g", "Tab round to Global")
gsc.chat_edit.str = "hello all"
gsc:Run()
check(gsc.baseRan and gsc.whisper == false, "Global goes through DST's own Run")
CL.setMode("s")

-- ============================================================================ modmain (in a mod environment: only what DST gives one)
do
    local registered = {}
    local env = {pairs = pairs, ipairs = ipairs, print = print, math = math, table = table, type = type, string = string,
        tostring = tostring, require = require, Class = Class, TUNING = {}, GLOBAL = _G, modname = "proxcomms", MODROOT = ROOT}
    env.env = env
    local function reg(kind) return function(ns, name, fn) registered[#registered + 1] = kind .. ":" .. name end end
    env.AddModRPCHandler, env.AddClientModRPCHandler, env.AddShardModRPCHandler = reg("server"), reg("client"), reg("shard")
    env.AddPrefabPostInit = function(name, fn) registered[#registered + 1] = "prefab:" .. name end
    local classFns = {}
    env.AddClassPostConstruct = function(name, fn) registered[#registered + 1] = "class:" .. name classFns[name] = fn end
    local userCommands = {}
    env.AddUserCommand = function(name, data) registered[#registered + 1] = "command:" .. name userCommands[name] = data end
    function Asset(kind, path) return {kind = kind, path = path} end
    COMMAND_PERMISSION = {USER = "user"}
    local componentInit = {}
    env.AddComponentPostInit = function(name, fn) registered[#registered + 1] = "component:" .. name componentInit[name] = fn end
    env.GetModConfigData = function(k) return ({whisper_range = 8, speak_range = 18, yell_range = 32, voice = true, voice_region = ""})[k] end
    -- (a FUTURE Networking_Say: one more argument than today's; it shows the line over the head unless too long)
    local got
    Networking_Say = function(guid, userid, name, prefab, message, colour, whisper, isemote, vanity, extra)
        got = {n = select("#", guid, userid, name, prefab, message, colour, whisper, isemote, vanity, extra), extra = extra}
        local e = Ents[guid]
        if not isemote and e and e.components.talker and #message <= 150 then e.components.talker:Say(message) end
        return "dst's result"
    end
    unpack = unpack or table.unpack
    ChatHistory.GenerateChatMessage = function() return {} end
    local dstHistory = {}
    ChatHistory.OnSay = function(self, guid, userid, netid, name, prefab, message, colour, whisper, isemote)
        dstHistory[#dstHistory + 1] = message
    end
    LOC = {GetLanguage = function() return 1 end}
    TheInput.AddKeyHandler = function() end
    MAX_CHAT_INPUT_LENGTH = 150
    local fontCalls = {}
    ModManager = {RegisterPrefabs = function() fontCalls[#fontCalls + 1] = "register" end,
        UnloadPrefabsFromData = function() fontCalls[#fontCalls + 1] = "unloadprefabs" end}
    TheSim.LoadFont = function(_, file, alias) fontCalls[#fontCalls + 1] = "load:" .. alias .. ":" .. file end
    TheSim.UnloadFont = function(_, alias) fontCalls[#fontCalls + 1] = "unload:" .. alias end
    TheSim.SetupFontFallbacks = function(_, alias, fb) fontCalls[#fontCalls + 1] = "fallbacks:" .. alias .. ":" .. tostring(fb) end
    DEFAULT_FALLBACK_TABLE_OUTLINE = "outline-fallbacks"
    package.loaded["screens/pc_settingsscreen"] = {}
    local chunk = assert(loadfile(ROOT .. "modmain.lua"))
    setfenv(chunk, env)
    local ok, err = pcall(chunk)
    check(ok, "modmain runs in a mod environment: " .. tostring(err))
    eq(#registered, 9 + 8 + 11 + 2 + 5 + 1 + 1, "modmain registers its RPCs, world hooks, UI hooks, the talker hook and its menu entry")
    local menu = userCommands.proxcomms
    check(menu and menu.servermenu == true and menu.localfn and not menu.serverfn and menu.slash == false, "Proximity Comms in the Miscellaneous / Server Actions window: client-side, no slash command")
    check(env.Assets and #env.Assets == 5 and env.Assets[1].path == "images/pc_wheel.xml" and env.Assets[3].path == "images/pc_bubble.xml"
        and env.Assets[5].kind == "FONT" and env.Assets[5].path == ROOT .. "fonts/pc_pangolin.zip",
        "the wheel's pictures, the bubble's box and its font are the mod's assets")
    -- the font: (re)loaded after the mods' prefabs are, with the game's fallbacks; let go of before they are dropped
    fontCalls = {}
    ModManager:RegisterPrefabs()
    eq(table.concat(fontCalls, " "), "register unload:pc_pangolin load:pc_pangolin:" .. ROOT .. "fonts/pc_pangolin.zip "
        .. "fallbacks:pc_pangolin:outline-fallbacks", "the bubbles' font loads after the mod's prefab, falling back on the game's fonts")
    fontCalls = {}
    ModManager:UnloadPrefabsFromData({})
    eq(table.concat(fontCalls, " "), "unload:pc_pangolin unloadprefabs", "and is let go of before it")
    local zip = io.open(ROOT .. "fonts/pc_pangolin.zip", "rb")
    check(zip and zip:read(2) == "PK", "the font package is there (tools/make_font.py)")
    if zip then zip:close() end
    local opened
    local was = CL.openSettings
    CL.openSettings = function(page) opened = page end
    menu.localfn({}, ThePlayer)
    eq(opened, 1, "the menu entry opens the settings")
    CL.openSettings = was
    -- DST's own Say through the chain: nothing re-implemented, every argument passed on, only the text over the head
    -- blanked (and drawn by the mod)
    local said = {}
    local talker = {Say = function(t, script) said[#said + 1] = script end}
    componentInit.talker(talker)
    local ana_e = {components = {talker = talker}, HasTag = function() return false end}
    Ents = {[7] = ana_e}
    ThePlayer.HUD = {}
    Settings.bubbles = true
    CL.bubbles = {}
    local r = Networking_Say(7, "KU_ana", "Ana", "wilson", "hello there", {1, 0, 0, 1}, false, false, {}, "future")
    eq(r, "dst's result", "DST's result comes back")
    check(got.n == 10 and got.extra == "future", "every argument reaches DST's Networking_Say (a future one too)")
    eq(said[1], "", "DST's text over the head is blanked")
    check(CL.bubbles.KU_ana and CL.bubbles.KU_ana.cur.full == "hello there" and CL.bubbles.KU_ana.cur.native, "the mod draws the line")
    eq(talker.pc_blank, nil, "the blanking is used once")
    talker:Say("It's getting dark")
    eq(said[2], "It's getting dark", "the character's own quips are untouched")
    CL.bubbles = {}
    Networking_Say(7, "KU_ana", "Ana", "wilson", string.rep("x", 200), {1, 0, 0, 1}, false, false, {})
    check(CL.bubbles.KU_ana == nil and talker.pc_blank == nil, "a line DST does not show: no bubble, nothing left blanked")
    Networking_Say(7, "KU_ana", "Ana", "wilson", "waves", {1, 0, 0, 1}, false, true, {})
    check(CL.bubbles.KU_ana == nil and #said == 2, "an emote: DST's, untouched")
    Settings.bubbles = false
    Networking_Say(7, "KU_ana", "Ana", "wilson", "bubbles off", {1, 0, 0, 1}, false, false, {})
    eq(said[3], "bubbles off", "bubbles off: DST's own text over the head")
    -- the history: a translated line's original smaller than its translation (its colour table marked, then its rows)
    do
        local m = {message = "hola", m_colour = {1, 1, 1, 1}}
        local b = {histMsg = m, hist = true, level = "full", name = "Ana"}
        local shared = m.m_colour
        CL.translated("KU_ana", "Ana", "hello", b)
        check(m.m_colour.pc_small and m.m_colour ~= shared and shared.pc_small == nil, "translated: the original's history line marked small (its own colour table)")
        local row = {message = {size = 30}}
        function row.message:SetSize(sz) self.size = sz end
        function row.message:GetRegionSize() return 100, 20 end
        function row.message:SetPosition(x) self.x = x end
        row.SetChatData = function() end
        classFns["widgets/redux/chatline"](row)
        row:SetChatData(1, 1, "hola", m.m_colour)
        eq(row.message.size, 30 * 0.6, "its row: 60 % of the size")
        row:SetChatData(1, 1, "hello", {1, 0.6, 0.78, 1})
        eq(row.message.size, 30, "the next line in that row: full size again")
    end
    -- a whisper: the mod's (its range, its history line), bubbles on or off; DST's own history line left out
    history = {}
    Networking_Say(7, "KU_ana", "Ana", "wilson", "psst over here", {1, 0, 0, 1}, true, false, {})
    check(CL.bubbles.KU_ana and CL.bubbles.KU_ana.cur.mode == "w" and CL.bubbles.KU_ana.cur.full == "psst over here",
        "bubbles off: a whisper is still the mod's")
    check(#history == 1 and history[1].sender:find("Ana") and history[1].text == "psst over here", "its history line is the mod's")
    ChatHistory:OnSay(7, "KU_ana", 1, "Ana", "wilson", "psst over here", {1, 0, 0, 1}, true, false)
    ChatHistory:OnSay(7, "KU_ana", 1, "Ana", "wilson", "a Global line", {1, 0, 0, 1}, false, false)
    check(#dstHistory == 1 and dstHistory[1] == "a Global line", "DST's history: its whisper line left out, the rest kept")
    Settings.bubbles = true
    Networking_Say(7, "KU_ana", "Ana", "wilson", string.rep("x", 200), {1, 0, 0, 1}, true, false, {})
    check(CL.bubbles.KU_ana.cur.full == "psst over here", "a whisper DST turns away (too long): nothing")
    -- a mime (Wes): over his head too, in brackets, in DST's own modes as well
    local mimeTalker = {Say = function(t, script) said[#said + 1] = script end}
    componentInit.talker(mimeTalker)
    Ents[8] = {components = {talker = mimeTalker}, HasTag = function(_, t) return t == "mime" end}
    CL.bubbles = {}
    Networking_Say(8, "KU_bob", "Bob", "wes", "hi all", {1, 0, 0, 1}, false, false, {})
    check(CL.bubbles.KU_bob and CL.bubbles.KU_bob.cur.full == "hi all", "a mime's Global line: a bubble (no mime rule in the mod)")
    ThePlayer.HUD = nil
    local info = {locale = "en"}
    local ichunk = assert(loadfile(ROOT .. "modinfo.lua"))
    setfenv(ichunk, info)
    ichunk()
    check(info.all_clients_require_mod == true and info.client_only_mod == false and info.api_version == 10 and info.dst_compatible, "modinfo: every player needs it, API 10")
    eq(info.author, "McPuppetFace", "modinfo: the author")
    check(info.icon_atlas == "modicon.xml" and info.icon == "modicon.tex", "modinfo: the icon")
    local xml = io.open(ROOT .. "modicon.xml"):read("*a")
    check(xml:find('filename="modicon.tex"', 1, true) and xml:find('name="modicon.tex"', 1, true), "the icon's atlas names its texture")
    local tex = io.open(ROOT .. "modicon.tex", "rb"):read("*a")
    check(tex:sub(1, 4) == "KTEX" and #tex > 16384, "the icon is a KTEX texture")
    eq(#info.configuration_options, 5, "modinfo: the host's options")
    local defaults = {}
    for _, o in ipairs(info.configuration_options) do defaults[o.name] = o.default end
    check(defaults.whisper_range == C.WHISPER_TILES and defaults.speak_range == C.SPEAK_TILES and defaults.yell_range == C.YELL_TILES,
        "modinfo: the distances' defaults are the code's (8, 18, 32)")
    for _, loc in ipairs({"zh", "ru"}) do
        local i2 = {locale = loc}
        local c2 = assert(loadfile(ROOT .. "modinfo.lua"))
        setfenv(c2, i2)
        c2()
        check(i2.description and not i2.description:find("Proximity chat:"), "modinfo in " .. loc)
    end
end


-- ============================================================================ the bubbles (a mocked widget system)
do
    local W = {}
    local function widget(name)
        local w = {name = name, children = {}, shown = true, x = 0, y = 0}
        function w:AddChild(c) self.children[#self.children + 1] = c c.parent = self return c end
        function w:SetScaleMode() end function w:SetMaxPropUpscale() end function w:SetClickable() end
        function w:Hide() self.shown = false end function w:Show() self.shown = true end
        function w:Kill() self.killed = true end
        function w:SetPosition(x, y) self.x, self.y = x, y end
        function w:StartUpdating() end function w:MoveToBack() end function w:SetScale() end
        function w:SetHAnchor() end function w:SetVAnchor() end
        function w:OnRawKey() return false end function w:OnControl() return false end
        function w:SetFocusChangeDir(dir, to) self.dirs = self.dirs or {} self.dirs[dir] = to end function w:SetFocus() self.focused = true end
        function w:SetText(t) self.text_ = t end
        return w
    end
    package.loaded["widgets/widget"] = Class(function(self, name) for k, v in pairs(widget(name)) do if self[k] == nil then self[k] = v end end end)
    package.loaded["widgets/text"] = Class(function(self, font, size, str)
        for k, v in pairs(widget("text")) do if self[k] == nil then self[k] = v end end
        self.font, self.size, self.str = font, size, str or ""
        function self:SetFont(f) self.font = f end
        function self:SetSize(sz) self.size = sz end
        function self:SetString(t) self.str = t end
        function self:SetColour(...) self.colour = {...} end
        function self:GetRegionSize()
            local w, n = 0, 0
            for line in (self.str .. "\n"):gmatch("([^\n]*)\n") do w, n = math.max(w, T.len(line)), n + 1 end
            return w * self.size * 0.5, n * self.size
        end
    end)
    package.loaded["widgets/nineslice"] = Class(function(self, atlas)
        for k, v in pairs(widget("nineslice")) do if self[k] == nil then self[k] = v end end
        self.atlas = atlas
        function self:SetTint(...) self.tint = {...} end
        function self:SetSize(w, h) self.w, self.h = w, h end
    end)
    package.loaded["widgets/image"] = Class(function(self, atlas, tex)
        for k, v in pairs(widget("image")) do if self[k] == nil then self[k] = v end end
        self.atlas, self.tex = atlas, tex
        function self:SetTint(...) self.tint = {...} end
    end)
    ANCHOR_MIDDLE, ANCHOR_BOTTOM, DEFAULTFONT = 0, 4, "opensans"
    SCALEMODE_PROPORTIONAL, MAX_HUD_SCALE, RESOLUTION_X, RESOLUTION_Y = 1, 1.25, 1280, 720
    TheFrontEnd = {GetHUDScale = function() return 1 end}
    TheSim.GetScreenPos = function(_, x, y, z) return 960 + x * 30, 540 - z * 30 end
    package.loaded["widgets/pc_bubbles"] = nil
    local PCBubbles = require "widgets/pc_bubbles"
    CL.init()
    CL.onState(8, 16, "", "", "", "", true)
    K.talking = {}
    Settings.bubbles, Settings.textSize = true, 1
    ana.x, bob.x = 10, 40
    CL.onLine("KU_ana", "Ana", "hello", "s", 100, 10, 0, false)
    CL.onLine("KU_bob", "Bob", "you are off the screen", "s", 101, 40, 0, false)
    local long = {}
    for i = 1, 40 do long[i] = "word" .. i end
    CL.onLine("KU_me", "Me", table.concat(long, " "), "s", 102, 0, 0, false)
    local view = PCBubbles(me, CL, K)
    view:OnUpdate(0.03)
    local ana_w, bob_w, me_w = view.pool["KU_ana:cur"], view.pool["KU_bob:cur"], view.pool["KU_me:cur"]
    check(ana_w and ana_w.text.str == "hello", "a bubble over Ana")
    check(ana_w and math.abs(ana_w.x - (960 + 300)) < 1, "over her head (her screen position)")
    check(bob_w and bob_w.x < 1920 and bob_w.x > 1500, "Bob off screen: docked on the right edge")
    check(bob_w and bob_w.name.shown and bob_w.name.str == "Bob:", "a docked bubble names its speaker")
    local function tail(w)
        local side
        for k, t in pairs(w.tails) do if t.shown then check(side == nil, "one tail at a time") side = k end end
        return side, side and w.tails[side]
    end
    check(bob_w and bob_w.box.shown and tail(bob_w) == "right", "Bob off the right of the screen: his bubble's tail points right")
    check(select(2, tail(bob_w)).x > bob_w.box.w * 0.5, "outside the box's right edge")
    local lowW, highW = me_w, ana_w
    if ana_w.y < me_w.y then lowW, highW = ana_w, me_w end
    local side, t = tail(lowW)
    check(side == "bottom" and math.abs(t.x) < 1, "a bubble over a head: the tail under its middle")
    -- (the tip on the head: the bubble's centre, minus the box's half and the whole tail, in screen pixels)
    local k = 1.25   -- (the bubbles' scale on this 1920 x 1080 screen)
    check(math.abs((lowW.y + k * (t.y - 6)) - 540) < 1.5, "the tail's tip on the speaker's head")
    side, t = tail(highW)
    check(side == "bottom", "a bubble raised above another: its tail still points down at its speaker")
    check(bob_w and bob_w.text.str:find(T.GARBLE, 1, true), "and is garbled (Bob is in the buffer)")
    -- (colours as in the history: Speak white, garbled grey, Yell orange; a docked name in the player's colour)
    check(ana_w.text.colour[1] == 1 and ana_w.text.colour[2] == 1 and ana_w.text.colour[3] == 1, "Speak: white")
    check(bob_w.text.colour[1] == CL.FAR_COLOUR[1] and bob_w.text.colour[3] == CL.FAR_COLOUR[3], "garbled: the history's grey")
    check(bob_w.name.colour[2] == 1 and bob_w.name.colour[1] == 0, "the docked name: Bob's own colour (green)")
    CL.onLine("KU_ana", "Ana", "over here", "y", 110, 10, 0, false)
    view:OnUpdate(0.03)
    local yc = view.pool["KU_ana:cur"].text.colour
    check(yc[1] == CL.YELL_COLOUR[1] and yc[2] == CL.YELL_COLOUR[2] and yc[3] == CL.YELL_COLOUR[3], "Yell: orange, as in the history")
    local n = 0
    for _ in me_w.text.str:gmatch("\n") do n = n + 1 end
    eq(n, 2, "a long line: three lines show")
    local b = CL.bubbles.KU_me.cur
    check(b.extra and b.extra > 0, "a long line stays up longer (its scroll)")
    local first = me_w.text.str:match("^[^\n]+")
    advance(1.5 + 1.8 * 2 + 0.1)
    view:OnUpdate(0.03)
    check(view.pool["KU_me:cur"].text.str:match("^[^\n]+") ~= first, "then it scrolls")
    -- two bubbles in one place: the higher one moves up
    cid.x, cid.z = 10.5, 0
    CL.onLine("KU_ana", "Ana", "hello again", "s", 104, 10, 0, false)
    CL.onLine("KU_cid", "Cid", "same spot", "s", 103, 10.5, 0, false)
    view:OnUpdate(0.03)
    local a2, c2 = view.pool["KU_ana:cur"], view.pool["KU_cid:cur"]
    check(a2 and c2 and math.abs(a2.y - c2.y) >= 20, "overlapping bubbles are stacked")
    -- (the user, 2026-11-05: bubbles "fighting for placement and flickering rapidly" - two speakers at one height,
    --  their heads bobbing: the stack must keep its order)
    local function higher() return view.pool["KU_ana:cur"].y > view.pool["KU_cid:cur"].y and "ana" or "cid" end
    local h0, flips = higher(), 0
    for i = 1, 10 do
        ana.z, cid.z = (i % 2 == 0) and 0.1 or -0.1, (i % 2 == 0) and -0.1 or 0.1
        view:OnUpdate(0.03)
        if higher() ~= h0 then flips = flips + 1 end
    end
    eq(flips, 0, "two heads bobbing at one height: the stack keeps its order (no flicker)")
    ana.z, cid.z = (h0 == "ana") and 3 or -3, 0
    view:OnUpdate(0.03)
    check(higher() == "cid" or h0 == "cid", "one really lower than the other: re-stacked by height")
    ana.z, cid.z = 0, 0
    -- (the user, 2026-11-18: a player's two bubbles over the head "keep swapping places constantly" while walking: the
    --  older line's sort height was up to STICK stale, the newer one's fresh - they crossed it on different frames)
    do
        local az, cz = ana.z, cid.z
        cid.z = 12                                      -- (Cid out of the way)
        CL.bubbles.KU_ana = nil                         -- (her bubbles before: gone)
        view:OnUpdate(0.03)
        CL.onLine("KU_ana", "Ana", "the first thing I said, long enough to wrap over two or three lines in its bubble", "s", 130, 10, 0, false)
        view:OnUpdate(0.03)
        ana.z = -0.8                                    -- (24 px up: under STICK, her sort height left behind)
        view:OnUpdate(0.03)
        CL.onLine("KU_ana", "Ana", "and then this, which is also a long line, so the two bubbles are tall ones", "s", 131, 10, -0.8, false)
        for _ = 1, 10 do view:OnUpdate(0.03) end
        local function order()
            local c, p = view.pool["KU_ana:cur"], view.pool["KU_ana:prev"]
            return c and p and (c.y < p.y and "new below" or "new above")
        end
        eq(order(), "new below", "a speaker's two bubbles: the newest nearest the head, the one before above it")
        local swaps, last = 0, order()
        for i = 1, 60 do                                -- (walking down the screen, bobbing)
            ana.z = -0.8 + i * 0.1 + ((i % 2 == 0) and 0.1 or -0.1)
            view:OnUpdate(0.03)
            local o = order()
            if o ~= last then swaps = swaps + 1 end
            last = o
        end
        eq(swaps, 0, "walking with two bubbles: they never swap")
        local topSwaps = 0
        for i = 1, 40 do                                -- (near the screen's top, bobbing: at most one change)
            ana.z = -13.5 + ((i % 2 == 0) and 0.15 or -0.15)
            view:OnUpdate(0.03)
            local o = order()
            if o ~= last then topSwaps = topSwaps + 1 end
            last = o
        end
        check(topSwaps <= 1, "near the screen's top, bobbing: they change places once at most (" .. topSwaps .. ")")
        CL.bubbles.KU_ana = nil
        view:OnUpdate(0.03)
        ana.z, cid.z = az, cz
    end
    -- (the user, 2026-11-16: two bubbles docked on the screen's edge, one speaker walking past the other - they
    --  "keep flickering and rapidly switching places": they must glide, and change places once at most)
    do
        -- (heard - this player stands near them - but off the screen's right edge: the screen is fixed here)
        local ax, az, cx, cz, mx = ana.x, ana.z, cid.x, cid.z, me.x
        me.x, ana.x, cid.x, ana.z, cid.z = 90, 110, 110, -8, 0
        CL.onLine("KU_ana", "Ana", "over here by the river", "y", 120, 110, -8, false)
        CL.onLine("KU_cid", "Cid", "and me, by the rocks", "y", 121, 110, 0, false)
        for _ = 1, 20 do view:OnUpdate(0.03) end
        local function ys() return view.pool["KU_ana:cur"].y, view.pool["KU_cid:cur"].y end
        -- (a bubble's offset from where its speaker puts it: what glides; the speaker's own steps it follows at once)
        local function offs() return view.lay["KU_ana:cur"].dy, view.lay["KU_cid:cur"].dy end
        local pa, pc = ys()
        local oa, oc = offs()
        local jump, glide, swaps, order, targets = 0, 0, 0, pa > pc, 0
        local lastT = view.lay["KU_ana:cur"].oy
        for i = 1, 80 do
            ana.z = -8 + 16 * i / 80 + 0.15 * ((i % 2 == 0) and 1 or -1)    -- (walking past Cid, bobbing)
            view:OnUpdate(0.03)
            local ya, yc = ys()
            local na, nc = offs()
            jump = math.max(jump, math.abs(ya - pa), math.abs(yc - pc))
            glide = math.max(glide, math.abs(na - oa), math.abs(nc - oc))
            if (ya > yc) ~= order then swaps, order = swaps + 1, ya > yc end
            local tNow = view.lay["KU_ana:cur"].oy
            if math.abs(tNow - lastT) > 60 then targets = targets + 1 end
            pa, pc, oa, oc, lastT = ya, yc, na, nc, tNow
        end
        check(view.pool["KU_ana:cur"].x > 1500 and view.pool["KU_cid:cur"].x > 1500, "(both docked on the right edge)")
        check(glide <= 1100 * 0.03 + 0.5, "docked bubbles glide to their places: at most 33 px a frame (" .. math.floor(glide) .. ")")
        check(jump < 60, "and never jump: under 60 px a frame with the speaker's own steps (" .. math.floor(jump) .. ")")
        check(targets <= 1 and swaps <= 1,
            "one walking past the other: they change places once at most (" .. swaps .. ", " .. targets .. " new places)")
        ana.x, ana.z, cid.x, cid.z, me.x = ax, az, cx, cz, mx
        for _ = 1, 20 do view:OnUpdate(0.03) end
    end
    -- (a crowded screen: speakers off every side and corner, two lines each, round the game's HUD - no bubble over
    --  another or behind the HUD; seen in game 2026-11-16: Wickerbottom's over Wendy's at the top left)
    do
        local ranges = CL.ranges
        CL.ranges = C.ranges(30, 64)
        local hud = {{50, 940, 180, 1080}, {0, 150, 90, 880}, {1760, 780, 1920, 1080}, {340, 0, 1580, 95},
            {1790, 0, 1920, 115}}
        local spots = {{110, 0}, {-110, 0}, {0, -60}, {0, 60}, {-110, -60}, {110, -60}, {-110, 60}, {110, 60}}
        local lid = 900
        for round = 1, 2 do
            for i, s in ipairs(spots) do
                lid = lid + 1
                CL.onLine("KU_crowd" .. i, "Speaker " .. i, "line " .. round .. ", read me", "y", lid, s[1], s[2], false)
            end
            for _ = 1, 60 do                                  -- (time to glide to their places)
                view.hudAt, view.hudRects = 1e12, hud
                view:OnUpdate(0.03)
            end
        end
        local boxes = {}
        for key, w in pairs(view.pool) do
            if key:find("^KU_crowd") and w.shown ~= false and w.place then boxes[#boxes + 1] = {key = key, p = w.place} end
        end
        local function over(a, b2)
            return math.abs(a[1] - b2[1]) < (a[3] + b2[3]) * 0.5 - 1 and math.abs(a[2] - b2[2]) < (a[4] + b2[4]) * 0.5 - 1
        end
        local bad, behind = {}, {}
        for i = 1, #boxes do
            for j = i + 1, #boxes do
                if over(boxes[i].p, boxes[j].p) then bad[#bad + 1] = boxes[i].key .. "/" .. boxes[j].key end
            end
            for _, r in ipairs(hud) do
                local hb = {(r[1] + r[3]) * 0.5, (r[2] + r[4]) * 0.5, r[3] - r[1], r[4] - r[2]}
                if over(boxes[i].p, hb) then behind[#behind + 1] = boxes[i].key end
            end
        end
        eq(#boxes, 16, "a crowded screen: sixteen bubbles shown")
        check(#bad == 0, "no bubble over another (" .. table.concat(bad, ", ") .. ")")
        check(#behind == 0, "none behind the HUD (" .. table.concat(behind, ", ") .. ")")
        local tbad = 0
        for i = 1, #boxes do for j = i + 1, #boxes do
            local a, c = view.pool[boxes[i].key].target, view.pool[boxes[j].key].target
            if over(a, c) then tbad = tbad + 1 end
        end end
        eq(tbad, 0, "(their places as chosen: none over another)")
        -- (more than the screen holds - long lines: they overlap, but spread out, not piled in one place)
        for i, s in ipairs(spots) do
            lid = lid + 1
            CL.onLine("KU_crowd" .. i, "Speaker " .. i, "a much longer line this time, two lines of words in a bubble - can you still read it?",
                "y", lid, s[1], s[2], false)
        end
        for _ = 1, 40 do
            view.hudAt, view.hudRects = 1e12, hud
            view:OnUpdate(0.03)
        end
        local same = 0
        local seen = {}
        for key, w in pairs(view.pool) do
            if key:find("^KU_crowd") and w.target then
                local k2 = math.floor(w.target[1] / 8) .. ":" .. math.floor(w.target[2] / 8)
                if seen[k2] then same = same + 1 end
                seen[k2] = true
            end
        end
        eq(same, 0, "too many for the screen: spread out, none piled on another's place")
        CL.ranges = ranges
        for i = 1, #spots do CL.bubbles["KU_crowd" .. i] = nil end
        view:OnUpdate(0.03)
    end
    local low, high = a2, c2
    if a2.y > c2.y then low, high = c2, a2 end
    check(low.box.shown and high.box.shown and low.box.tint[4] == 0.6, "Clear: each bubble on a see-through box (60 %)")
    check(low.text.font == "pc_pangolin", "Clear: Pangolin")
    Settings.bubbleOpacity = 0.3
    view:OnUpdate(0.03)
    check(view.pool["KU_ana:cur"].box.tint[4] == 0.3 and select(2, tail(view.pool["KU_ana:cur"])).tint[4] == 0.3,
        "the box's opacity is the setting's, its tail's too")
    Settings.bubbleOpacity = 0
    view:OnUpdate(0.03)
    check(not view.pool["KU_ana:cur"].box.shown and tail(view.pool["KU_ana:cur"]) == nil, "0 %: no box, no tail")
    Settings.bubbleOpacity = 0.6
    -- the tail follows its speaker, every frame: Cid near the screen's left edge (his bubble held in on screen)
    cid.x = -30
    view:OnUpdate(0.03)
    local s1, t1 = tail(view.pool["KU_cid:cur"])
    local x1 = t1 and t1.x
    cid.x = -29
    view:OnUpdate(0.03)
    local s2, t2 = tail(view.pool["KU_cid:cur"])
    check(s1 == "bottom" and s2 == "bottom" and x1 < 0 and t2.x > x1, "a bubble held in at the edge: its tail slides toward its speaker as he moves")
    check(low.box.w > 0 and low.box.h > 0, "the box fits the words")
    Settings.bubbleStyle = "game"
    view:OnUpdate(0.03)
    check(not view.pool["KU_ana:cur"].box.shown and view.pool["KU_ana:cur"].text.font == TALKINGFONT,
        "the game's style: no box, its hand-drawn letters")
    Settings.bubbleStyle = "clear"
    view:OnUpdate(0.03)
    check(view.pool["KU_ana:cur"].box.shown and view.pool["KU_ana:cur"].text.font == "pc_pangolin", "and back")
    cid.x, cid.z = 60, 0
    -- gone after their time
    advance(30)
    view:OnUpdate(0.03)
    check(view.pool["KU_ana:cur"] == nil and ana_w.killed, "a bubble goes when its time is up")
    -- "♪" for a voice heard without words
    K.talking = {KU_ana = true}
    view:OnUpdate(0.03)
    check(view.pool["KU_ana:talk"] and view.pool["KU_ana:talk"].text.str == "♪", "a voice heard: ♪")
    K.talking = {}
    -- a translated line: the translation at full size, the original over it smaller
    CL.onLine("KU_ana", "Ana", "hola amigos", "s", 4343, 10, 0, false)
    CL.translated("KU_ana", "Ana", "hello friends", CL.bubbles.KU_ana.cur)
    view:OnUpdate(0.03)
    local tw = view.pool["KU_ana:cur"]
    check(tw and tw.tr.shown and tw.tr.str == "hello friends" and tw.tr.size > tw.text.size,
        "translated: the translation bigger than the original")
    check(math.abs(tw.tr.size - 28) < 0.01 and math.abs(tw.text.size - 28 * 0.6) < 0.01, "(full size, and 60 %)")
    -- the talk key + Tab: the next mode, and DST's player list shut (its release too); Tab alone is DST's
    CL.setMode("s")
    K.talkKey = true
    check(CL.talkTab(true) and CL.mode == "y", "talk key + Tab: the next mode")
    check(CL.talkTab(false), "and its release is kept from DST too")
    CL.talkTab(true) CL.talkTab(false)
    eq(CL.mode, "g", "again: Global")
    CL.talkTab(true) CL.talkTab(false)
    eq(CL.mode, "w", "and round to Whisper")
    K.talkKey = false
    check(not CL.talkTab(true) and not CL.talkTab(false) and CL.mode == "w", "Tab alone: DST's (the player list)")
    -- the strip: shown while the key is held, the mode lit; it slides on a switch, and fades after
    UIFONT = "bp50"
    package.loaded["widgets/pc_talkstrip"] = nil
    local strip = require("widgets/pc_talkstrip")(CL, K)
    strip:OnUpdate(0.03)
    check(not strip.shown, "the strip: hidden while the talk key is up")
    K.talkKey = true
    strip:OnUpdate(0.03)
    check(strip.shown, "shown while it is held")
    local wl = strip.labels[1]
    check(wl.str == require("proxcomms/strings").L("WHISPER") and wl.colour[1] == 1 and wl.colour[2] == 1 and wl.colour[3] == 1, "the current mode (Whisper) lit")
    check(strip.labels[2].colour[4] < 1, "the others dimmed")
    check(strip.hint.str:find("Tab", 1, true) and strip.hint.str:find("V", 1, true), "the hint: V + Tab")
    local x1 = strip.light.x
    CL.talkTab(true) CL.talkTab(false)
    strip:OnUpdate(0.03)                                   -- (the frame of the switch)
    advance(0.1)
    strip:OnUpdate(0.03)
    check(strip.light.x > x1 and strip.light.x < strip:cellX(2), "a switch: the light slides toward Speak")
    advance(0.5)
    strip:OnUpdate(0.03)
    check(math.abs(strip.light.x - strip:cellX(2)) < 0.01 and strip.labels[2].colour[1] == 1, "and settles on it, lit")
    K.talkKey = false
    strip:OnUpdate(0.03)
    check(strip.shown, "let go: still there a moment (fading)")
    advance(0.5)
    strip:OnUpdate(0.03)
    check(not strip.shown, "then gone")
    CL.setMode("s")
end

-- ============================================================================ the settings screen (mocked templates)
do
    local Widget = package.loaded["widgets/widget"]
    package.loaded["widgets/screen"] = Class(Widget, function(self, name) Widget._ctor(self, name) end)
    local made = {}
    local function focusable(w)
        function w:SetFocusChangeDir(dir, to) self.dirs = self.dirs or {} self.dirs[dir] = to end
        function w:SetFocus() self.focused = true end
        return w
    end
    package.loaded["widgets/redux/templates"] = {
        BackgroundTint = function() return Widget("tint") end,
        RectangleWindow = function() return Widget("window") end,
        StandardButton = function(fn, text)
            local b = focusable(Widget("button"))
            b.onclick, b.label = fn, text
            function b:Disable() self.disabled = true end
            made[#made + 1] = b
            return b
        end,
        LabelSpinner = function(label, data, a, b2, c, d, e, f, g, changed)
            local w = focusable(Widget("labelspinner"))
            w.label, w.data, w.changed = label, data, changed
            w.spinner = {SetSelected = function(_, v) w.selected = v end}
            made[#made + 1] = w
            return w
        end,
    }
    package.loaded["screens/pc_settingsscreen"] = nil
    local Text = package.loaded["widgets/text"]
    Text._ctor_orig = Text._ctor
    CHATFONT, UICOLOURS = "chat", {GOLD = {1, 1, 1, 1}, WHITE = {1, 1, 1, 1}}
    MOVE_UP, MOVE_DOWN, MOVE_LEFT, MOVE_RIGHT = 1, 2, 3, 4
    ANCHOR_MIDDLE, ANCHOR_RIGHT = 0, 2
    function VisitURL(u) VISITED = u end
    TheInput.ControllerAttached = function() return true end
    local Screen = require "screens/pc_settingsscreen"
    -- (a Text with region and wrap calls)
    local oldText = package.loaded["widgets/text"]
    local TextCls = Class(function(self, font, size, str)
        oldText._ctor(self, font, size, str)
        function self:SetRegionSize() end function self:EnableWordWrap() end function self:SetHAlign() end
    end)
    package.loaded["widgets/text"] = TextCls
    package.loaded["screens/pc_settingsscreen"] = nil
    Screen = require "screens/pc_settingsscreen"
    K.online = false
    for page = 1, 4 do
        made = {}
        local ok, scr = pcall(Screen, CL, K, page)
        check(ok, "settings page " .. page .. " builds: " .. tostring(ok or scr))
        if ok then
            check(scr.default_focus ~= nil, "page " .. page .. ": a controller has a first row")
            check(scr.close.dirs and scr.close.dirs[MOVE_UP] ~= nil, "page " .. page .. ": Close is reachable")
        end
    end
    -- the Players page: every other player's volume (0-150 %), a Reset each, the muted marked; pages beyond 8
    local L = require("proxcomms/strings").L
    do
        local others = CL.others
        local list = {}
        for i = 1, 10 do list[i] = {uid = "KU_p" .. i, name = "Player" .. string.format("%02d", i)} end
        CL.others = function() local out = {} for i, v in ipairs(list) do out[i] = v end return out end
        Settings.muted.KU_p2 = "Player02"
        made = {}
        local scr = Screen(CL, K, 3)
        local spins, resets, nav = {}, {}, nil
        for _, w in ipairs(made) do
            if w.name == "labelspinner" and type(w.label) == "string" and w.label:find("Player") then spins[#spins + 1] = w end
            if w.name == "button" and w.label == L("RESET") then resets[#resets + 1] = w end
        end
        eq(#spins, 8, "Players: 8 on a page")
        eq(#resets, 8, "each with Reset")
        check(spins[1].label == "Player01" and spins[2].label:find(L("MUTED_TAG"), 1, true), "by name; the muted marked")
        local top = spins[1].data[#spins[1].data].data
        eq(top, 1.5, "up to 150 %")
        spins[1].changed(0.5)
        eq(Settings.volumeOf("KU_p1"), 0.5, "a player's volume set")
        resets[1].onclick()
        check(Settings.volumeOf("KU_p1") == 1 and spins[1].selected == 1, "Reset: 100 % again")
        local nextBtn
        for _, w in ipairs(made) do if w.name == "button" and w.label == ">" then nextBtn = w end end
        check(nextBtn and not nextBtn.disabled, "more than 8: a next page")
        made = {}
        nextBtn.onclick()
        local n = 0
        for _, w in ipairs(made) do if w.name == "labelspinner" and type(w.label) == "string" and w.label:find("Player") then n = n + 1 end end
        eq(n, 2, "the next page: the other 2")
        Settings.muted.KU_p2 = nil
        CL.others = others
    end
    -- the talk key: bound by pressing it; the chat's keys and the game's own keys (on this PC) refused
    KEY_V, KEY_B, KEY_ESCAPE, KEY_ENTER, KEY_F5 = 118, 98, 27, 13, 286
    CONTROL_FAKE_DANCE = 77
    VIRTUAL_CONTROL_START = 10000
    STRINGS.UI.CONTROLSSCREEN = {INPUTS = {[1] = {[118] = "V", [98] = "B", [286] = "F5", [13] = "Enter"}}, CONTROLS = {[78] = "Dance"}}
    TheInputProxy = {GetLocalizedControl = function(_, dev, control)
        if control == CONTROL_FAKE_DANCE then return 1, 1, KEY_B end
        return 1, 1, 0
    end}
    local Keys = require "proxcomms/keys"
    eq(Keys.nameOf(118), "V", "a key's name")
    eq(Keys.label("F5"), "F5", "its label")
    eq(Keys.gameUse(KEY_B), "Dance", "a key the game uses, by its control's name")
    -- (DST's CONTROL_CUSTOM_START - 103 since 2026-10-22 - is no control: the engine asserts, a crash, if asked about it)
    do
        local asked = {}
        local proxy = TheInputProxy.GetLocalizedControl
        TheInputProxy.GetLocalizedControl = function(_, dev, control) asked[control] = true return proxy(_, dev, control) end
        CONTROL_CUSTOM_START, CONTROL_SOME_MOD_CONTROL = 103, 105
        Keys.gameUse(KEY_F5)
        check(not asked[103] and not asked[105], "CONTROL_CUSTOM_START and beyond are never asked of the engine (a crash)")
        TheInputProxy.GetLocalizedControl = proxy
        CONTROL_SOME_MOD_CONTROL = nil
    end
    eq(Keys.refusal("V"), nil, "a free key is fine")
    eq(Keys.refusal("ENTER"), "reserved", "the chat's key is not")
    Settings.talkKey = "V"
    made = {}
    K.online = false
    local ks = Screen(CL, K, 2)
    check(ks.keyRow and ks.keyRow.button, "the Voice page has the talk key's button")
    ks:StartBinding()
    check(ks.binding, "pressing it waits for a key")
    ks:OnRawKey(KEY_B, true)
    eq(Settings.talkKey, "V", "the game's key: refused")
    check(ks.keyNote.str:find("Dance", 1, true), "and says for what")
    ks:StartBinding()
    ks:OnRawKey(KEY_ENTER, true)
    eq(Settings.talkKey, "V", "Enter: refused")
    ks:StartBinding()
    ks:OnRawKey(KEY_F5, false)
    check(ks.binding, "a key's release does nothing")
    ks:OnRawKey(KEY_F5, true)
    check(Settings.talkKey == "F5" and not ks.binding, "a free key: the new talk key")
    ks:StartBinding()
    ks:OnRawKey(KEY_ESCAPE, true)
    eq(Settings.talkKey, "F5", "Esc keeps it")
    check(ks:OnControl(CONTROL_CANCEL, false) == true and not ks.closedByCancel, "and Esc's release does not close the screen")
    Settings.talkKey = "V"
    -- the Voice page's rows change the settings
    made = {}
    K.online = true
    K.version, K.speech, K.mic, K.voiceState = "0.5.5", "ready", "open", "connected"
    eq(K.maxBody(), K.MAX_BODY, "Koetama 0.5.5: feeds up to 64 KB")
    K.version = "0.5.17"
    eq(K.maxBody(), K.MAX_BODY_BIG, "Koetama 0.5.17: feeds up to 256 KB")
    K.version = ""
    eq(K.maxBody(), K.MAX_BODY, "no hello yet: 64 KB")
    K.version = "0.5.5"
    -- (the user, 2026-11-19: users told whether their Koetama is up to date: C.KOETAMA_LATEST, or a newer "latest" in
    --  Koetama's hello - in the chat when it connects, /pc koetama and the settings)
    do
        local v0, o0, l0 = K.version, K.outdated, K.latestSaid
        K.outdated, K.latestSaid = false, ""
        K.version = C.KOETAMA_LATEST
        eq(K.updateLine(), Strings.L("K_UPTODATE", C.KOETAMA_LATEST), "Koetama as new as this mod knows: up to date")
        K.version = "0.5.6"
        eq(K.updateLine(), Strings.L("K_UPDATE", C.KOETAMA_LATEST, "0.5.6"), "an older one: the version to update to")
        K.version, K.latestSaid = C.KOETAMA_LATEST, "9.0.0"
        eq(K.updateLine(), Strings.L("K_UPDATE", "9.0.0", C.KOETAMA_LATEST), "a newer one Koetama's hello names counts")
        K.latestSaid = "0.0.1"
        eq(K.updateLine(), Strings.L("K_UPTODATE", C.KOETAMA_LATEST), "(an older one it names does not)")
        K.version, K.outdated = "0.5.1", true
        eq(K.updateLine(), Strings.L("K_OLD", "0.5.1"), "under the minimum: the stronger warning")
        K.version, K.outdated, K.latestSaid = "0.5.6", false, ""
        local found = false
        for _, line in ipairs(K.statusLines()) do if line == Strings.L("K_UPDATE", C.KOETAMA_LATEST, "0.5.6") then found = true end end
        check(found, "/pc koetama says it too")
        K.version, K.outdated, K.latestSaid = v0, o0, l0
    end
    local scr = Screen(CL, K, 2)
    local mic
    for _, w in ipairs(made) do if w.label == Strings.L("ROW_MIC") then mic = w end end
    check(mic and mic.selected == Settings.mic, "the microphone row shows the setting")
    mic.changed("always")
    eq(Settings.mic, "always", "and changes it")
    Settings.mic = "auto"
    K.into, K.pairs, K.pairKeys = "en", {["es>en"] = {from = "es", to = "en", state = "downloading", progress = 0.42}}, {"es>en"}
    local ok3 = pcall(Screen, CL, K, 3)
    check(ok3, "the Translate page with a pair downloading")
    TheInput.ControllerAttached = function() return controller end
end

-- (a model's [bracketed] asides are not said - the user, 2026-11-06)
do
    local A_ = require "proxcomms/agents"
    eq(A_.noAsides("[Gilbert is a friend, not me] Blub! Gilbert won't hurt me."), "Blub! Gilbert won't hurt me.",
        "agents: a bracketed aside is not said")
    eq(A_.noAsides("Hrrm, yes [thinking] friend [still"), "Hrrm, yes friend", "agents: live words: an open bracket cut")
    eq(A_.noAsides("No brackets here."), "No brackets here.", "agents: words without brackets as they are")
    eq(A_.noAsides("[only an aside]"), "", "agents: only an aside - nothing to say")
end

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
