-- The link to Koetama, the free companion app on this player's PC (github.com/AgeOfAlgorithms/koetama): Koetama's
-- PROTOCOL.md, "Transport: HTTP". Each client talks to its OWN Koetama on 127.0.0.1 (a dedicated server has none):
-- it POSTs its feed (where everyone is, the talk key, the chat lines to translate) and the answer carries Koetama's
-- objects (what this player said, the voice room, who is talking, translations).
--
-- The loop: one request at a time; while voices are in play (a voice room and someone in reach, the talk key held,
-- this player talking) a feed every 0.1 s, else a long poll (wait 1: the answer comes with the first object, or after
-- 1 s); a change that matters now (the talk key, a line to translate) goes at once as a second request. Koetama not
-- there: tried again every 5 s, quietly. Measured in DST (tools/probe, build 756039): QueryServer sends Content-Length
-- and Content-Type: application/json, several requests can be out at once, a refused port answers ok=false code=0.
local J = require "proxcomms/json"
local T = require "proxcomms/text"
local C = require "proxcomms/config"
local Settings = require "proxcomms/settings"
local Strings = require "proxcomms/strings"
local L = Strings.L

local K = {
    URL = "http://127.0.0.1:" .. C.KOETAMA_PORT .. "/",
    online = nil,             -- nil: not tried yet; true / false
    session = 0, ack = 0,
    features = {}, version = "", outdated = false, said = {},
    speech = "", mic = "", voiceState = "", voicePlayers = {}, talking = {},
    into = nil, pairs = {}, pairKeys = {},
    lines = {}, nextId = 1, cache = {}, cacheN = 0, buckets = {}, retry = {},
    polling = false, urgent = false, urgentAgain = false, lastSend = -1, retryAt = 0,
    roomAt = 0, roomTries = 0, roomOffer = nil,
    talkKey = false,
    liveUtt = nil, liveText = nil, liveAt = -1, liveSent = nil,
    startAt = nil,
    CL = nil,                 -- (modmain) the client half
    D = nil,                  -- (modmain) the test figures
}

K.LINE_TTL = 10
K.MAX_LINES = 16
K.MAX_BYTES = 400
K.ACTIVE_EVERY = 0.1
K.RETRY = 5                -- s between tries while Koetama is not there (the first 2 minutes of a session)
K.RETRY_LATER = 15         -- ... then (each failed try is a "CURL ERROR" line in DST's log)
K.LIVE_EVERY = 0.25
K.HEAD = 1.6              -- a character's head above the ground, in units (listener and speakers alike)

-- (tests replace it)
function K.query(url, cb, method, body)
    TheSim:QueryServer(url, cb, method, body)
end

-- (the link runs on real time: a world hosted alone autopauses in menus, and GetTime stops then)
local function now() return GetStaticTime and GetStaticTime() or GetTime() end

function K.newSession()
    K.session = (os.time() % 100000000) * 1000 + math.random(0, 999)
    K.ack = 0
end

-- ---- the feed

function K.listen()
    local m = Settings.mic
    if m == "off" then return "off" end
    if m == "always" then return "always" end
    if m == "ptt" then return "push_to_talk" end
    if TheInput and TheInput.ControllerAttached and TheInput:ControllerAttached() then return "always" end
    return "push_to_talk"
end

function K.lang()
    if Settings.lang ~= "" then return Settings.lang end
    return Strings.lang == "zh" and "zh" or (Strings.lang == "ru" and "ru" or "en")
end

-- where this player hears from: the character's head, the camera's axes (DST's FollowCamera: it looks along
-- (-cos h, ., -sin h); its right is (cos(h + 90), 0, sin(h + 90)))
function K.listener()
    local CL = K.CL
    local x, z = CL.myPos()
    if not x then return nil end
    local h = (TheCamera and TheCamera.GetHeading and TheCamera:GetHeading() or 0) * math.pi / 180
    local r = h + math.pi / 2
    return {position = {x, K.HEAD, z}, forward = {-math.cos(h), 0, -math.sin(h)}, right = {math.cos(r), 0, math.sin(r)}, up = {0, 1, 0}}
end

-- the other players this player can hear: near ones by position (their own Koetama announces how far their voice
-- carries), each with this player's volume for them. Not those in Global: Global is text only - typed, or what they
-- say written out - and no one hears it (the user, 2026-10-16, as in the Teardown mod)
function K.speakers()
    local CL = K.CL
    local me = CL.me()
    local out = J.array({})
    local x, z = CL.myPos()
    local far = CL.ranges.y[2] * 1.25
    local function entry(uid, name)
        local e = {id = uid, name = name}
        local v = Settings.volumeOf(uid)
        if CL.isMuted(uid) then v = 0 end
        if v ~= 1 then e.volume = math.floor(v * 100 + 0.5) / 100 end
        return e
    end
    for _, p in ipairs(AllPlayers or {}) do
        local uid = p.userid
        if uid and uid ~= "" and uid ~= me and p.Transform then
            local px, _, pz = p.Transform:GetWorldPosition()
            local d = x and math.sqrt((px - x) ^ 2 + (pz - z) ^ 2) or 1e9
            if not CL.global[uid] and d <= far then
                local e = entry(uid, CL.nameOf(uid, p.name))
                e.position = {px, K.HEAD, pz}
                if p.HasTag and p:HasTag("playerghost") then e.effects = {reverb = 0.35, wobble = 0.25} end
                out[#out + 1] = e
            end
        end
    end
    if K.D then
        for _, e in ipairs(K.D.speakers()) do out[#out + 1] = e end
    end
    return out
end

function K.translateList()
    local ids, out = {}, J.array({})
    for id in pairs(K.lines) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local l = K.lines[id]
        if not l.asked then out[#out + 1] = {id = id, text = l.text} end
    end
    return out
end

function K.feed(wait)
    local CL = K.CL
    local f = {type = "feed", session = K.session, ack = K.ack, wait = wait,
        volume = Settings.voiceVolume, listen = K.listen(), talk_key = K.talkKey, lang = K.lang(), live = Settings.live}
    local me = CL.me()
    if me then
        f.me = me
        f.name = CL.nameOf(me)
    end
    if CL.voiceOn and CL.room then
        f.room, f.key = CL.room, CL.key
        if CL.region ~= "" then f.region = CL.region end
    end
    local lis = K.listener()
    if lis then
        f.listener = lis
        f.speakers = K.speakers()
    else
        f.speakers = J.array({})
    end
    f.range = C.voiceRange(CL.ranges, CL.mode == "g" and "s" or CL.mode)
    f.max_range = CL.ranges.y[2]
    if CL.mode == "g" then
        f.to = J.array({})              -- (Global: the voice to no one; what is said still comes back as text)
    end
    local tr = K.translateList()
    if #tr > 0 then f.to_translate = tr end
    if K.A then K.A.feed(f) end                      -- (agents' definitions, lines and results: the brain only)
    return f
end

-- voices are in play: feed often (positions move)
function K.active()
    local CL = K.CL
    if K.A and K.A.busy() then return true end
    if K.talkKey or CL.live[CL.me() or ""] then return true end
    if K.D and K.D.any() then return true end
    if not (CL.voiceOn and CL.room) then return false end
    local x, z = CL.myPos()
    if not x then return false end
    local far = CL.ranges.y[2] * 1.25
    local me = CL.me()
    for _, p in ipairs(AllPlayers or {}) do
        if p.userid and p.userid ~= me and p.Transform then
            local px, _, pz = p.Transform:GetWorldPosition()
            if (px - x) ^ 2 + (pz - z) ^ 2 <= far * far then return true end
        end
    end
    return false
end

-- ---- requests

function K.post(wait, done)
    local ok, body = pcall(J.encode, K.feed(wait))
    if not ok then done(false) return end
    K.lastSend = now()
    local ok2 = pcall(K.query, K.URL, function(result, isSuccessful, code)
        done(K.onAnswer(result, isSuccessful, code))
    end, "POST", body)
    if not ok2 then done(false) end
end

function K.onAnswer(result, isSuccessful, code)
    if not isSuccessful or code ~= 200 then
        if code == 400 and not K.said.refused then
            K.said.refused = true
            K.CL.system(L("K_REFUSED", T.head(tostring(result or ""), 120)))
        end
        if code == 0 or not isSuccessful or code == nil then K.gone() end
        return false
    end
    local a = J.decode(result)
    if type(a) ~= "table" or type(a.last) ~= "number" then return true end
    if K.online ~= true then K.came() end
    local objects = type(a.objects) == "table" and a.objects or {}
    local first = type(a.first) == "number" and a.first or (a.last - #objects + 1)
    for i, o in ipairs(objects) do
        local n = first + i - 1
        if n > K.ack then
            K.ack = n
            if type(o) == "table" then
                local okh, err = pcall(K.onObject, o)
                if not okh then print("[Proximity Comms] Koetama object failed: " .. tostring(err)) end
            end
        end
    end
    if a.last > K.ack then K.ack = a.last end
    return true
end

function K.came()
    K.online = true
    K.said = {}
end

function K.gone()
    if K.online == true then K.CL.system(L("K_GONE")) end
    K.online = false
    K.features, K.version, K.outdated = {}, "", false
    K.speech, K.mic, K.voiceState, K.voicePlayers, K.talking = "", "", "", {}, {}
    K.into, K.pairs, K.pairKeys, K.lines, K.retry = nil, {}, {}, {}, {}
    K.roomOffer, K.roomTries = nil, 0
    K.liveUtt, K.liveText, K.liveSent = nil, nil, nil
    local me = K.CL.me()
    if me then K.CL.live[me] = nil end
end

-- a change that matters now: a second request (wait 0), not behind the long poll
function K.poke()
    if K.online ~= true then return end
    if K.urgent then K.urgentAgain = true return end
    K.urgent = true
    K.post(0, function()
        K.urgent = false
        if K.urgentAgain then
            K.urgentAgain = false
            K.poke()
        end
    end)
end

function K.setTalk(down)
    if K.talkKey == down then return end
    K.talkKey = down
    K.poke()
end

-- ---- Koetama's objects

function K.onObject(o)
    local CL = K.CL
    local t = o.type
    if t == "hello" then
        K.features = {}
        for _, f in ipairs(type(o.features) == "table" and o.features or {}) do K.features[f] = true end
        K.version = tostring(o.version or "")
        K.outdated = C.olderThan(K.version, C.KOETAMA_MIN)
        if K.A then K.A.onHello(K.features) end
        if not K.said.hello then
            K.said.hello = true
            CL.system(L("K_CONNECTED"))
            if K.outdated then CL.system(L("K_OLD", K.version)) end
        end
    elseif t == "speech" then
        K.onSpeech(o)
    elseif t == "agents_known" then                     -- (agents: this game is the brain - proxcomms/agents.lua)
        if K.A then K.A.onKnown(o) end
    elseif t == "received" then
        if K.A then K.A.onReceived(o) end
    elseif t == "agent_reply" then
        if K.A then K.A.onReply(o) end
    elseif t == "agent_status" then
        if K.A then K.A.onStatus(o) end
    elseif t == "room" then
        if type(o.room) == "string" and type(o.key) == "string" then
            K.roomOffer, K.roomTries, K.roomAt = {o.room, o.key}, 0, 0
        end
    elseif t == "voice" then
        K.voicePlayers = type(o.players) == "table" and o.players or {}
        local s = tostring(o.state or "")
        if s ~= K.voiceState then
            local was = K.voiceState
            K.voiceState = s
            if s == "unreachable" then CL.system(L("K_VOICE_UNREACHABLE"))
            elseif s == "connected" and was == "unreachable" then CL.system(L("K_VOICE_BACK"))
            elseif s == "id_taken" then CL.system(L("K_ID_TAKEN")) end
        end
    elseif t == "talking" then
        if type(o.id) == "string" or type(o.id) == "number" then K.talking[tostring(o.id)] = o.talking == true or nil end
    elseif t == "status" then
        local sp, mic = tostring(o.speech or ""), tostring(o.microphone or "")
        if sp ~= K.speech or mic ~= K.mic then
            K.speech, K.mic = sp, mic
            if mic == "none" and not K.said.mic then K.said.mic = true CL.system(L("K_MIC_NONE"))
            elseif sp == "loading" and not K.said.loading then K.said.loading = true CL.system(L("K_LOADING"))
            elseif sp == "error" then CL.system(L("K_SPEECH_ERROR"))
            elseif sp == "ready" and mic == "open" and K.said.loading and not K.said.ready then K.said.ready = true CL.system(L("K_READY")) end
        end
    elseif t == "translation" then
        K.onTranslation(o)
    elseif t == "translations_status" then
        if type(o.into) == "string" then
            K.into = o.into
            if o.into == "" then K.lines = {} end
        end
        K.pairs, K.pairKeys = {}, {}
        for _, s in ipairs(type(o.translations) == "table" and o.translations or {}) do
            if type(s) == "table" then
                local key = tostring(s.from) .. ">" .. tostring(s.to)
                K.pairs[key] = {from = tostring(s.from), to = tostring(s.to), state = tostring(s.state or ""), progress = tonumber(s.progress) or 0}
                K.pairKeys[#K.pairKeys + 1] = key
            end
        end
        table.sort(K.pairKeys)
        if K.allReady() and #K.retry > 0 then
            for _, l in ipairs(K.retry) do K.ask(l.uid, l.text, l.b, true) end
            K.retry = {}
        end
    end
end

-- what this player says (speech to text): start / live / final
function K.onSpeech(o)
    local CL = K.CL
    local me = CL.me()
    if not me then return end
    local mode = CL.mode
    if o.kind == "start" then
        K.liveUtt, K.liveText, K.liveSent = o.utt, "", nil
        if Settings.live then CL.live[me] = {utt = o.utt, text = "", mode = mode, t = CL.now()} end
        K.liveAt = -1
    elseif o.kind == "live" and type(o.text) == "string" then
        K.liveUtt, K.liveText = o.utt, o.text
        if Settings.live then CL.live[me] = {utt = o.utt, text = T.clean(o.text, 200), mode = mode, t = CL.now()} end
    elseif o.kind == "final" then
        CL.live[me] = nil
        K.liveUtt, K.liveText, K.liveSent = nil, nil, nil
        local text = type(o.text) == "string" and o.text or ""
        if text ~= "" then
            local times = nil
            if type(o.times) == "table" then
                times = {}
                for i, v in ipairs(o.times) do times[i] = tonumber(v) or 0 end
            end
            CL.say(text, mode, {utt = tonumber(o.utt) or 0, times = times, ago = tonumber(o.ago) or 0})
        end
    end
end

-- live words to the players in reach, at most every 0.25 s ("" first: they started talking). Not in Global (only the
-- finished line goes to everyone).
function K.liveTick(t)
    if K.liveText == nil or K.CL.mode == "g" then return end
    if t - K.liveAt < K.LIVE_EVERY then return end
    local key = tostring(K.liveUtt) .. ":" .. K.liveText
    if key == K.liveSent then return end
    K.liveAt, K.liveSent = t, key
    K.CL.rpc("live", tonumber(K.liveUtt) or 0, T.tail(K.liveText, 200), K.CL.mode)
end

-- ---- translation (Koetama's PROTOCOL.md "Translation": what into what is the player's setting in Koetama)

function K.allReady()
    for _, p in pairs(K.pairs) do
        if p.state == "downloading" or p.state == "loading" then return false end
    end
    return true
end

-- a line another player said, made out in full: translated if Koetama translates
function K.want(uid, text, b)
    if K.online ~= true or not K.features.translate or K.into == "" then return end
    if type(text) ~= "string" or text == "" then return end
    local t = now()
    -- (a flood costs this player's CPU: per speaker 6 at once, then one every 2 s; the same text once per 30 s)
    local bk = K.buckets[uid]
    if not bk then bk = {n = 6, t = t} K.buckets[uid] = bk end
    bk.n = math.min(6, bk.n + (t - bk.t) / 2)
    bk.t = t
    local c = K.cache[text]
    if c and t - c.t < 30 then
        if c.tr and c.tr ~= "" then K.CL.translated(uid, K.CL.nameOf(uid, b and b.name), c.tr, b) end
        return
    end
    if bk.n < 1 then return end
    bk.n = bk.n - 1
    K.ask(uid, text, b)
end

function K.ask(uid, text, b, retried)
    local id = K.nextId
    K.nextId = K.nextId + 1
    K.lines[id] = {text = T.cutBytes(text, K.MAX_BYTES), uid = uid, b = b, t = now(), retried = retried,
        name = K.CL.nameOf(uid, b and b.name)}
    local n = 0
    for _ in pairs(K.lines) do n = n + 1 end
    while n > K.MAX_LINES do
        local oldest
        for lid in pairs(K.lines) do if not oldest or lid < oldest then oldest = lid end end
        K.lines[oldest] = nil
        n = n - 1
    end
    if K.cacheN > 64 then K.cache, K.cacheN = {}, 0 end
    K.cache[text], K.cacheN = {t = now()}, K.cacheN + 1
    K.poke()
end

function K.onTranslation(o)
    local l = K.lines[o.id]
    if not l then return end
    K.lines[o.id] = nil
    local text = type(o.text) == "string" and o.text or ""
    if text ~= "" then
        if K.cache[l.text] then K.cache[l.text].tr = text end
        K.CL.translated(l.uid, l.name, text, l.b)
    elseif not K.allReady() and not l.retried then
        K.retry[#K.retry + 1] = l               -- ("" also means "the models are not ready yet": asked again then)
        if K.cache[l.text] then K.cache[l.text] = nil end
    end
end

-- ---- every frame

function K.retryEvery()
    if K.startAt and now() - K.startAt > 120 then return K.RETRY_LATER end
    return K.RETRY
end

function K.tick()
    local t = now()
    local CL = K.CL
    if not CL.me() then return end
    K.startAt = K.startAt or t
    for id, l in pairs(K.lines) do
        if t - l.t > K.LINE_TTL then K.lines[id] = nil end
    end
    K.liveTick(t)
    if K.A then K.A.clientTick() end
    -- (the voice room Koetama offered: to the server every 2 s, until the server's room is known; 30 tries)
    if K.roomOffer and not CL.room and t >= K.roomAt and K.roomTries < 30 then
        K.roomAt, K.roomTries = t + 2, K.roomTries + 1
        CL.rpc("room", K.roomOffer[1], K.roomOffer[2])
    end
    if K.online ~= true then
        if not K.polling and t >= K.retryAt then
            K.polling = true
            K.newSession()
            K.post(0, function(ok)
                K.polling = false
                if not ok then K.retryAt = now() + K.retryEvery() end
            end)
        end
        -- (a quiet pointer, in a player's first three sessions without it)
        if K.online == false and not K.said.pointer and t - K.startAt > 20 and (Settings.pointed or 0) < 3 then
            K.said.pointer = true
            Settings.pointed = (Settings.pointed or 0) + 1
            Settings.save()
            CL.system(L("K_NOT_RUNNING", C.KOETAMA_URL))
        end
        return
    end
    if K.polling then return end
    local function done(ok)
        K.polling = false
        if not ok then K.retryAt = now() + K.retryEvery() end
    end
    if K.active() then
        if t - K.lastSend >= K.ACTIVE_EVERY then
            K.polling = true
            K.post(0, done)
        end
    else
        K.polling = true
        K.post(1, done)
    end
end

-- /pc koetama
function K.statusLines()
    local out = {}
    if K.online ~= true then
        out[1] = L("K_NOT_RUNNING", C.KOETAMA_URL)
    else
        out[1] = L("VOICE_STATE", K.version, K.speech ~= "" and K.speech or "-", K.mic ~= "" and K.mic or "-",
            K.voiceState ~= "" and K.voiceState or "-")
        if K.outdated then out[#out + 1] = L("K_OLD", K.version) end
        if K.into == nil then out[#out + 1] = L("TR_WAIT")
        elseif K.into == "" then out[#out + 1] = L("TR_OFF")
        else out[#out + 1] = L("TR_INTO", Strings.langName(K.into)) end
    end
    out[#out + 1] = L("K_PRIVACY")
    return out
end

return K
