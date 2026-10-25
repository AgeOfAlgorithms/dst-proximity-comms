-- AGENTS: AI characters (or other jobs) a mod puts in the world, played by the large language model of an admin's
-- Koetama (Koetama's PROTOCOL.md "Large language models: agents", docs/agents-guide.md; the Teardown mod's agents.lua,
-- its API 17-18, ported - the user, 2026-10-25). Players talk to them as to anyone (typed or spoken, Whisper / Speak /
-- Yell near them, Global if they hear "all"); an agent's reply is said like a player's line (a bubble over it, its mode's
-- reach, garbled across the buffer, in the history, translated, captions); its function calls go to the mod, which checks
-- each, acts and answers.
--
-- A MOD CALLS (server; GLOBAL.ProxComms - README "Agents"):
--   ProxComms.agent(id, def)    define or change an agent (nil: remove). def: persona (required: who it is, up to 8 KB),
--                               name, entity (an inst: it hears and speaks where it is) or x / z, hears (near - the
--                               default - / named / engaged / all / none), mode (whisper / speak / yell / global),
--                               functions (a list of {name, description, parameters}, or that list as JSON), state (a
--                               string or a function returning one: what it should know now), max_words, stream (false:
--                               no live words), character (false: not a character - the persona is the whole prompt),
--                               onCall(call) (return "ok: ..." / "error: ..." now, or nil and ProxComms.result later),
--                               onReply(text, info), onError(code, why)
--   ProxComms.event(id, text)   a line for it to hear from the game; .note(id, text): with its next line, once;
--   ProxComms.say(id, text)     it says this without the model (the model hears of it with its next line);
--   ProxComms.forget(id)        its conversation starts over; .result(callId, text): a call's answer;
--   ProxComms.status()          "ready" / "busy" / "budget" / "error" / "off"
--   World events: proxcomms_agent_call (a call), proxcomms_said (its line said: .agent set), proxcomms_agent_error.
--
-- WHOSE KOETAMA: an ADMIN's whose language model is on for Don't Starve Together (its hello names "llm"): its game
-- sends "llm" to its shard's server, the master shard picks one (the one already chosen, else the lowest id; a candidate
-- unheard for 30 s drops out) and tells every shard - the "brain". No other player's game ever gets what is said near
-- an agent. The brain may be on another shard than an agent (caves): everything between them goes through the shards.
-- THE SERVER (every shard): the mods' agents, who hears what (S.onSay, the native lines the speakers' games report), the
-- replies said, the calls handed to the mod. THE BRAIN (the admin's game): the definitions (versioned), lines and results
-- in Koetama's feed until "received", the replies and calls back to the agent's shard.
local C = require "proxcomms/config"
local T = require "proxcomms/text"
local J = require "proxcomms/json"

local A = {}
A.API = 1                       -- ProxComms.version
A.LINE_LIFE = 60                -- s a line waits for its reply (the brain)
A.LINES_MAX = 32
A.SEND_FOR = 5                  -- s definitions go in the feed after a hello or a change, before agents_known
A.ENGAGED = 30                  -- s a player it answered (or who named it) stays heard by an agent that hears "engaged"
A.CAND_LIFE = 30                -- s a brain candidate is kept without being heard again
A.CALL_LIFE = 30                -- s a call waits for the mod's answer
A.REPLY_MAX = 600
A.HEARS = {near = true, named = true, engaged = true, all = true, none = true}
A.MODES = {whisper = "w", w = "w", speak = "s", s = "s", yell = "y", shout = "y", y = "y", global = "g", g = "g"}
A.PREFIX = "agent:"             -- an agent's speaker id in lines (uid "agent:<kid>")

-- the game's side, set by modmain / tests
A.S, A.CL, A.K = nil, nil, nil

local function now() return (GetStaticTime and GetStaticTime()) or (GetTime and GetTime()) or 0 end

function A.idOk(id)
    return type(id) == "string" and #id >= 1 and #id <= 48 and id:find("^[%w_%.%-]+$") ~= nil
end

-- this shard's tag, and an agent's id for Koetama: "<id>:<shard>" (the same mod's agent may be in both worlds)
function A.shard()
    local ok, s = pcall(function() return TheShard and TheShard:GetShardId() end)
    return ok and s and tostring(s) or "1"
end
function A.kid(id) return id .. ":" .. A.shard() end
function A.split(kid)
    if type(kid) ~= "string" then return nil end
    return kid:match("^(.-):([^:]+)$")
end

local function shardRPC(name) return GetShardModRPC(C.NAMESPACE, name) end
local function clientRPC(name) return GetClientModRPC(C.NAMESPACE, name) end
local function toShards(name, ...) pcall(SendModRPCToShard, shardRPC(name), nil, ...) end

-- ==================================================================================== THE SERVER (every shard)

A.agents = {}          -- id -> {id, kid, def fields, sig, notes, said}
A.owner = nil          -- the brain's userid (the master's choice, on every shard)
A.state = "ready"      -- the brain's agent_status
A.cands = {}           -- (master) userid -> last heard
A.calls = {}           -- call id -> {id (agent), t}
A.eng = {}             -- id -> userid -> when it was named / answered

function A.isLocal(uid)
    for _, p in ipairs(AllPlayers or {}) do
        if p.userid == uid then return p end
    end
    return nil
end

function A.status()
    if not A.owner then return "off" end
    return A.state or "ready"
end

-- a definition's functions as a list (a Lua list, or JSON): empty "required" lists dropped (they would go as {})
local function functionsOf(f)
    if type(f) == "string" then f = J.decode(f) end
    if type(f) ~= "table" then return nil end
    local out = J.array({})
    for _, fn in ipairs(f) do
        if type(fn) == "table" and type(fn.name) == "string" and #out < 16 then
            local p = type(fn.parameters) == "table" and fn.parameters or {type = "object", properties = {}}
            if type(p.required) == "table" and p.required[1] == nil then p.required = nil end
            out[#out + 1] = {name = fn.name, description = tostring(fn.description or ""), parameters = p}
        end
    end
    return out
end

-- (server) what Koetama gets of an agent: its definition, without a version (the brain versions it)
local function defOf(a)
    local d = {kid = a.kid, persona = a.persona, max_words = a.max_words, character = a.character, stream = a.stream}
    if a.functions and #a.functions > 0 then d.functions = a.functions end
    return d
end

-- (server) to the brain: on this shard, straight to its game; else through the shards (the one it is on hands it on)
function A.up(kind, t)
    if not A.owner then return false end
    local s = J.encode(t)
    if A.isLocal(A.owner) then
        SendModRPCToClient(clientRPC("agent_up"), A.owner, kind, s)
    else
        toShards("agent_up", kind, s)
    end
    return true
end

function A.onShardUp(shard, kind, s)
    if A.owner and A.isLocal(A.owner) and type(kind) == "string" and type(s) == "string" then
        SendModRPCToClient(clientRPC("agent_up"), A.owner, kind, s)
    end
end

-- (API) define, change or (def nil) remove an agent
function A.define(id, def)
    if not A.idOk(id) then return false, "an agent id is 1-48 of A-Z a-z 0-9 _ . -" end
    if def == nil then
        if A.agents[id] then
            A.agents[id] = nil
            A.up("remove", {kid = A.kid(id)})
        end
        return true
    end
    if type(def) ~= "table" or type(def.persona) ~= "string" or def.persona == "" then return false, "no persona" end
    local a = A.agents[id] or {id = id, kid = A.kid(id), notes = {}, said = {}}
    a.persona = T.cutBytes(def.persona, 8192)
    a.name = T.clean(type(def.name) == "string" and def.name or id, C.NAME_LEN)
    if a.name == "" then a.name = id end
    a.entity = def.entity
    a.x, a.z = tonumber(def.x), tonumber(def.z)
    a.hears = A.HEARS[def.hears] and def.hears or "near"
    a.mode = A.MODES[type(def.mode) == "string" and def.mode:lower() or ""] or "s"
    a.functions = functionsOf(def.functions)
    a.state = def.state
    a.max_words = math.max(1, math.min(1000, math.floor(tonumber(def.max_words) or 80)))
    a.stream = def.stream ~= false
    a.character = def.character ~= false
    a.onCall, a.onReply, a.onError = def.onCall, def.onReply, def.onError
    A.agents[id] = a
    local sig = J.encode(defOf(a))
    if sig ~= a.sig then
        a.sig = sig
        A.up("def", defOf(a))
    end
    return true
end

-- where an agent is (x, z), or nil: its entity while valid, else the place it was given
function A.posOf(a)
    local e = a.entity
    if e and e.Transform and (not e.IsValid or e:IsValid()) then
        local x, _, z = e.Transform:GetWorldPosition()
        a.lastX, a.lastZ = x, z
        return x, z
    end
    if a.x and a.z then return a.x, a.z end
    return a.lastX, a.lastZ
end

-- its name said in a line ("Pig King, ..." - any case, whole words)
function A.named(text, name)
    local t, n = " " .. tostring(text):lower() .. " ", tostring(name):lower()
    if n == "" then return false end
    local i = 1
    while true do
        local a, b = t:find(n, i, true)
        if not a then return false end
        if not t:sub(a - 1, a - 1):find("[%w]") and not t:sub(b + 1, b + 1):find("[%w]") then return true end
        i = a + 1
    end
end

local function stateOf(a)
    local s = a.state
    if type(s) == "function" then
        local ok, v = pcall(s, a.id)
        s = ok and v or nil
    end
    if type(s) ~= "string" or s == "" then return nil end
    return T.cutBytes(s, 2048)
end

-- (server) a line for an agent: what it said without the model and the mod's note first (as events, once each)
function A.lineUp(a, text, from)
    text = T.cutBytes(tostring(text or ""), 400)
    if text == "" then return end
    for _, said in ipairs(a.said) do A.up("line", {kid = a.kid, text = T.cutBytes("you said: " .. said, 400)}) end
    a.said = {}
    for _, note in ipairs(a.notes) do A.up("line", {kid = a.kid, text = note}) end
    a.notes = {}
    A.up("line", {kid = a.kid, text = text, from = from, state = stateOf(a)})
end

-- (server) a player (uid, name) said text in mode at x, z: the agents that hear it get it
function A.hear(uid, name, text, mode, x, z)
    if not A.owner or type(text) ~= "string" or text == "" then return end
    local t = now()
    for id, a in pairs(A.agents) do
        local hear = a.hears == "all"
        local named = (a.hears == "named" or a.hears == "engaged") and A.named(text, a.name)
        local eng = A.eng[id] and A.eng[id][uid]
        local engaged = a.hears == "engaged" and eng ~= nil and t - eng <= A.ENGAGED
        if (a.hears == "near" or named or engaged) and mode ~= "g" and x and z then
            local ax, az = A.posOf(a)
            local r = A.S.ranges[mode] or A.S.ranges.s
            hear = ax ~= nil and (ax - x) ^ 2 + (az - z) ^ 2 <= (r[1] + 1) ^ 2
        end
        if hear then
            if named then A.eng[id] = A.eng[id] or {} A.eng[id][uid] = t end
            A.lineUp(a, text, {id = uid, name = name})
        end
    end
end

-- (server RPC) a player's own Whisper / Global line (DST's chat: the server does not see it otherwise), reported by
-- their game: the agents that hear it get it
function A.onHeard(player, text, whisper)
    local uid = A.S.who(player)
    if not uid or type(text) ~= "string" or #text > C.MAX_LEN * 4 or not A.S.allow(uid, "heard", 1, 6) then return end
    text = T.clean(text, C.MAX_LEN)
    if text == "" then return end
    local x, z = A.S.pos(player)
    A.hear(uid, A.S.nameOf(player), text, whisper == true and "w" or "g", x, z)
end

-- (server) an agent's line said as a player's: the players in its mode's reach (Global: everyone; nowhere: everyone)
function A.deliver(a, text, info)
    text = T.clean(text, A.REPLY_MAX)
    if text == "" then return 0 end
    local x, z = A.posOf(a)
    local mode = a.mode
    local to
    if mode ~= "g" and x then to = A.S.near(x, z, A.S.reach(mode)) end
    A.S.lineId = A.S.lineId + 1
    local uid = A.PREFIX .. a.kid
    if to == nil or #to > 0 then
        SendModRPCToClient(clientRPC("line"), to, uid, a.name, text, mode, A.S.lineId, x or 0, z or 0, false, 0, "", 0)
    end
    local heard = to and #to or #(AllPlayers or {})
    info = info or {}
    info.heard = heard
    if type(a.onReply) == "function" then pcall(a.onReply, text, info) end
    if TheWorld then
        TheWorld:PushEvent("proxcomms_said", {agent = a.id, userid = uid, mode = mode, text = text, x = x, z = z,
            heard = heard, from = info.from, lines = info.lines,
            range = (A.S.ranges[mode] or A.S.ranges.s)[1], reach = (A.S.ranges[mode] or A.S.ranges.s)[2]})
    end
    return heard
end

-- (API) it says this without the model (the model hears of it with its next line)
function A.say(id, text)
    local a = A.agents[id]
    if not a or type(text) ~= "string" then return false end
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        if line ~= "" then
            A.deliver(a, line, {from = {}, lines = {}, scripted = true})
            a.said[#a.said + 1] = line
            while #a.said > 3 do table.remove(a.said, 1) end
        end
    end
    return true
end

function A.event(id, text)
    local a = A.agents[id]
    if not a or type(text) ~= "string" then return false end
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do if line ~= "" then A.lineUp(a, line, nil) end end
    return true
end

function A.note(id, text)
    local a = A.agents[id]
    if not a or type(text) ~= "string" or text == "" then return false end
    a.notes[#a.notes + 1] = T.cutBytes(text, 400)
    return true
end

function A.forget(id)
    local a = A.agents[id]
    if not a then return false end
    A.up("forget", {kid = a.kid})
    return true
end

-- (API) a call's answer ("ok: ..." / "error: ..."), back to the model
function A.result(callId, text)
    local c = A.calls[callId]
    if not c or type(text) ~= "string" then return false end
    A.calls[callId] = nil
    A.up("result", {call = callId, result = T.cutBytes(text, 1000)})
    return true
end

-- (server) from the brain, for an agent of this shard (or the status, for every shard)
function A.handle(kind, t)
    if type(t) ~= "table" then return end
    if kind == "status" then
        if t.state == "ready" or t.state == "busy" or t.state == "budget" or t.state == "error" then A.state = t.state end
        return
    end
    if kind == "sync" then                              -- (the brain asks for every definition: a new brain, a hello)
        for _, a in pairs(A.agents) do A.up("def", defOf(a)) end
        return
    end
    local id, shard = A.split(t.kid)
    if shard ~= A.shard() then return end
    local a = id and A.agents[id]
    if not a then return end
    local from = type(t.from) == "table" and t.from or {}
    local lines = type(t.lines) == "table" and t.lines or {}
    if kind == "say" then
        local tm = now()
        for _, uid in ipairs(from) do
            if type(uid) == "string" then A.eng[id] = A.eng[id] or {} A.eng[id][uid] = tm end
        end
        if type(t.text) == "string" and t.text ~= "" then A.deliver(a, t.text, {from = from, lines = lines}) end
    elseif kind == "live" then
        local x, z = A.posOf(a)
        if a.mode == "g" or not x or type(t.text) ~= "string" then return end
        SendModRPCToClient(clientRPC("live"), A.S.near(x, z, A.S.reach(a.mode)), A.PREFIX .. a.kid, a.name,
            tonumber(t.utt) or 1, T.clean(T.tail(t.text, 200), 200), a.mode, x, z)
    elseif kind == "call" then
        if type(t.call) ~= "string" or type(t.name) ~= "string" then return end
        A.calls[t.call] = {id = id, t = now()}
        local call = {id = t.call, agent = id, name = t.name, args = type(t.args) == "table" and t.args or {},
            from = from, lines = lines}
        if TheWorld then TheWorld:PushEvent("proxcomms_agent_call", call) end
        if type(a.onCall) == "function" then
            local ok, r = pcall(a.onCall, call)
            if ok and type(r) == "string" then A.result(t.call, r)
            elseif not ok then A.result(t.call, "error: " .. tostring(r):sub(1, 200)) end
        end
    elseif kind == "error" then
        a.error, a.why = tostring(t.error or ""), tostring(t.why or "")
        if type(a.onError) == "function" then pcall(a.onError, a.error, a.why) end
        if TheWorld then TheWorld:PushEvent("proxcomms_agent_error", {agent = id, error = a.error, why = a.why}) end
    end
end

-- (server RPC) the brain's game sends kind with t (JSON) - only the brain
function A.onDown(player, kind, s)
    local uid = A.S.who(player)
    if not uid or uid ~= A.owner or type(kind) ~= "string" or type(s) ~= "string" or #s > 16384 then return end
    local t = J.decode(s)
    if type(t) ~= "table" then return end
    if kind == "status" or kind == "sync" then
        A.handle(kind, t)
        toShards("agent_down", kind, s)
        return
    end
    local _, shard = A.split(t.kid)
    if shard == A.shard() then A.handle(kind, t) else toShards("agent_down", kind, s) end
end

function A.onShardDown(shard, kind, s)
    if type(kind) ~= "string" or type(s) ~= "string" then return end
    local t = J.decode(s)
    if type(t) ~= "table" then return end
    if kind == "status" or kind == "sync" then A.handle(kind, t) return end
    local _, sh = A.split(t.kid)
    if sh == A.shard() then A.handle(kind, t) end
end

-- (server RPC) a player's game says its Koetama's language model is on (or off): an admin's only, to the master
function A.onLlm(player, on)
    local uid = A.S.who(player)
    if not uid then return end
    local c = TheNet and TheNet.GetClientTableForUser and TheNet:GetClientTableForUser(uid)
    if not (c and c.admin) then return end
    on = on == true
    if uid == A.owner and on and A.isLocal(uid) then        -- (the brain came to this shard: tell it so)
        SendModRPCToClient(clientRPC("agent_owner"), uid, true)
    end
    if A.S.isMaster() then A.cand(uid, on) else toShards("llm_cand", uid, on) end
end

function A.onShardCand(shard, uid, on)
    if A.S.isMaster() and type(uid) == "string" then A.cand(uid, on == true) end
end

-- (master) a candidate heard (or gone); the brain chosen
function A.cand(uid, on)
    A.cands[uid] = on and now() or nil
    A.elect()
end

function A.elect()
    local t = now()
    for uid, at in pairs(A.cands) do
        if t - at > A.CAND_LIFE then A.cands[uid] = nil end
    end
    local pick = A.owner and A.cands[A.owner] and A.owner or nil
    if not pick then
        for uid in pairs(A.cands) do
            if not pick or uid < pick then pick = uid end
        end
    end
    if pick ~= A.owner then
        A.setOwner(pick)
        toShards("llm_owner", pick or "")
    end
end

function A.onShardOwner(shard, uid)
    if type(uid) == "string" then A.setOwner(uid ~= "" and uid or nil) end
end

function A.setOwner(uid)
    local old = A.owner
    A.owner = uid
    if old and old ~= uid and A.isLocal(old) then SendModRPCToClient(clientRPC("agent_owner"), old, false) end
    if uid and A.isLocal(uid) then SendModRPCToClient(clientRPC("agent_owner"), uid, true) end
    if not uid then A.state = "ready" end
end

-- (server, every second) the master's choice kept fresh; calls the mod never answered dropped
function A.serverTick()
    if A.S.isMaster() then A.elect() end
    local t = now()
    for k, c in pairs(A.calls) do
        if t - c.t > A.CALL_LIFE then A.calls[k] = nil end
    end
end

-- ==================================================================================== THE BRAIN (the admin's game)

A.brain = {on = false, defs = {}, lines = {}, results = {}, forget = {}, known = nil, sentAt = -1e9, n = 0,
    lineFrom = {}, liveOn = {}, utt = {}, callIds = {}, llmAt = -1e9, llmSaid = nil}

local function B() return A.brain end

function A.down(kind, t)
    if A.CL then A.CL.rpc("agent_down", kind, J.encode(t or {})) end
end

-- (client RPC) this game is the brain now (or no longer)
function A.onOwner(on)
    local b = B()
    b.on = on == true
    if b.on then
        b.sentAt, b.known = now(), nil
        A.down("sync", {})
    else
        b.defs, b.lines, b.results, b.forget = {}, {}, {}, {}
    end
end

-- (client RPC) from an agent's server
function A.onUp(kind, s)
    local b = B()
    if not b.on or type(kind) ~= "string" or type(s) ~= "string" then return end
    local t = J.decode(s)
    if type(t) ~= "table" or type(t.kid) ~= "string" and kind ~= "result" then return end
    if kind == "def" then
        local sig = s
        local d = b.defs[t.kid]
        if not d or d.sig ~= sig then
            local def = {id = t.kid, version = (d and d.def.version or 0) + 1, persona = t.persona,
                character = t.character ~= false, stream = t.stream ~= false, max_words = t.max_words, functions = t.functions}
            b.defs[t.kid] = {sig = sig, def = def}
            b.sentAt = now()
            if A.K then A.K.poke() end
        end
    elseif kind == "remove" then
        b.defs[t.kid] = nil
    elseif kind == "line" then
        b.n = b.n + 1
        b.lineFrom[b.n] = type(t.from) == "table" and t.from.id or nil
        b.lineFrom[b.n - 300] = nil
        local from = type(t.from) == "table" and {id = tostring(t.from.id), name = tostring(t.from.name or "?")} or nil
        b.lines[#b.lines + 1] = {id = b.n, agent = t.kid, text = t.text, from = from, state = t.state, t = now()}
        while #b.lines > A.LINES_MAX do table.remove(b.lines, 1) end
        if A.K then A.K.poke() end
    elseif kind == "forget" then
        b.forget[#b.forget + 1] = {id = t.kid, t = now()}
        if A.K then A.K.poke() end
    elseif kind == "result" then
        if type(t.call) == "string" then
            b.results[#b.results + 1] = {call = t.call, result = tostring(t.result or ""), ids = b.callIds[t.call]}
            b.callIds[t.call] = nil
            if A.K then A.K.poke() end
        end
    end
end

-- (the brain's Koetama) its hello: definitions again (it keeps them only for its session); the server told
function A.onHello(features)
    local b = B()
    b.sentAt, b.known = now(), nil
    b.llm = features and features.llm == true or false
    b.llmAt = -1e9                               -- (said to the server at once)
end

function A.onKnown(o)
    local known = {}
    for _, a in ipairs(type(o.agents) == "table" and o.agents or {}) do
        if type(a) == "table" and type(a.id) == "string" and tonumber(a.version) then known[a.id] = tonumber(a.version) end
    end
    B().known = known
end

function A.onReceived(o)
    local b = B()
    local got, calls = {}, {}
    for _, x in ipairs(type(o.to_agent) == "table" and o.to_agent or {}) do if tonumber(x) then got[tonumber(x)] = true end end
    for _, x in ipairs(type(o.agent_results) == "table" and o.agent_results or {}) do if type(x) == "string" then calls[x] = true end end
    for _, l in ipairs(b.lines) do if got[l.id] then l.received = true end end
    for _, r in ipairs(b.results) do if calls[r.call] then r.received = true end end
end

function A.onStatus(o)
    local s = o.state
    if s == "ready" or s == "busy" or s == "budget" or s == "error" then
        if B().state ~= s then B().state = s A.down("status", {state = s}) end
    end
end

-- (K.feed) the agents' fields: definitions Koetama lacks (or has older), lines and results not yet received, forgets
function A.feed(f)
    local b = B()
    if not (b.on and b.llm) then return end
    local t = now()
    local defs = J.array({})
    for _, d in pairs(b.defs) do
        local want
        if b.known then local kv = b.known[d.def.id] want = kv == nil or kv < d.def.version
        else want = t - b.sentAt < A.SEND_FOR end
        if want and #defs < 32 then defs[#defs + 1] = d.def end
    end
    if #defs > 0 then f.agents = defs end
    local lines = J.array({})
    for _, l in ipairs(b.lines) do
        if #lines < 8 and not l.received then lines[#lines + 1] = {id = l.id, agent = l.agent, text = l.text, from = l.from, state = l.state} end
    end
    if #lines > 0 then f.to_agent = lines end
    local res = J.array({})
    for _, r in ipairs(b.results) do if not r.received then res[#res + 1] = {call = r.call, result = r.result} end end
    if #res > 0 then f.agent_results = res end
    local fg = J.array({})
    for _, x in ipairs(b.forget) do fg[#fg + 1] = x.id end
    if #fg > 0 then f.agent_forget = fg end
end

-- (K.active) lines or results waiting: feed often
function A.busy()
    local b = B()
    return b.on and (#b.lines > 0 or #b.results > 0) or false
end

-- an agent_reply: the lines it answers; its words said (by its server); each call to the mod; an error
function A.onReply(o)
    local b = B()
    local kid = o.agent
    if type(kid) ~= "string" then return end
    if o.final == false then                        -- (a streaming agent's words so far: live words, as a player's)
        local text = type(o.text) == "string" and o.text or ""
        if text ~= "" then
            b.utt[kid] = b.utt[kid] or 1
            b.liveOn[kid] = true
            A.down("live", {kid = kid, utt = b.utt[kid], text = text})
        end
        return
    end
    local final = type(o.text) == "string" and o.text or ""
    local err = type(o.error) == "string" and o.error or ""
    if b.liveOn[kid] and (final == "" or err ~= "") then A.down("live", {kid = kid, utt = b.utt[kid] or 1, text = ""}) end
    b.liveOn[kid] = nil
    b.utt[kid] = (b.utt[kid] or 1) + 1
    local ids = {}
    for _, x in ipairs(type(o.ids) == "table" and o.ids or {}) do if tonumber(x) then ids[tonumber(x)] = true end end
    local answered = {}
    for i = #b.lines, 1, -1 do if ids[b.lines[i].id] then table.insert(answered, 1, table.remove(b.lines, i)) end end
    for i = #b.results, 1, -1 do                        -- (the follow-up came: their results are read)
        for _, x in ipairs(b.results[i].ids or {}) do if ids[x] then table.remove(b.results, i) break end end
    end
    if err == "cancelled" then return end
    if err == "unknown_agent" then                     -- (Koetama lost it: the definition and the lines again, once)
        if b.known then b.known[kid] = nil end
        b.sentAt = now()
        local again = false
        for _, l in ipairs(answered) do
            if not l.retried then
                b.n = b.n + 1
                l.id, l.received, l.retried, again = b.n, nil, true, true
                b.lines[#b.lines + 1] = l
            end
        end
        if again then
            if A.K then A.K.poke() end
            return
        end
    end
    local idList = {}
    for x in pairs(ids) do idList[#idList + 1] = x end
    table.sort(idList)
    local from, seen = {}, {}
    for _, x in ipairs(idList) do
        local f = b.lineFrom[x]
        if f and f ~= "" and not seen[f] then seen[f] = true from[#from + 1] = f end
    end
    if err ~= "" then
        A.down("error", {kid = kid, error = err, why = type(o.why) == "string" and o.why:sub(1, 500) or ""})
        return
    end
    if final ~= "" or #from > 0 then A.down("say", {kid = kid, text = final, from = from, lines = idList}) end
    for _, call in ipairs(type(o.calls) == "table" and o.calls or {}) do
        if type(call) == "table" and type(call.name) == "string" and type(call.call) == "string" then
            b.callIds[call.call] = idList
            A.down("call", {kid = kid, call = call.call, name = call.name, args = type(call.args) == "table" and call.args or {},
                from = from, lines = idList})
        end
    end
end

-- (the brain's game, every frame) lines no reply came for dropped; the server told now and then that this player's
-- language model is on (an admin's: the server checks)
function A.clientTick()
    local b, t = B(), now()
    for i = #b.lines, 1, -1 do
        if t - b.lines[i].t > A.LINE_LIFE then table.remove(b.lines, i) end
    end
    for i = #b.forget, 1, -1 do if t - b.forget[i].t > 3 then table.remove(b.forget, i) end end
    local K = A.K
    local on = K and K.online == true and b.llm == true or false
    if on and t - b.llmAt >= 10 then
        b.llmAt, b.llmSaid = t, true
        if A.CL then A.CL.rpc("llm", true) end
    elseif not on and b.llmSaid then
        b.llmSaid = nil
        if A.CL then A.CL.rpc("llm", false) end
    end
end

return A
