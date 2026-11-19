-- AGENTS: AI characters (or other jobs) a mod puts in the world, played by the large language model of an admin's
-- Koetama (Koetama's PROTOCOL.md "Large language models: agents", docs/agents-guide.md; the Teardown mod's agents.lua,
-- its API 17-18, ported - the user, 2026-10-25). Players talk to them as to anyone (typed or spoken, Whisper / Speak /
-- Yell near them, Global if they hear "all"); an agent's reply is said like a player's line (a bubble over it, its mode's
-- reach, garbled across the buffer, in the history, translated, captions); its function calls go to the mod, which checks
-- each, acts and answers.
--
-- A MOD CALLS (server; GLOBAL.ProxComms - README "Agents"):
--   ProxComms.agent(id, def)    define or change an agent (nil: remove). def: persona (required: who it is, up to 32 KB),
--                               name, entity (an inst: it hears and speaks where it is) or x / z, hears (near - the
--                               default - / named / engaged / all / none; API 6: in the buffer past the mode's range a
--                               line comes garbled, ⬚ for the letters not made out), mode (whisper / speak / yell /
--                               global),
--                               functions (a list of up to 64 {name, description, parameters}, or that list as JSON:
--                               API 3 - with an older Koetama only the first 16 go, ProxComms.agentfunctions()), state (a
--                               string or a function returning one: what it should know now), max_words, stream (false:
--                               no live words), character (false: not a character - the persona is the whole prompt),
--                               onCall(call) (return "ok: ..." / "error: ..." now, or nil and ProxComms.result later;
--                               API 5: return text, true - a final result: the turn ends, no follow-up request),
--                               (API 5) max_rounds (1-16: the most requests in one turn, follow-ups included),
--                               onReply(text, info), onError(code, why), (API 4) onSay(text, info) (a reply before it
--                               is said - return false: nothing is said, a string: that is said instead, nil: as it is;
--                               such an agent shows no live words: they would show what onSay may still hold back);
--                               (API 2, the Teardown mod's API 19-20 - the user, 2026-11-05) criteria (a list of up to 8
--                               {name, description}: each turn of players' lines scored 0-1 on each before it is
--                               answered) with onScores(scores, info) (return true: answer, false: skip, nil: decide
--                               later with ProxComms.decide - no decision in 3 s: answered) and onSkip(info);
--                               hearagents (1-50: it hears the other agents too, up to that many agent lines in a row)
--   ProxComms.event(id, text)   a line for it to hear from the game; .note(id, text): with its next line, once
--                               (API 2: .note(id, nil) takes them back; .noted(id): how many still wait);
--   ProxComms.say(id, text)     it says this without the model (the model hears of it with its next line);
--   ProxComms.forget(id)        its conversation starts over; .result(callId, text): a call's answer (API 5:
--                               .result(callId, text, {final = true}) - it ends the turn, no follow-up request);
--   ProxComms.finals()          (API 5) true: the brain's Koetama ends a turn on a final result and keeps to
--                               max_rounds (Koetama 0.5.16); else both are ignored. Replies' info.tokens (and a call's
--                               call.tokens): {input, output, cached} the request used, when Koetama says (0.5.16)
--   ProxComms.status()          "ready" / "busy" / "budget" / "error" / "off"
--   ProxComms.scores()          (API 2) true: the brain's Koetama scores turns (criteria do something);
--   ProxComms.decide(id, turn, answer)  (API 2) a decision on a scored turn (info.turn), when onScores returned nil
--   ProxComms.agentfunctions()  (API 3) the functions an agent may have: 16, or 32 once the brain's Koetama says so
--                               (0.5.15 and later); an agent's functions past that are not sent - put the important first
--   World events: proxcomms_agent_call (a call), proxcomms_said (its line said: .agent set), proxcomms_agent_error,
--   proxcomms_agent_skip (API 2: a scored turn the mod skipped).
--
-- SCORES (API 2): with criteria, a brain whose Koetama names "agent_scores" in its hello sends them in the definition;
-- Koetama scores each turn made only of players' (or agents') lines and context notes, and the turn waits for the mod's
-- decision (agent_scores -> the agent's shard -> onScores -> agent_decisions). Notes and "you said" lines go as context
-- (no reason by themselves to answer); a mod's event always gets an answer, never scored. A skipped turn: no words, no
-- engagement, its lines kept by Koetama for the next answered turn.
-- AGENTS HEARING AGENTS (API 2): a player's line or an event is count 0; an agent's line answering lines of count n is
-- n + 1 (a say: 1). An agent with hearagents N hears another agent's line (by its own hears rule, a moment after it is
-- said - time to read it) while its count is at most N, so their talk ends unless someone speaks again.
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
A.API = 8                       -- ProxComms.version (2: scores, agents hearing agents; 3: up to 32 functions;
                                -- 4: onSay; 5: final results, max_rounds, the tokens a reply used; 6: garbled lines;
                                -- 7: states up to 8 KB, ProxComms.statemax(); 8: personas up to 32 KB,
                                -- ProxComms.personamax(), up to 64 functions)
-- (API 3: an agent may have up to 32 functions from Koetama 0.5.15, whose hello says so - "agent_functions": 32; an older
-- one takes 16 and leaves out an agent with more, so the brain sends it the first 16. The user, 2026-11-15)
A.FUNCTIONS_MAX = 64            -- an agent's functions kept, at most (32 until API 8: the user, 2026-11-19,
                                -- "ok time to increase the functions to 64 then"; as many as the hello's agent_functions)
A.FUNCTIONS_OLD = 16            -- what a Koetama takes whose hello has no agent_functions (0.5.14 and older)
-- (API 7: an agent's state up to 8 KB from Koetama 0.5.18, whose hello says so - "agent_state": 8192; an older one
-- drops a state over 2048 bytes whole, so it is cut to that. The user's AI Villagers, 2026-11-18: "Around you", 50 kinds)
A.STATE_MAX = 8192              -- an agent's state kept, at most
A.STATE_OLD = 2048              -- what a Koetama takes whose hello has no agent_state (0.5.17 and older)
-- (API 8: a persona up to 32 KB from a Koetama whose hello says so - "agent_persona": 32768; an older one leaves out
-- an agent whose persona is over 8192 bytes, so the brain sends it the first 8192. The user, 2026-11-19: "I think 8kb
-- is still too small for rules. maybe it should be 32kb")
A.PERSONA_MAX = 32768           -- an agent's persona kept, at most
A.PERSONA_OLD = 8192            -- what a Koetama takes whose hello has no agent_persona
A.DEF_BUDGET_BIG = 160 * 1024   -- the definitions in one feed to a Koetama taking 256 KB feeds (0.5.17 and later)
A.LINE_LIFE = 60                -- s a line waits for its reply (the brain)
A.LINES_MAX = 32
A.SEND_FOR = 5                  -- (no longer used: definitions go until a feed carrying them is answered)
-- (a feed is at most 64 KB - Koetama answers a bigger one 413 and takes none of it. The definitions Koetama lacks go
-- over as many feeds as they need, at most DEF_BUDGET of them in one, the longest unsent first; the rest of the feed
-- (lines with their states, results) has the room left. The user's AI Villagers, 2026-11-17: four of ~16.5 KB each in
-- every feed made it ~70 KB - refused every time, so only the one villager defined alone ever got through)
A.DEF_BUDGET = 36 * 1024
A.ENGAGED = 30                  -- s a player it answered (or who named it) stays heard by an agent that hears "engaged"
A.CAND_LIFE = 30                -- s a brain candidate is kept without being heard again
A.CALL_LIFE = 30                -- s a call waits for the mod's answer
A.REPLY_MAX = 600
A.HEARS = {near = true, named = true, engaged = true, all = true, none = true}
A.MODES = {whisper = "w", w = "w", speak = "s", s = "s", yell = "y", shout = "y", y = "y", global = "g", g = "g"}
A.PREFIX = "agent:"             -- an agent's speaker id in lines (uid "agent:<kid>")
A.HEAR_AGENTS_MAX = 50          -- hearagents at most
-- (s before other agents hear an agent's line: time for the players to read it - about 12 characters a second; was
-- 1 + 0.04 a character, at most 4 s: the user, 2026-11-06, "the creatures speak too fast and is difficult to follow")
A.PAUSE_MIN, A.PAUSE_PER_CHAR, A.PAUSE_MAX = 2.5, 0.085, 10
A.LATER_MAX = 32                -- agents' lines waiting to be heard by other agents, at most

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
A.scores = false       -- the brain's Koetama scores turns (its "caps", on every shard)
A.functionsMax = A.FUNCTIONS_OLD   -- the functions an agent may have, as the brain's Koetama says (its "caps")
A.finalOk = false      -- the brain's Koetama ends turns on final results, keeps to max_rounds (its "caps", API 5)
A.stateMax = A.STATE_OLD   -- an agent's state's most bytes, as the brain's Koetama says (its "caps", API 7)
A.personaMax = A.PERSONA_OLD   -- an agent's persona's most bytes, as the brain's Koetama says (its "caps", API 8)
A.ROUNDS_MAX = 16
A.later = {}           -- agents' lines other agents will hear: {due, uid, name, text, mode, x, z, depth, by}

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

-- (API 3) the functions an agent may have: 16 until the brain's Koetama says more (0.5.15 and later: 32). An agent
-- defined with more has only its first that many sent (put the ones that matter most first)
function A.finals()
    return A.owner ~= nil and A.finalOk == true
end

function A.agentFunctions()
    return A.functionsMax
end

-- (API 7) an agent's state's most bytes: 2048 until the brain's Koetama says more (0.5.18 and later: 8192). A longer
-- state is cut there (put what matters most first)
function A.stateBytes()
    return A.stateMax
end

-- (API 8) an agent's persona's most bytes: 8192 until the brain's Koetama says more (32768). A longer one keeps
-- up to 32 KB here, and the brain sends the first personamax() of it (put what matters most first)
function A.personaBytes()
    return A.personaMax
end

-- (API) the brain's Koetama scores turns: an agent's criteria do something
function A.scoring()
    return A.owner ~= nil and A.scores == true
end

-- a definition's criteria as Koetama takes them: 1-8 {name (a-z 0-9 _, at most 32, each once), description (cut to
-- 300 bytes)}; nil and why when it isn't that (nil, nil: none given)
local function criteriaOf(c)
    if c == nil then return nil end
    if type(c) == "string" then c = J.decode(c) end
    if type(c) ~= "table" or #c == 0 or #c > 8 then return nil, "criteria: a list of 1 to 8 {name, description}" end
    local out, seen = J.array({}), {}
    for _, x in ipairs(c) do
        local n, d = type(x) == "table" and x.name, type(x) == "table" and x.description
        if type(n) ~= "string" or not n:find("^[a-z0-9_]+$") or #n > 32 or seen[n] then
            return nil, "criteria: a bad or repeated name (a-z 0-9 _, at most 32)"
        end
        if type(d) ~= "string" or d == "" then return nil, "criteria: " .. n .. " has no description" end
        seen[n] = true
        out[#out + 1] = {name = n, description = T.cutBytes(d, 300)}
    end
    return out
end

-- a definition's functions as a list (a Lua list, or JSON): empty "required" lists dropped (they would go as {})
local function functionsOf(f)
    if type(f) == "string" then f = J.decode(f) end
    if type(f) ~= "table" then return nil end
    local out = J.array({})
    for _, fn in ipairs(f) do
        if type(fn) == "table" and type(fn.name) == "string" and #out < A.FUNCTIONS_MAX then
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
    if a.criteria then d.criteria = a.criteria end
    if a.max_rounds then d.max_rounds = a.max_rounds end
    return d
end

-- (server) to the brain: on this shard, straight to its game; else through the shards (the one it is on hands it on)
-- (a message to the brain over A.PART goes in parts, put together again by the brain (A.onUp "part"). DST cuts a mod
-- RPC's long string, silently: the in-game test of 2026-11-19 (devtest SCENE=bigdef) - a definition of 98889 bytes
-- (a 32 KB persona, 64 functions) arrived as its first 33353, no JSON, so never; in 12 KB parts, whole)
A.PART = 12 * 1024
A.PART_LIFE = 30        -- s the brain keeps the parts of a message not yet whole
A.partN = 0

-- s cut into pieces of at most `most` bytes, each at a character's start (DST's strings: never half a character)
function A.pieces(s, most)
    local out, i = {}, 1
    while i <= #s do
        local j = math.min(#s, i + most - 1)
        while j < #s and j > i and s:byte(j + 1) >= 0x80 and s:byte(j + 1) < 0xC0 do j = j - 1 end
        out[#out + 1] = s:sub(i, j)
        i = j + 1
    end
    return out
end

local function upRaw(kind, s)
    if A.isLocal(A.owner) then
        SendModRPCToClient(clientRPC("agent_up"), A.owner, kind, s)
    else
        toShards("agent_up", kind, s)
    end
end

function A.up(kind, t)
    if not A.owner then return false end
    local s = J.encode(t)
    if #s <= A.PART then
        upRaw(kind, s)
        return true
    end
    A.partN = A.partN + 1
    local id = A.shard() .. "." .. A.partN
    local ps = A.pieces(s, A.PART)
    for i, p in ipairs(ps) do upRaw("part", id .. "|" .. i .. "|" .. #ps .. "|" .. kind .. "|" .. p) end
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
    a.persona = T.cutBytes(def.persona, A.PERSONA_MAX)
    a.name = T.clean(type(def.name) == "string" and def.name or id, C.NAME_LEN)
    if a.name == "" then a.name = id end
    a.entity = def.entity
    a.x, a.z = tonumber(def.x), tonumber(def.z)
    a.hears = A.HEARS[def.hears] and def.hears or "near"
    a.mode = A.MODES[type(def.mode) == "string" and def.mode:lower() or ""] or "s"
    a.functions = functionsOf(def.functions)
    a.state = def.state
    a.max_words = math.max(1, math.min(1000, math.floor(tonumber(def.max_words) or 80)))
    local mr = tonumber(def.max_rounds)                 -- (API 5: absent - no limit)
    a.max_rounds = mr and math.max(1, math.min(A.ROUNDS_MAX, math.floor(mr))) or nil
    a.stream = def.stream ~= false
    a.character = def.character ~= false
    a.onCall, a.onReply, a.onError = def.onCall, def.onReply, def.onError
    a.onSay = def.onSay
    a.onScores, a.onSkip = def.onScores, def.onSkip
    local crit, why = criteriaOf(def.criteria)
    a.criteria = crit
    a.hearagents = math.max(0, math.min(A.HEAR_AGENTS_MAX, math.floor(tonumber(def.hearagents) or 0)))
    a.skipn = a.skipn or 0
    A.agents[id] = a
    local sig = J.encode(defOf(a))
    if sig ~= a.sig then
        a.sig = sig
        A.up("def", defOf(a))
    end
    if why then print("[ProxComms] agent " .. id .. ": " .. why .. " - nothing is scored") end
    return true, why and (why .. " - nothing is scored") or nil
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

-- the prefab of the entity it speaks from ("" for none): each line and live words carry it, so the players' games find
-- that entity near where it was said and keep its bubble over it as it moves (CL.trackAgent)
function A.prefabOf(a)
    local e = a.entity
    if e and e.prefab and (not e.IsValid or e:IsValid()) then return tostring(e.prefab) end
    return ""
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
    return T.cutBytes(s, A.stateMax)
end

-- (server) a line for an agent: what it said without the model and the mod's note first (as context events, once
-- each: what it should know, no reason by themselves to answer - a scored turn stays scored). depth: the line's count
-- of agent lines in a row (0: a player's, an event)
function A.lineUp(a, text, from, depth)
    text = T.cutBytes(tostring(text or ""), 400)
    if text == "" then return end
    for _, said in ipairs(a.said) do
        A.up("line", {kid = a.kid, text = T.cutBytes("you said: " .. said, 400), context = true})
    end
    a.said = {}
    for _, note in ipairs(a.notes) do A.up("line", {kid = a.kid, text = note, context = true}) end
    a.notes = {}
    A.up("line", {kid = a.kid, text = text, from = from, state = stateOf(a), depth = depth or 0})
end

-- (a line's garble seed: the same line garbles the same for every agent at one distance, as for players)
local function seedOf(uid, text)
    local h = #text
    for i = 1, math.min(#text, 64) do h = (h * 31 + text:byte(i)) % 1000003 end
    for i = 1, #uid do h = (h * 31 + uid:byte(i)) % 1000003 end
    return h
end

-- (server) a player (uid, name) said text in mode at x, z: the agents that hear it get it. depth (API 2): an agent's
-- line (uid "agent:<kid>", by its id) - its count of agent lines in a row; only the others whose hearagents reaches it
function A.hear(uid, name, text, mode, x, z, depth, by)
    if not A.owner or type(text) ~= "string" or text == "" then return end
    depth = depth or 0
    local t = now()
    for id, a in pairs(A.agents) do
        if depth == 0 or (id ~= by and a.hearagents >= depth) then
            local hear = a.hears == "all"
            local named = (a.hears == "named" or a.hears == "engaged") and A.named(text, a.name)
            local eng = A.eng[id] and A.eng[id][uid]
            local engaged = a.hears == "engaged" and eng ~= nil and t - eng <= A.ENGAGED
            local heard = text
            if (a.hears == "near" or a.hears == "named" or a.hears == "engaged") and mode ~= "g" and x and z then
                -- (API 6: as a player there reads it - whole within the mode's range, garbled (⬚, T.GARBLE) in the
                --  buffer out to its reach, nothing past it. The user, 2026-11-17, for the AI Villagers: "squares in
                --  speeches mean they are not close enough to hear the full speech" - they never saw one. Its name is
                --  looked for in what it made out: a name lost in the garble is not heard)
                hear = false
                local ax, az = A.posOf(a)
                local r = A.S.ranges[mode] or A.S.ranges.s
                if ax ~= nil then
                    local d = math.sqrt((ax - x) ^ 2 + (az - z) ^ 2)
                    if d <= r[1] + 1 then
                        hear = true
                    elseif d <= r[2] then
                        local f = math.max(0, math.min(1, (r[2] - d) / math.max(0.5, r[2] - r[1]))) * C.GARBLE_MAX
                        heard = T.garble(text, f, seedOf(uid, text))
                        hear = true
                    end
                end
                if hear and a.hears ~= "near" then
                    named = A.named(heard, a.name)
                    hear = named or engaged
                end
            end
            if hear then
                if named then A.eng[id] = A.eng[id] or {} A.eng[id][uid] = t end
                A.lineUp(a, heard, {id = uid, name = name}, depth)
            end
        end
    end
end

-- (server, API 2) an agent's line said: the other agents that hear agents get it after a pause to read it
function A.toAgents(a, text, depth, x, z)
    local any = false
    for id, o in pairs(A.agents) do
        if id ~= a.id and o.hearagents >= depth then any = true break end
    end
    if not any then return end
    local wait = math.max(A.PAUSE_MIN, math.min(A.PAUSE_MAX, #T.units(text) * A.PAUSE_PER_CHAR))
    A.later[#A.later + 1] = {due = now() + wait, uid = A.PREFIX .. a.kid, name = a.name, text = text, mode = a.mode,
        x = x, z = z, depth = depth, by = a.id}
    while #A.later > A.LATER_MAX do table.remove(A.later, 1) end
end

-- (server) the agents' lines read by now: heard
function A.laterTick()
    local t, i = now(), 1
    while A.later[i] do
        local l = A.later[i]
        if t >= l.due then
            table.remove(A.later, i)
            A.hear(l.uid, l.name, l.text, l.mode, l.x, l.z, l.depth, l.by)
        else
            i = i + 1
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
        SendModRPCToClient(clientRPC("line"), to, uid, a.name, text, mode, A.S.lineId, x or 0, z or 0, false, 0, "", 0,
            A.prefabOf(a))
    end
    local heard = to and #to or #(AllPlayers or {})
    info = info or {}
    info.heard = heard
    if info.depth then A.toAgents(a, text, info.depth, x, z) end
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
            A.deliver(a, line, {from = {}, lines = {}, scripted = true, depth = 1})
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

-- (API) what it should know with its next line, once; (API 2) text nil: the notes waiting taken back (a mod that sends
-- them as an event instead when no line came in time)
function A.note(id, text)
    local a = A.agents[id]
    if not a then return false end
    if text == nil then a.notes = {} return true end
    if type(text) ~= "string" or text == "" then return false end
    a.notes[#a.notes + 1] = T.cutBytes(text, 400)
    while #a.notes > 8 do table.remove(a.notes, 1) end
    return true
end

-- (API 2) how many of its notes still wait for a line (0: a line took them)
function A.noted(id)
    local a = A.agents[id]
    return a and #a.notes or 0
end

function A.forget(id)
    local a = A.agents[id]
    if not a then return false end
    A.up("forget", {kid = a.kid})
    return true
end

-- (API) a call's answer ("ok: ..." / "error: ..."), back to the model
-- (API 5: opts {final = true} (or true) - a final result: the turn ends with it, no follow-up request, when the brain's
-- Koetama does that - ProxComms.finals(); an older one asks the model again as before)
function A.result(callId, text, opts)
    local c = A.calls[callId]
    if not c or type(text) ~= "string" then return false end
    A.calls[callId] = nil
    local final = opts == true or (type(opts) == "table" and opts.final == true)
    A.up("result", {call = callId, result = T.cutBytes(text, 1000), final = final or nil})
    return true
end

-- (API 5) a reply's tokens as the mod gets them: {input, output, cached}, or nil (an older Koetama)
local function tokensOf(t)
    if type(t) ~= "table" or not tonumber(t.input) then return nil end
    return {input = tonumber(t.input), output = tonumber(t.output) or 0, cached = tonumber(t.cached) or 0}
end

-- (API 2) the mod's decision on a scored turn (onScores' info.turn): answer it (true) or skip it
function A.decide(id, turn, answer)
    local a = A.agents[id]
    if not a or not tonumber(turn) then return false end
    A.up("decide", {kid = a.kid, turn = tonumber(turn), answer = answer == true})
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
    if kind == "caps" then                              -- (API 2: what the brain's Koetama does)
        A.scores = t.scores == true
        local n = math.floor(tonumber(t.functions) or A.FUNCTIONS_OLD)
        A.functionsMax = math.max(A.FUNCTIONS_OLD, math.min(A.FUNCTIONS_MAX, n))     -- (API 3)
        A.finalOk = t.final == true                                                  -- (API 5)
        local sb = math.floor(tonumber(t.state) or A.STATE_OLD)
        A.stateMax = math.max(A.STATE_OLD, math.min(A.STATE_MAX, sb))                -- (API 7)
        local pb = math.floor(tonumber(t.persona) or A.PERSONA_OLD)
        A.personaMax = math.max(A.PERSONA_OLD, math.min(A.PERSONA_MAX, pb))          -- (API 8)
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
        local text = t.text
        -- (onSay(text, info), for the AI Villagers, 2026-11-16: the mod sees a reply before it is said - return false:
        --  nothing is said; a string: that is said instead. A model told to stay silent says "NO WORDS." aloud)
        if type(text) == "string" and text ~= "" and type(a.onSay) == "function" then
            local ok, r = pcall(a.onSay, text, {from = from, lines = lines, tokens = tokensOf(t.tokens)})
            if ok and r == false then text = "" elseif ok and type(r) == "string" then text = r end
        end
        if type(text) == "string" and text ~= "" then
            local depth = math.max(1, math.min(1000, math.floor(tonumber(t.depth) or 1)))
            A.deliver(a, text, {from = from, lines = lines, depth = depth, tokens = tokensOf(t.tokens)})
        end
    elseif kind == "skip" then                          -- (API 2: a scored turn the mod skipped - nothing said)
        a.skipn = (a.skipn or 0) + 1
        local info = {from = from, lines = lines}
        if type(a.onSkip) == "function" then pcall(a.onSkip, info) end
        if TheWorld then TheWorld:PushEvent("proxcomms_agent_skip", {agent = id, from = from, lines = lines}) end
    elseif kind == "scores" then                        -- (API 2: a turn scored; the mod decides)
        local turn = tonumber(t.turn)
        if not turn then return end
        local scores = {}
        for k, v in pairs(type(t.scores) == "table" and t.scores or {}) do
            if type(k) == "string" and tonumber(v) then scores[k] = math.max(0, math.min(1, tonumber(v))) end
        end
        local info = {turn = turn, from = from, lines = lines, text = type(t.text) == "table" and t.text or {}}
        if type(a.onScores) == "function" then
            local ok, r = pcall(a.onScores, scores, info)
            if ok and (r == true or r == false) then A.decide(id, turn, r)
            elseif not ok then print("[ProxComms] agent " .. id .. " onScores: " .. tostring(r)) end
        end
    elseif kind == "live" then
        local x, z = A.posOf(a)
        if a.mode == "g" or not x or type(t.text) ~= "string" then return end
        if type(a.onSay) == "function" then return end  -- (API 4: its words are shown once onSay passed them)
        SendModRPCToClient(clientRPC("live"), A.S.near(x, z, A.S.reach(a.mode)), A.PREFIX .. a.kid, a.name,
            tonumber(t.utt) or 1, T.clean(T.tail(t.text, 200), 200), a.mode, x, z, A.prefabOf(a))
    elseif kind == "call" then
        if type(t.call) ~= "string" or type(t.name) ~= "string" then return end
        A.calls[t.call] = {id = id, t = now()}
        local call = {id = t.call, agent = id, name = t.name, args = type(t.args) == "table" and t.args or {},
            from = from, lines = lines, tokens = tokensOf(t.tokens)}
        if TheWorld then TheWorld:PushEvent("proxcomms_agent_call", call) end
        if type(a.onCall) == "function" then
            local ok, r, fin = pcall(a.onCall, call)
            if ok and type(r) == "string" then A.result(t.call, r, fin == true)
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
    if kind == "status" or kind == "sync" or kind == "caps" then
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
    if kind == "status" or kind == "sync" or kind == "caps" then A.handle(kind, t) return end
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
    if not uid then A.state, A.scores, A.stateMax, A.personaMax = "ready", false, A.STATE_OLD, A.PERSONA_OLD end
end

-- (server, every second) the master's choice kept fresh; calls the mod never answered dropped
function A.serverTick()
    if A.S.isMaster() then A.elect() end
    A.laterTick()
    local t = now()
    for k, c in pairs(A.calls) do
        if t - c.t > A.CALL_LIFE then A.calls[k] = nil end
    end
end

-- ==================================================================================== THE BRAIN (the admin's game)

A.brain = {on = false, defs = {}, lines = {}, results = {}, forget = {}, known = nil, sentAt = -1e9, n = 0,
    lineFrom = {}, liveOn = {}, utt = {}, callIds = {}, llmAt = -1e9, llmSaid = nil,
    scores = false, scorePending = {}, decisions = {}, lineDepth = {}}   -- (API 2: scores, decisions, agent lines' counts)

local function B() return A.brain end

function A.down(kind, t)
    if A.CL then A.CL.rpc("agent_down", kind, J.encode(t or {})) end
end

-- (API 2) what this brain's Koetama does, to every shard
local function sendCaps()
    local b = B()
    A.down("caps", {scores = b.scores == true and b.llm == true, functions = b.maxFn or A.FUNCTIONS_OLD,
        final = b.final == true and b.llm == true, state = b.maxState or A.STATE_OLD,
        persona = b.maxPersona or A.PERSONA_OLD})
end

-- (client RPC) this game is the brain now (or no longer)
function A.onOwner(on)
    local b = B()
    b.on = on == true
    if b.on then
        b.sentAt, b.known = now(), nil
        A.down("sync", {})
        sendCaps()
    else
        b.defs, b.lines, b.results, b.forget = {}, {}, {}, {}
        b.scorePending, b.decisions = {}, {}
    end
end

-- (client RPC) from an agent's server
function A.onUp(kind, s)
    local b = B()
    if not b.on or type(kind) ~= "string" or type(s) ~= "string" then return end
    if kind == "part" then                              -- (a long message's part: A.up)
        local id, i, n, k, p = s:match("^([^|]+)|(%d+)|(%d+)|([^|]+)|(.*)$")
        i, n = tonumber(i), tonumber(n)
        if not id or not i or not n or i < 1 or i > n or n > 64 or k == "part" then return end
        b.parts = b.parts or {}
        local t = now()
        for pid, m in pairs(b.parts) do if t - m.t > A.PART_LIFE then b.parts[pid] = nil end end
        local m = b.parts[id]
        if not m or m.n ~= n or m.kind ~= k then m = {n = n, kind = k, got = 0, ps = {}, t = t} b.parts[id] = m end
        if m.ps[i] == nil then m.ps[i], m.got = p, m.got + 1 end
        m.t = t
        if m.got < n then return end
        b.parts[id] = nil
        return A.onUp(k, table.concat(m.ps))
    end
    local t = J.decode(s)
    if type(t) ~= "table" or type(t.kid) ~= "string" and kind ~= "result" then return end
    if kind == "def" then
        local sig = s
        local d = b.defs[t.kid]
        if not d or d.sig ~= sig then
            local def = {id = t.kid, version = (d and d.def.version or 0) + 1, persona = t.persona,
                character = t.character ~= false, stream = t.stream ~= false, max_words = t.max_words, functions = t.functions,
                max_rounds = tonumber(t.max_rounds),
                criteria = type(t.criteria) == "table" and #t.criteria > 0 and t.criteria or nil}
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
        local context = t.context == true and from == nil or nil
        b.lineDepth[b.n] = not context and math.max(0, math.floor(tonumber(t.depth) or 0)) or nil   -- (notes don't count)
        b.lineDepth[b.n - 300] = nil
        b.lines[#b.lines + 1] = {id = b.n, agent = t.kid, text = t.text, from = from, state = t.state, t = now(),
            context = context}
        while #b.lines > A.LINES_MAX do table.remove(b.lines, 1) end
        if A.K then A.K.poke() end
    elseif kind == "forget" then
        b.forget[#b.forget + 1] = {id = t.kid, t = now()}
        if A.K then A.K.poke() end
    elseif kind == "result" then
        if type(t.call) == "string" then
            b.results[#b.results + 1] = {call = t.call, result = tostring(t.result or ""), ids = b.callIds[t.call],
                final = t.final == true}
            b.callIds[t.call] = nil
            if A.K then A.K.poke() end
        end
    elseif kind == "decide" then                        -- (API 2: the mod's decision on the turn waiting)
        local sp = b.scorePending[t.kid]
        if sp and tonumber(t.turn) == sp.turn then
            b.scorePending[t.kid] = nil
            b.decisions[#b.decisions + 1] = {agent = t.kid, turn = sp.turn, answer = t.answer == true, ids = sp.ids, t = now()}
            while #b.decisions > 32 do table.remove(b.decisions, 1) end
            if A.K then A.K.poke() end
        end
    end
end

-- (the brain's Koetama, API 2) agent_scores: a turn of an agent's lines scored on its criteria - to the agent's shard,
-- whose mod decides (what was said, by whom, goes with it)
function A.onScores(o)
    local b = B()
    local kid, turn = o.agent, tonumber(o.turn)
    if type(kid) ~= "string" or not b.defs[kid] or not turn then return end
    local ids, want = {}, {}
    for _, x in ipairs(type(o.ids) == "table" and o.ids or {}) do
        if tonumber(x) then ids[#ids + 1] = tonumber(x) want[tonumber(x)] = true end
    end
    table.sort(ids)
    local from, seen, text = {}, {}, {}
    for _, l in ipairs(b.lines) do
        if want[l.id] then
            local f = b.lineFrom[l.id]
            if f and f ~= "" and not seen[f] then seen[f] = true from[#from + 1] = f end
            text[#text + 1] = l.from and ((l.from.name or "?") .. ": " .. l.text) or ("[" .. l.text .. "]")
        end
    end
    local scores = {}
    for k, v in pairs(type(o.scores) == "table" and o.scores or {}) do
        if type(k) == "string" and k:find("^[a-z0-9_]+$") and tonumber(v) then scores[k] = math.max(0, math.min(1, tonumber(v))) end
    end
    b.scorePending[kid] = {turn = turn, ids = ids, t = now()}
    A.down("scores", {kid = kid, turn = turn, scores = scores, from = from, lines = ids, text = text})
end

-- (the brain's Koetama) its hello: definitions again (it keeps them only for its session); the server told
function A.onHello(features, hello)
    local b = B()
    b.sentAt, b.known = now(), nil
    b.llm = features and features.llm == true or false
    b.scores = features and features.agent_scores == true or false     -- (API 2: Koetama 0.5.14)
    local n = math.floor(tonumber(type(hello) == "table" and hello.agent_functions) or A.FUNCTIONS_OLD)
    b.maxFn = math.max(1, math.min(A.FUNCTIONS_MAX, n))                -- (API 3: Koetama 0.5.15 says 32)
    b.cutSaid = {}
    b.final = features and features.agent_final == true or false       -- (API 5: Koetama 0.5.16)
    local sb = math.floor(tonumber(type(hello) == "table" and hello.agent_state) or A.STATE_OLD)
    b.maxState = math.max(1, math.min(A.STATE_MAX, sb))                -- (API 7: Koetama 0.5.18 says 8192)
    local pb = math.floor(tonumber(type(hello) == "table" and hello.agent_persona) or A.PERSONA_OLD)
    b.maxPersona = math.max(1, math.min(A.PERSONA_MAX, pb))            -- (API 8)
    local v = type(hello) == "table" and tostring(hello.version or "") or ""
    b.bigFeeds = (type(hello) == "table" and hello.agent_state ~= nil) or (v ~= "" and not C.olderThan(v, "0.5.17"))
    b.scorePending, b.decisions = {}, {}         -- (a new Koetama numbers its turns afresh)
    b.llmAt = -1e9                               -- (said to the server at once)
    if b.on then sendCaps() end
end

function A.onKnown(o)
    local known = {}
    for _, a in ipairs(type(o.agents) == "table" and o.agents or {}) do
        if type(a) == "table" and type(a.id) == "string" and tonumber(a.version) then known[a.id] = tonumber(a.version) end
    end
    B().known = known
end

-- (K.post) the feed went: answered (ok) - its definitions are Koetama's now; or not - they go again
function A.fed(ok)
    local b = B()
    if ok then
        local t = now()
        for _, d in ipairs(b.inFlight or {}) do d.okAt = t end
    end
    b.inFlight = {}
end

function A.onReceived(o)
    local b = B()
    local got, calls = {}, {}
    for _, x in ipairs(type(o.to_agent) == "table" and o.to_agent or {}) do if tonumber(x) then got[tonumber(x)] = true end end
    for _, x in ipairs(type(o.agent_results) == "table" and o.agent_results or {}) do if type(x) == "string" then calls[x] = true end end
    for _, l in ipairs(b.lines) do if got[l.id] then l.received = true end end
    for _, r in ipairs(b.results) do if calls[r.call] then r.received = true end end
    local turns = {}
    for _, x in ipairs(type(o.agent_decisions) == "table" and o.agent_decisions or {}) do if tonumber(x) then turns[tonumber(x)] = true end end
    for _, x in ipairs(b.decisions) do if turns[x.turn] then x.received = true end end
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
    -- (wanted: Koetama lacks it or has an older version - or, before its agents_known, not yet in an answered feed
    --  since the hello or the last change; one just answered waits 3 s for agents_known to catch up)
    local cands = {}
    for _, d in pairs(b.defs) do
        local want
        if b.known then
            local kv = b.known[d.def.id]
            want = (kv == nil or kv < d.def.version) and not (d.okAt and d.okAt >= b.sentAt and t - d.okAt < 3)
        else
            want = (d.okAt or -1e9) < b.sentAt
        end
        if want then cands[#cands + 1] = d end
    end
    table.sort(cands, function(x, y)
        local tx, ty = x.tryAt or -1e9, y.tryAt or -1e9
        if tx ~= ty then return tx < ty end
        return x.def.id < y.def.id
    end)
    local bytes = 0
    b.inFlight = {}
    for _, d in ipairs(cands) do
        if #defs >= 32 then break end
        do
            local def = d.def
            local maxFn = b.maxFn or A.FUNCTIONS_OLD
            local cut = type(def.functions) == "table" and #def.functions > maxFn
            local maxP = b.maxPersona or A.PERSONA_OLD
            local long = type(def.persona) == "string" and #def.persona > maxP
            if (def.criteria and not b.scores) or cut or long or (def.max_rounds and not b.final) then
                def = {}
                for k, v in pairs(d.def) do def[k] = v end
                if not b.scores then def.criteria = nil end    -- (criteria only for a Koetama that scores)
                if not b.final then def.max_rounds = nil end   -- (API 5: max_rounds only for one that keeps to it)
            end
            if long then             -- (API 8: a longer persona than this Koetama takes would leave the agent out)
                def.persona = T.cutBytes(d.def.persona, maxP)
                b.cutSaid = b.cutSaid or {}
                if not b.cutSaid["p:" .. def.id] then
                    b.cutSaid["p:" .. def.id] = true
                    print(string.format("[ProxComms] agent %s has a persona of %d bytes; this Koetama takes %d - the "
                        .. "first %d sent", def.id, #d.def.persona, maxP, maxP))
                end
            end
            if cut then              -- (API 3: more functions than this Koetama takes would leave the agent out)
                local fns = J.array({})
                for i = 1, maxFn do fns[i] = d.def.functions[i] end
                def.functions = fns
                b.cutSaid = b.cutSaid or {}
                if not b.cutSaid[def.id] then
                    b.cutSaid[def.id] = true
                    print(string.format("[ProxComms] agent %s has %d functions; this Koetama takes %d - the first %d "
                        .. "sent (newer Koetamas take more)", def.id, #d.def.functions, maxFn, maxFn))
                end
            end
            -- (its size as sent - kept while the definition and what this Koetama takes stay the same)
            local key = tostring(b.scores) .. tostring(b.final) .. tostring(b.maxFn) .. tostring(maxP)
            if d.sizeKey ~= key then d.sizeKey, d.size = key, #J.encode(def) end
            if #defs > 0 and bytes + d.size > (b.bigFeeds and A.DEF_BUDGET_BIG or A.DEF_BUDGET) then break end
            defs[#defs + 1] = def
            bytes = bytes + d.size
            d.tryAt = t
            b.inFlight[#b.inFlight + 1] = d
        end
    end
    if #defs > 0 then f.agents = defs end
    local lines = J.array({})
    for _, l in ipairs(b.lines) do
        if #lines < 8 and not l.received then
            local st = type(l.state) == "string" and T.cutBytes(l.state, b.maxState or A.STATE_OLD) or nil   -- (a shard's caps late)
            lines[#lines + 1] = {id = l.id, agent = l.agent, text = l.text, from = l.from, state = st, context = l.context}
        end
    end
    if #lines > 0 then f.to_agent = lines end
    local res = J.array({})
    for _, r in ipairs(b.results) do                        -- (API 5: final only to a Koetama that ends turns on it)
        if not r.received then res[#res + 1] = {call = r.call, result = r.result, final = (r.final and b.final) or nil} end
    end
    if #res > 0 then f.agent_results = res end
    local dec = J.array({})                                -- (API 2: the mods' decisions on scored turns)
    for _, x in ipairs(b.decisions) do
        if not x.received and #dec < 32 then dec[#dec + 1] = {agent = x.agent, turn = x.turn, answer = x.answer} end
    end
    if #dec > 0 then f.agent_decisions = dec end
    local fg = J.array({})
    for _, x in ipairs(b.forget) do fg[#fg + 1] = x.id end
    if #fg > 0 then f.agent_forget = fg end
end

-- (K.active) lines or results waiting: feed often
function A.busy()
    local b = B()
    return b.on and (#b.lines > 0 or #b.results > 0 or #b.decisions > 0) or false
end

-- a model's words without its [bracketed] asides: brackets are how the game's events reach it ("[Spider hits you!]") and
-- a model copies them (the user, 2026-11-06, seen in game: "[Gilbert is a friend, not me] Blub! ..."); a bracket still
-- open at the end of live words is cut too. A mod's own lines (ProxComms.say) are said as they are.
function A.noAsides(text)
    text = text:gsub("%b[]", ""):gsub("%[[^%]]*$", "")
    return (text:gsub("%s%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+([,.!?;:])", "%1"))
end

-- an agent_reply: the lines it answers; its words said (by its server); each call to the mod; an error
function A.onReply(o)
    local b = B()
    local kid = o.agent
    if type(kid) ~= "string" then return end
    if o.final == false then                        -- (a streaming agent's words so far: live words, as a player's)
        local text = type(o.text) == "string" and A.noAsides(o.text) or ""
        if text ~= "" then
            b.utt[kid] = b.utt[kid] or 1
            b.liveOn[kid] = true
            A.down("live", {kid = kid, utt = b.utt[kid], text = text})
        end
        return
    end
    local final = type(o.text) == "string" and A.noAsides(o.text) or ""
    local err = type(o.error) == "string" and o.error or ""
    if b.liveOn[kid] and (final == "" or err ~= "") then A.down("live", {kid = kid, utt = b.utt[kid] or 1, text = ""}) end
    b.liveOn[kid] = nil
    b.utt[kid] = (b.utt[kid] or 1) + 1
    local ids = {}
    for _, x in ipairs(type(o.ids) == "table" and o.ids or {}) do if tonumber(x) then ids[tonumber(x)] = true end end
    local answered = {}
    for i = #b.lines, 1, -1 do if ids[b.lines[i].id] then table.insert(answered, 1, table.remove(b.lines, i)) end end
    local function done(x) for _, i in ipairs(x.ids or {}) do if ids[i] then return true end end end
    for i = #b.decisions, 1, -1 do if done(b.decisions[i]) then table.remove(b.decisions, i) end end   -- (its turn is
    for k, sp in pairs(b.scorePending) do if done(sp) then b.scorePending[k] = nil end end            --  over)
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
                b.lineFrom[b.n], b.lineDepth[b.n] = b.lineFrom[l.id], b.lineDepth[l.id]   -- (who said it, its count: kept)
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
    if o.skipped == true then                       -- (API 2: the mod skipped this scored turn - nothing said, and it
        A.down("skip", {kid = kid, from = from, lines = idList})   --  isn't engaged with them for it)
        return
    end
    local depth                                     -- (its count of agent lines in a row: the lowest it answers + 1)
    for _, x in ipairs(idList) do
        local ld = b.lineDepth[x]
        if ld and (not depth or ld < depth) then depth = ld end
    end
    depth = (depth or 0) + 1
    local tok = tonumber(o.tokens_in) and {input = tonumber(o.tokens_in), output = tonumber(o.tokens_out) or 0,
        cached = tonumber(o.tokens_cached) or 0} or nil                -- (API 5: Koetama 0.5.16)
    if final ~= "" or #from > 0 then
        A.down("say", {kid = kid, text = final, from = from, lines = idList, depth = depth, tokens = tok})
    end
    for _, call in ipairs(type(o.calls) == "table" and o.calls or {}) do
        if type(call) == "table" and type(call.name) == "string" and type(call.call) == "string" then
            b.callIds[call.call] = idList
            A.down("call", {kid = kid, call = call.call, name = call.name, args = type(call.args) == "table" and call.args or {},
                from = from, lines = idList, tokens = tok})
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
    for i = #b.decisions, 1, -1 do if t - b.decisions[i].t > A.LINE_LIFE then table.remove(b.decisions, i) end end
    for k, sp in pairs(b.scorePending) do if t - sp.t > A.LINE_LIFE then b.scorePending[k] = nil end end
    local K = A.K
    local on = K and K.online == true and b.llm == true or false
    if on and t - b.llmAt >= 10 then
        b.llmAt, b.llmSaid = t, true
        if A.CL then A.CL.rpc("llm", true) end
        if b.on then sendCaps() end                 -- (kept fresh: a shard that restarted learns it again)
    elseif not on and b.llmSaid then
        b.llmSaid = nil
        if A.CL then A.CL.rpc("llm", false) end
    end
end

return A
