-- The client half (every player's game): what this player hears of each line, and when.
--
-- Speak and Yell lines come from the server (only to players in reach). Each is heard by the distance to its speaker:
-- within the mode's words range in full, in its buffer garbled (⬚ for the letters not made out, more of them the
-- closer), beyond it not at all - and a bubble that is up is revealed as the listener walks in. A spoken line
-- (Koetama) carries each word's time: only the words said while this player was in reach are shown ("... the rest"),
-- each as clearly as it was heard then, and it stays so. Whisper and Global are DST's own chat; their bubbles are
-- drawn here too (scrolling, docked to the screen edge), unchanged.
--
-- The history is DST's own chat (ChatHistory), per player by nature: a line goes in when this player heard it, as
-- they heard it, marked [S] / [Y] (and "(far)" when garbled). Lines are local only (never sent to joiners).
local T = require "proxcomms/text"
local C = require "proxcomms/config"
local Settings = require "proxcomms/settings"
local Strings = require "proxcomms/strings"
local L = Strings.L

local CL = {
    mode = "s",
    ranges = C.ranges(C.SPEAK_TILES, C.YELL_TILES, C.WHISPER_TILES),
    gotState = false, helloAt = 0,
    room = nil, key = nil, region = "", voiceOn = true,
    global = {},              -- userid -> true: their voice is in Global
    vmodeSent = nil, vmodeAt = 0,
    bubbles = {},             -- userid -> {cur = b, prev = b}
    live = {},                -- userid -> {utt, text, mode, t, x, z, name}
    samples = {},             -- userid -> {t = {}, d = {}}: the distance to them, every 0.1 s (the last 40 s)
    sampleAt = -1,
    clients = {}, clientsAt = -1,   -- userid -> DST's client table entry (names, colours, admin, muted)
    recall = {}, recallAt = 0,      -- the last lines this player sent (Up / Down on the chat line)
    K = nil,                  -- the Koetama link (modmain sets it)
    D = nil,                  -- the test figures (modmain sets it)
}

CL.YELL_COLOUR = {1, 0.62, 0.25, 1}
CL.FAR_COLOUR = {0.62, 0.62, 0.62, 1}
CL.TR_COLOUR = {1, 0.6, 0.78, 1}
CL.WHISPER_COLOUR = {0.6, 0.6, 0.6, 1}
CL.SAY_COLOUR = {1, 1, 1, 1}

-- a MODE's own colour (the chat line's mode button, the wheel's centre, "Chat mode: ..." lines): Whisper grey, Speak
-- white, Yell orange, Global light blue
CL.MODE_COLOUR = {w = {0.6, 0.6, 0.6, 1}, s = {0.95, 0.95, 0.95, 1}, y = {1, 0.62, 0.25, 1}, g = {0.55, 0.8, 1, 1}}

-- a line's colour by its mode - the same in its bubble as in the chat history (the user, 2026-10-13): Speak and Global
-- white, Yell orange, Whisper DST's whisper grey; garbled: the history's "(far)" grey
function CL.modeColour(mode, garbled)
    if garbled then return CL.FAR_COLOUR end
    if mode == "y" then return CL.YELL_COLOUR end
    if mode == "w" then return CL.WHISPER_COLOUR end
    return CL.SAY_COLOUR
end

CL.LIFE_MIN, CL.LIFE_PER_CHAR, CL.LIFE_MAX = 2.5, 0.1, 12
CL.REVEAL_HOLD = 1
CL.LIVE_LIFE = 4
CL.GARBLE_MAX = 0.75          -- the share of letters made out at the inner edge of the buffer
CL.SAMPLE_EVERY, CL.SAMPLE_KEEP = 0.1, 40

-- ---- the game

function CL.now() return GetTime() end

function CL.me()
    return ThePlayer and ThePlayer.userid or nil
end

function CL.refreshClients(force)
    local now = CL.now()
    if not force and now - CL.clientsAt < 1 then return end
    CL.clientsAt = now
    local t = {}
    for _, c in ipairs(TheNet and TheNet:GetClientTable() or {}) do
        if c.userid and c.userid ~= "" then t[c.userid] = c end
    end
    CL.clients = t
end

function CL.client(uid)
    CL.refreshClients()
    return CL.clients[uid]
end

function CL.nameOf(uid, fallback)
    local c = CL.client(uid)
    local n = c and c.name or fallback or "?"
    n = T.clean(n, C.NAME_LEN)
    return n ~= "" and n or "?"
end

function CL.colourOf(uid)
    local c = CL.client(uid)
    local col = c and c.colour
    if type(col) == "table" and #col >= 3 then return {col[1], col[2], col[3], 1} end
    return {1, 1, 1, 1}
end

-- a mime (Wes): DST shows nothing over a mime's head; the mod does, in brackets (the user, 2026-10-16: "no mime rule
-- ... wrap whatever he says in brackets in the speech bubble") - in every mode and his live words; his voice as anyone's
function CL.isMime(uid)
    local e = CL.entity(uid)
    return e ~= nil and type(e.HasTag) == "function" and e:HasTag("mime") == true
end

function CL.mimed(text, uid)
    if type(text) == "string" and text ~= "" and CL.isMime(uid) then return "[" .. text .. "]" end
    return text
end

function CL.entity(uid)
    if ThePlayer and ThePlayer.userid == uid then return ThePlayer end
    for _, p in ipairs(AllPlayers or {}) do
        if p.userid == uid then return p end
    end
    if CL.D then return CL.D.entity(uid) end
    return nil
end

function CL.myPos()
    if not (ThePlayer and ThePlayer.Transform) then return nil end
    local x, _, z = ThePlayer.Transform:GetWorldPosition()
    return x, z
end

-- the distance to a speaker: where they stand now when this game knows them, else where the line was said
function CL.distTo(uid, x, z)
    local mx, mz = CL.myPos()
    if not mx then return nil end
    if uid == CL.me() then return 0 end
    local e = CL.entity(uid)
    if e and e.Transform and (not e.IsValid or e:IsValid()) then
        local ex, _, ez = e.Transform:GetWorldPosition()
        x, z = ex, ez
    end
    if not (x and z) then return nil end
    local dx, dz = x - mx, z - mz
    return math.sqrt(dx * dx + dz * dz)
end

function CL.isMuted(uid)
    if Settings.muted[uid] then return true end
    local c = CL.client(uid)
    return c ~= nil and c.muted == true
end

function CL.filter(text, uid)
    if ApplyLocalWordFilter and TEXT_FILTER_CTX_CHAT then
        local netid = TheNet and TheNet.GetNetIdForUser and TheNet:GetNetIdForUser(uid) or nil
        local ok, out = pcall(ApplyLocalWordFilter, text, TEXT_FILTER_CTX_CHAT, netid)
        if ok and type(out) == "string" then return out end
    end
    return text
end

-- ---- ranges and levels

function CL.rangeOf(mode)
    local r = CL.ranges[mode] or CL.ranges.s
    return r[1], r[2]
end

-- the share of letters made out at distance d (nil beyond the buffer, 1 within the words' range)
function CL.fracAt(d, mode)
    local inner, outer = CL.rangeOf(mode)
    if not d or d > outer then return nil end
    if d <= inner then return 1 end
    return math.max(0, math.min(1, (outer - d) / math.max(0.5, outer - inner))) * CL.GARBLE_MAX
end

function CL.levelAt(d, mode)
    local f = CL.fracAt(d, mode)
    if not f then return nil end
    return f >= 1 and "full" or "mumble"
end

local LEVEL = {none = 0, mumble = 1, full = 2}

-- ---- the distance log (timed words)

function CL.sample(now)
    if now - CL.sampleAt < CL.SAMPLE_EVERY then return end
    CL.sampleAt = now
    local me = CL.me()
    local function put(uid, d)
        local r = CL.samples[uid]
        if not r then r = {t = {}, d = {}} CL.samples[uid] = r end
        r.t[#r.t + 1], r.d[#r.d + 1] = now, d or false
        while #r.t > 1 and now - r.t[1] > CL.SAMPLE_KEEP do table.remove(r.t, 1) table.remove(r.d, 1) end
    end
    for _, p in ipairs(AllPlayers or {}) do
        if p.userid and p.userid ~= me then put(p.userid, CL.distTo(p.userid)) end
    end
    if CL.D then for _, uid in ipairs(CL.D.ids()) do put(uid, CL.distTo(uid)) end end
end

-- the distance to uid at local time t (the nearest sample within 0.35 s), or nil
function CL.distAt(uid, t)
    local r = CL.samples[uid]
    if not (r and #r.t > 0) then return nil end
    local lo, hi = 1, #r.t
    while hi - lo > 1 do
        local mid = math.floor((lo + hi) / 2)
        if r.t[mid] <= t then lo = mid else hi = mid end
    end
    local k = math.abs(r.t[lo] - t) <= math.abs(r.t[hi] - t) and lo or hi
    if t > r.t[#r.t] then
        if t - r.t[#r.t] < 1.5 then k = #r.t else return nil end
    elseif math.abs(r.t[k] - t) > 0.35 then
        return nil
    end
    return r.d[k] or nil
end

-- what this player heard of a timed line: the units said while in reach ("..." for each stretch missed), whether all
-- of it was clear, and the share of each letter made out (T.garble's order). nil: none of it.
function CL.heardTimed(uid, us, times, start, mode)
    local inner, outer = CL.rangeOf(mode)
    local out, fr, gap, any, clear = {}, {}, false, false, true
    local function letters(w, f) for _ in w:gmatch(T.CHAR) do fr[#fr + 1] = f end end
    for i, u in ipairs(us) do
        local d = CL.distAt(uid, start + times[i])
        if d and d <= outer then
            if gap then
                out[#out + 1] = (#out > 0 and " ... " or "... ") .. u.w
                letters("...", 1)
                gap = false
            else
                out[#out + 1] = (#out > 0 and u.s or "") .. u.w
            end
            local f = CL.fracAt(d, mode) or 0
            if f < 1 then clear = false end
            letters(u.w, f)
            any = true
        else
            gap = true
        end
    end
    if not any then return nil end
    if gap then out[#out + 1] = " ..." letters("...", 1) end
    return table.concat(out), clear, fr
end

-- ---- bubbles

function CL.life(b)
    local life = math.min(CL.LIFE_MAX, CL.LIFE_MIN + T.len(b.full) * CL.LIFE_PER_CHAR)
    if b.tr and b.trT then
        life = math.max(life, (b.trT - b.t) + math.min(CL.LIFE_MAX, CL.LIFE_MIN + T.len(b.tr) * CL.LIFE_PER_CHAR))
    end
    return life + (b.extra or 0)    -- (the widget adds the time a long line needs to scroll)
end

-- what a bubble shows now (a mime's in brackets)
function CL.bubbleText(b)
    if b.level == "full" then return CL.mimed(b.full, b.uid) end
    if b.fixed then return CL.mimed(T.garble(b.full, 0, b.seed, b.fracs), b.uid) end
    local f = CL.fracAt(CL.distTo(b.uid, b.x, b.z), b.mode) or 0
    return CL.mimed(T.garble(b.full, math.min(f, CL.GARBLE_MAX), b.seed), b.uid)
end

-- the most of it this player ever made out
function CL.histText(b)
    if b.level == "full" then return b.full end
    if b.fixed then return T.garble(b.full, 0, b.seed, b.fracs) end
    return T.garble(b.full, math.max(0, b.bestF or 0), b.seed)
end

-- shown now: heard (not hidden), the listener within its reach, bubbles on
function CL.visible(b)
    if not Settings.bubbles or b.hidden then return false end
    if b.uid == CL.me() or b.fixed then return true end
    if b.native and b.mode == "g" then return CL.entity(b.uid) ~= nil end   -- (Global: where DST shows it, never docked)
    local _, outer = CL.rangeOf(b.mode)
    local d = CL.distTo(b.uid, b.x, b.z)
    return d ~= nil and d <= outer
end

function CL.put(b)
    local s = CL.bubbles[b.uid]
    if not s then s = {} CL.bubbles[b.uid] = s end
    if s.cur and not s.cur.hidden then s.prev = s.cur end
    s.cur = b
end

-- a bubble not fully heard follows the listener while it is up (revealed walking in)
function CL.update(b, now, fresh)
    if b.fixed or b.native then return end
    local d = CL.distTo(b.uid, b.x, b.z)
    local level = CL.levelAt(d, b.mode)
    if level and LEVEL[level] > LEVEL[b.level] then
        b.level, b.hidden = level, false
        b.bestF = -1
        CL.askTr(b)
        if not fresh and level == "full" then
            b.t = math.max(b.t, now - CL.life(b) + CL.REVEAL_HOLD)
        end
        if level == "full" then CL.heardAll(b) end
    end
    if b.level == "mumble" then
        local f = CL.fracAt(d, b.mode) or 0
        if f > (b.bestF or -1) then b.bestF = math.min(f, CL.GARBLE_MAX) end
    end
end

-- the whole line was made out: in the history (once), and to Koetama for translation
function CL.heardAll(b)
    if not b.hist then
        b.hist = true
        CL.addHistory(b, b.full, false)
    end
    CL.askTr(b)
    if b.tr and not b.trHist then CL.addTrHistory(b, b.tr) end
end

-- ---- translations (Koetama): every line heard, garbled ones too - the translation is garbled by the same share as
-- the original (the user, 2026-10-19: a listener learns as much as a native speaker would, filling in walking closer)

function CL.askTr(b)
    if CL.K and b.uid ~= CL.me() and not b.trAsked then
        b.trAsked = true
        CL.K.want(b.uid, b.orig or b.full, b)
    end
end

-- the share of the line made out: 1 whole; a spoken line's, its letters' as heard; else by the distance now (best:
-- the most ever made out, for the history)
function CL.shareOf(b, best)
    if b.native or b.level == "full" then return 1 end
    if b.fixed then
        local n, sum = 0, 0
        for _, f in ipairs(b.fracs or {}) do n, sum = n + 1, sum + f end
        return n > 0 and sum / n or 0
    end
    if best then return math.max(0, b.bestF or 0) end
    return math.min(CL.fracAt(CL.distTo(b.uid, b.x, b.z), b.mode) or 0, CL.GARBLE_MAX)
end

-- what a bubble shows of its translation now (garbled as the line is), or nil
function CL.trText(b, best)
    if not b.tr then return nil end
    local f = CL.shareOf(b, best)
    if f >= 1 then return b.tr end
    return T.garble(b.tr, f, b.seed + 7)
end

-- the translation's history line (once): under the original's, which goes smaller
function CL.addTrHistory(b, text)
    if not b or b.trHist then return end
    b.trHist = true
    local m = b.histMsg
    if m and type(m.m_colour) == "table" and not m.m_colour.pc_small then
        local c = {}
        for k, v in pairs(m.m_colour) do c[k] = v end
        c.pc_small = true
        m.m_colour = c
    end
    CL.history(ChatTypes and ChatTypes.Message, "→ " .. (b.trName or b.name or "?"), text, CL.TR_COLOUR, CL.TR_COLOUR)
end

-- ---- arriving lines (client RPCs)

-- the server's line: uid, name, text, mode, id, x, z, voice, utt, times, age
function CL.onLine(uid, name, text, mode, id, x, z, voice, utt, times, age)
    if type(uid) ~= "string" or type(text) ~= "string" or not C.validMode(mode) then return end
    -- (Whisper and Global come so only from agents - proxcomms/agents.lua; players' are DST's own chat)
    if (mode == "w" or mode == "g") and uid:sub(1, 6) ~= "agent:" then return end
    if CL.isMuted(uid) then return end
    local now = CL.now()
    local me = CL.me()
    local b = {
        uid = uid, name = T.clean(type(name) == "string" and name or "", C.NAME_LEN), colour = CL.colourOf(uid),
        full = CL.filter(T.clean(text, C.MAX_LEN), uid), mode = mode, id = tonumber(id) or 0, x = tonumber(x), z = tonumber(z),
        t = now, level = "none", hidden = true, bestF = -1, voice = voice == true, caps = T.allCaps(text),
    }
    b.seed = (b.id * 7919) % 1000003
    if b.full == "" then return end
    if CL.live[uid] then CL.live[uid] = nil end         -- (the finished line takes the live words' place)
    if mode == "g" then                                 -- (an agent's Global line: everyone's, whole, in the history)
        b.level, b.hidden = "full", true
        CL.heardAll(b)
        CL.put(b)
        return
    end
    local us, ts = nil, nil
    if b.voice and uid ~= me then
        us = T.units(b.full)
        ts = T.timesOf(times)
        if ts and #ts ~= #us then ts = nil end
    end
    if ts then
        local start = now - math.max(0, tonumber(age) or 0)
        local heard, clear, fracs = CL.heardTimed(uid, us, ts, start, mode)
        if not heard then return end                     -- (none of it said while in reach)
        b.fixed, b.hidden, b.orig, b.full = true, false, b.full, heard
        if clear then
            b.level = "full"
            CL.heardAll(b)
        else
            b.level, b.fracs = "mumble", fracs
            b.hist = true
            CL.addHistory(b, CL.histText(b), true)
            CL.askTr(b)
        end
        CL.put(b)
        return
    end
    CL.update(b, now, true)
    if b.level ~= "none" or uid == me then
        if uid == me then b.level, b.hidden = "full", false CL.heardAll(b) end
        CL.put(b)
    else
        CL.put(b)                                          -- (kept hidden: walking in while it is up shows it)
    end
end

-- live words of a line being spoken ("" = they just started)
function CL.onLive(uid, name, utt, text, mode, x, z)
    if type(uid) ~= "string" or CL.isMuted(uid) then return end
    CL.live[uid] = {utt = utt, text = CL.filter(T.clean(text or "", 200), uid), mode = mode, t = CL.now(),
        x = tonumber(x), z = tonumber(z), name = name, seed = ((tonumber(utt) or 0) * 7919 + #uid) % 1000003}
end

-- what live words show now (garbled by the distance now)
function CL.liveText(l, uid)
    if l.text == "" then return "..." end
    if uid == CL.me() then return CL.mimed(T.tail(l.text, 70), uid) end
    local f = CL.fracAt(CL.distTo(uid, l.x, l.z), l.mode)
    if not f then return nil end
    local txt = T.tail(l.text, 70)
    if f >= 1 then return CL.mimed(txt, uid) end
    return CL.mimed(T.garble(txt, f, l.seed), uid)
end

-- DST's own Say / Whisper (wrapped Networking_Say): a bubble drawn here instead of DST's
function CL.onNative(uid, name, text, colour, whisper)
    if type(uid) ~= "string" or type(text) ~= "string" or text == "" then return end
    if whisper then return CL.onWhisper(uid, name, text, colour) end
    local b = {uid = uid, name = T.clean(name or "", C.NAME_LEN), colour = colour or CL.colourOf(uid),
        full = CL.filter(text, uid), mode = "g", t = CL.now(), level = "full", hidden = false, native = true,
        caps = T.allCaps(text), seed = 0}
    -- (its history line is DST's, made just before this: kept, to shrink once the line is translated)
    if CL.lastHistMsg and CL.lastHistMsg.message == text then b.histMsg = CL.lastHistMsg end
    CL.put(b)
    if CL.K and uid ~= CL.me() then CL.K.want(uid, b.full, b) end
end

-- DST's whisper, in the mod's Whisper range as a Speak line is in Speak's: clear within it, garbled in its buffer
-- (revealed walking in while it is up), nothing beyond. Its history line is the mod's too (modmain keeps DST's out:
-- DST would show the whole line to anyone within 40 units).
function CL.onWhisper(uid, name, text, colour)
    if CL.isMuted(uid) then return end
    local now = CL.now()
    local x, z
    local e = CL.entity(uid)
    if e and e.Transform then
        local ex, _, ez = e.Transform:GetWorldPosition()
        x, z = ex, ez
    end
    CL.whisperId = (CL.whisperId or 0) + 1
    local b = {uid = uid, name = T.clean(name or "", C.NAME_LEN), colour = colour or CL.colourOf(uid),
        full = CL.filter(T.clean(text, C.MAX_LEN), uid), mode = "w", x = x, z = z, t = now, level = "none",
        hidden = true, bestF = -1, caps = T.allCaps(text)}
    b.seed = (CL.whisperId * 7919 + #uid) % 1000003
    if b.full == "" then return end
    if uid == CL.me() then
        b.level, b.hidden = "full", false
        CL.heardAll(b)
    else
        CL.update(b, now, true)
    end
    CL.put(b)                                              -- (beyond its reach: kept hidden, shown walking in)
end

-- a translation came for a line: under it in the history, and in its bubble
function CL.translated(uid, name, text, b)
    text = CL.filter(T.clean(text, 300), uid)
    if text == "" then return end
    if not b then
        CL.history(ChatTypes and ChatTypes.Message, "→ " .. (name or "?"), text, CL.TR_COLOUR, CL.TR_COLOUR)
        return
    end
    b.tr, b.trT, b.trName = text, CL.now(), name
    -- (in the history once the line is: now if it was made out whole - else when it is, or garbled as made out when
    --  its bubble ends, CL.tick)
    if b.native or (b.hist and b.level == "full") then CL.addTrHistory(b, text) end
end

-- ---- history (DST's chat)

CL.histColour = nil   -- (modmain's GenerateChatMessage wrapper reads it: the message's own colour)
CL.lastHistMsg = nil  -- (and sets this: the message it made last)
CL.HIST_SIZE = 30     -- DST's chat rows' text size (widgets/redux/chatline.lua)
CL.HIST_ORIGINAL = 0.6    -- a translated line's original in the history, against its translation

function CL.history(kind, sender, text, nameColour, msgColour, uid)
    if not (ChatHistory and ChatTypes) then return end
    CL.histColour = msgColour
    local netid = uid and TheNet and TheNet.GetNetIdForUser and TheNet:GetNetIdForUser(uid) or nil
    local ok = pcall(ChatHistory.AddToHistory, ChatHistory, kind or ChatTypes.Message, uid, netid, sender, text,
        {nameColour[1], nameColour[2], nameColour[3], nameColour[4] or 1}, "default", false, true, nil)
    CL.histColour = nil
    return ok, ok and CL.lastHistMsg or nil
end

function CL.addHistory(b, text, far)
    local tag = b.mode == "y" and L("TAG_YELL") or (b.mode == "w" and L("TAG_WHISPER") or L("TAG_SPEAK"))
    local name = tag .. " " .. b.name .. (far and (" " .. L("TAG_HEARD")) or "")
    local msg = far and CL.FAR_COLOUR or (b.mode == "y" and CL.YELL_COLOUR
        or (b.mode == "w" and CL.MODE_COLOUR.w or CL.SAY_COLOUR))
    local _, m = CL.history(ChatTypes and ChatTypes.Message, name, text, b.colour, msg, b.uid)
    b.histMsg = m
end

-- a line only this player sees
function CL.system(text, colour)
    if colour and ChatHistory and ChatTypes then
        pcall(ChatHistory.AddToHistory, ChatHistory, ChatTypes.CommandResponse, nil, nil, nil, text, colour, nil, nil, true)
    elseif ChatHistory and ChatHistory.SendCommandResponse then
        ChatHistory:SendCommandResponse(text)
    end
    if CL.onSystem then CL.onSystem(text) end   -- (tests)
end

-- "Chat mode: Yell", in the mode's colour
function CL.modeLine()
    return L("MODE_NOW", L(C.MODE_KEY[CL.mode])), CL.MODE_COLOUR[CL.mode]
end

-- ---- every frame (the HUD's update)

function CL.tick(dt)
    local now = CL.now()
    if not ThePlayer then return end
    if not CL.gotState and now >= CL.helloAt then
        CL.helloAt = now + 3
        CL.rpc("hello")
    end
    if CL.gotState and (CL.vmodeSent ~= CL.mode) and now >= CL.vmodeAt then
        CL.vmodeAt = now + 2
        CL.rpc("vmode", CL.mode)
        CL.vmodeSent = CL.mode
    end
    CL.sample(now)
    for uid, s in pairs(CL.bubbles) do
        for _, k in ipairs({"cur", "prev"}) do
            local b = s[k]
            if b then
                if now > b.t + CL.life(b) then
                    if b.level == "mumble" and not b.hist then   -- (garbled to the end: in the history as made out)
                        b.hist = true
                        CL.addHistory(b, CL.histText(b), true)
                    end
                    if b.tr and not b.trHist and b.hist then CL.addTrHistory(b, CL.trText(b, true)) end
                    s[k] = nil
                elseif b.level ~= "full" then
                    CL.update(b, now, false)
                end
            end
        end
        if not s.cur and not s.prev then CL.bubbles[uid] = nil end
    end
    for uid, l in pairs(CL.live) do
        if now - l.t > CL.LIVE_LIFE then CL.live[uid] = nil end
    end
    if CL.K then CL.K.tick() end
    if CL.D then CL.D.tick(now) end
end

-- ---- sending

function CL.rpc(name, ...)
    if not (SendModRPCToServer and GetModRPC) then return end
    pcall(SendModRPCToServer, GetModRPC(C.NAMESPACE, name), ...)
end

function CL.setMode(m, quiet)
    if not C.validMode(m) then return end
    CL.mode = m
    Settings.mode = m
    Settings.save()
    if not quiet then CL.vmodeAt = 0 end
end

-- Tab while the talk key is held (pc_talkstrip shows it): the next mode - the chat's and the voice's - and not DST's
-- player list (the user, 2026-10-16, as in the Teardown mod). true: Tab was this, keep it from DST (its release too).
function CL.talkTab(down)
    if down then
        if not (CL.K and CL.K.talkKey) then return false end
        CL.tabTaken = true
        CL.setMode(C.nextMode(CL.mode))
        return true
    end
    if CL.tabTaken then
        CL.tabTaken = nil
        return true
    end
    return false
end

-- say a line as this player in a mode. voice (Koetama): {utt, times = {...}, ago}. A spoken line longer than a chat
-- line goes in pieces (DST's chat takes 150 characters).
function CL.say(text, mode, voice)
    text = T.clean(text, voice and 2000 or C.MAX_LEN)
    if text == "" then return false end
    mode = C.validMode(mode) and mode or CL.mode
    if voice then
        local us = T.units(text)
        local times = voice.times
        if not (times and #times == #us) then times = nil end
        local a = 1
        while a <= #us do
            local b = a
            while b < #us and T.len(T.join(us, a, b + 1)) <= C.MAX_LEN do b = b + 1 end
            local piece = T.head(T.join(us, a, b), C.MAX_LEN)
            local hex = ""
            if times then
                local sub = {}
                for i = a, b do sub[#sub + 1] = times[i] end
                hex = T.timesHex(sub)
            end
            CL.sendLine(piece, mode, voice.utt or 0, hex, voice.ago or 0)
            a = b + 1
        end
        return true
    end
    CL.sendLine(text, mode)
    return true
end

function CL.sendLine(text, mode, utt, hex, age)
    if mode == "w" or mode == "g" then
        if TheNet then TheNet:Say(text, mode == "w") end
    elseif utt then
        CL.rpc("say", text, mode, utt, hex or "", age or 0)
    else
        CL.rpc("say", text, mode)
    end
end

-- remember a sent line (Up / Down on the chat line bring it back)
function CL.remember(text)
    if text == "" then return end
    for i = #CL.recall, 1, -1 do if CL.recall[i] == text then table.remove(CL.recall, i) end end
    CL.recall[#CL.recall + 1] = text
    while #CL.recall > 10 do table.remove(CL.recall, 1) end
end

-- ---- players by name (commands)

function CL.findPlayer(arg)
    CL.refreshClients(true)
    arg = (arg or ""):lower()
    if arg == "" then return nil end
    local exact, starts = {}, {}
    local me = CL.me()
    for uid, c in pairs(CL.clients) do
        if uid ~= me then
            local n = (c.name or ""):lower()
            if n == arg then exact[#exact + 1] = uid
            elseif n:sub(1, #arg) == arg then starts[#starts + 1] = uid end
        end
    end
    local list = #exact > 0 and exact or starts
    if #list == 1 then return list[1] end
    if #list > 1 then
        local names = {}
        for _, uid in ipairs(list) do names[#names + 1] = CL.nameOf(uid) end
        table.sort(names)
        return nil, L("MANY_PLAYERS", table.concat(names, ", "))
    end
    return nil, L("NO_PLAYER", arg)
end

-- the other players in this session (for the Voice page): {uid, name} by name
function CL.others()
    CL.refreshClients(true)
    local me, out = CL.me(), {}
    for uid, c in pairs(CL.clients) do
        if uid ~= me and not (c.performance ~= nil and c.userid == nil) then out[#out + 1] = {uid = uid, name = CL.nameOf(uid)} end
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
end

-- ---- commands: true when the line was one of ours

function CL.command(text)
    local cmd, rest = text:match("^/(%S+)%s*(.-)%s*$")
    if not cmd then return false end
    cmd = cmd:lower()
    local modeOf = {s = "s", speak = "s", y = "y", yell = "y", w = "w", whisper = "w", g = "g", global = "g"}
    local m = modeOf[cmd]
    if m then
        if rest == "" then
            CL.setMode(m)
            CL.system(CL.modeLine())
        else
            CL.remember(text)
            CL.say(rest, m)
        end
        return true
    end
    if cmd ~= "pc" then return false end
    local sub, arg = rest:match("^(%S*)%s*(.-)$")
    sub = (sub or ""):lower()
    if sub == "" or sub == "help" then
        for _, line in ipairs(Strings.get("HELP")) do CL.system(line) end
        local r = CL.ranges
        CL.system(L("RANGES", r.whisperTiles, C.outerTiles(r, "w"), r.speakTiles, C.outerTiles(r, "s"), r.yellTiles,
            C.outerTiles(r, "y")))
    elseif sub == "settings" or sub == "voice" or sub == "translate" then
        if CL.openSettings then CL.openSettings(sub == "voice" and 2 or (sub == "translate" and 3 or 1)) end
    elseif sub == "mute" then
        if arg == "" then
            local names = {}
            for _, n in pairs(Settings.muted) do names[#names + 1] = n end
            table.sort(names)
            CL.system(#names > 0 and L("MUTED_LIST", table.concat(names, ", ")) or L("MUTED_NONE"))
        else
            local uid, err = CL.findPlayer(arg)
            if not uid then CL.system(err) return true end
            Settings.muted[uid] = CL.nameOf(uid)
            Settings.save()
            CL.bubbles[uid], CL.live[uid] = nil, nil
            CL.system(L("MUTED", CL.nameOf(uid)))
        end
    elseif sub == "unmute" then
        if arg:lower() == "all" then
            Settings.muted = {}
            Settings.save()
            CL.system(L("UNMUTED_ALL"))
        else
            local uid
            for u, n in pairs(Settings.muted) do if n:lower() == arg:lower() then uid = u end end
            local err
            if not uid then uid, err = CL.findPlayer(arg) end
            if not uid then CL.system(err) return true end
            Settings.muted[uid] = nil
            Settings.save()
            CL.system(L("UNMUTED", CL.nameOf(uid)))
        end
    elseif sub == "volume" or sub == "vol" then
        local who, val = arg:match("^(.-)%s+(%d+)%%?$")
        if not who then who = arg end
        if who == "" then
            local list = {}
            for uid, v in pairs(Settings.vol) do list[#list + 1] = CL.nameOf(uid, Settings.names[uid]) .. " " .. math.floor(v * 100 + 0.5) .. "%" end
            table.sort(list)
            CL.system(#list > 0 and L("VOLUME_LIST", table.concat(list, ", ")) or L("VOLUME_NONE"))
            return true
        end
        local uid, err = CL.findPlayer(who)
        if not uid then CL.system(err) return true end
        if val then
            local v = tonumber(val)
            if not v or v < 0 or v > Settings.VOL_MAX * 100 then CL.system(L("VOLUME_USAGE")) return true end
            Settings.names[uid] = CL.nameOf(uid)
            Settings.setVolume(uid, v / 100)
            CL.system(L("VOLUME_SET", CL.nameOf(uid), math.floor(Settings.volumeOf(uid) * 100 + 0.5)))
        else
            CL.system(L("VOLUME_IS", CL.nameOf(uid), math.floor(Settings.volumeOf(uid) * 100 + 0.5)))
        end
    elseif sub == "dummy" or sub == "dummies" then
        if CL.D then CL.D.command(arg) end
    elseif sub == "koetama" then
        if CL.K then for _, line in ipairs(CL.K.statusLines()) do CL.system(line) end end
    elseif sub == "range" or sub == "ranges" then
        local wh, sp, ye = arg:match("^(%d+)%s+(%d+)%s+(%d+)$")
        if not wh then
            CL.system(L("RANGE_USAGE", CL.ranges.whisperTiles, CL.ranges.speakTiles, CL.ranges.yellTiles))
            return true
        end
        local c = CL.client(CL.me())
        if not (c and c.admin) then CL.system(L("RANGE_ADMIN")) return true end
        local r = C.ranges(tonumber(sp), tonumber(ye), tonumber(wh))
        CL.rpc("ranges", r.speakTiles, r.yellTiles, r.whisperTiles)
        CL.system(L("RANGE_SENT", r.whisperTiles, r.speakTiles, r.yellTiles))
    else
        for _, line in ipairs(Strings.get("HELP")) do CL.system(line) end
    end
    return true
end

-- ---- the server's state (client RPCs)

function CL.onState(speak, yell, room, key, region, globalList, voiceOn, whisper)
    CL.gotState = true
    CL.ranges = C.ranges(speak, yell, whisper)
    CL.voiceOn = voiceOn ~= false
    CL.region = type(region) == "string" and region or ""
    if type(room) == "string" and room ~= "" then CL.room, CL.key = room, key end
    CL.onGlobal(globalList)
end

function CL.onRanges(speak, yell, whisper)
    CL.ranges = C.ranges(speak, yell, whisper)
end

function CL.onRoom(room, key, region)
    if type(room) == "string" and #room == 32 and type(key) == "string" and #key == 64 then
        CL.room, CL.key = room, key
        if type(region) == "string" then CL.region = region end
    end
end

function CL.onGlobal(list)
    CL.global = {}
    if type(list) ~= "string" then return end
    for uid in list:gmatch("[^,]+") do CL.global[uid] = true end
end

-- (modmain) the start of a session
function CL.init()
    CL.mode = Settings.mode
    CL.gotState, CL.helloAt, CL.vmodeSent = false, 0, nil
    CL.bubbles, CL.live, CL.samples = {}, {}, {}
    CL.room, CL.key = nil, nil
end

return CL
