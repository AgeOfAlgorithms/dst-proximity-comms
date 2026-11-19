-- Dev only (tools/devtest, SCENE=bigdef, FAKE_LLM=1): agent API 8 in a real world, with Koetama 0.5.19 - a definition
-- at full size (a 32 KB persona, 64 functions of about 1 KB: ~100 KB of JSON) from the shard to the brain's client (in
-- 12 KB parts, A.PART: one mod RPC of it arrived cut to 33353 bytes), and on to Koetama, which must list it in
-- agents_known. (AG.PART = 1e9 here: the one-RPC way, which fails.) (The user, 2026-11-19: personas up to 32 KB and
-- 64 functions for the AI Villagers; DST's limit on an RPC string was not known.) Logged ([PCTEST] lines; RESULT).
-- (Here the host is the brain: its RPC to its own client. A dedicated server's, over the network, is not tested.)
local G, out, later = ...
local K = G.require "proxcomms/koetama"
local AG = G.require "proxcomms/agents"
local J = G.require "proxcomms/json"

local function waitFor(ok, limit, fn)
    local t0 = G.GetStaticTime()
    local function poll()
        if ok() or G.GetStaticTime() - t0 > limit then fn() return end
        later(0.5, poll)
    end
    poll()
end

-- (the definitions' bytes in each feed, and the biggest feed sent)
local defBytes, biggest = 0, 0
local feed0 = AG.feed
AG.feed = function(f)
    feed0(f)
    if f.agents then
        local n = #J.encode(f.agents)
        if n > defBytes then defBytes = n end
    end
end

local RULE = "Rule: share food with any villager who is hungry, keep the camp's fire lit at dusk, and never fight a "
    .. "beefalo herd alone. "
local function persona(n)
    local t = {"You are Sage, the keeper of the village's rules.\n"}
    local len = #t[1]
    while len < n do t[#t + 1] = RULE len = len + #RULE end
    return G.table.concat(t):sub(1, n)
end

local function functions(n)
    local fns = {}
    for i = 1, n do
        fns[i] = {name = "act_" .. i,
            description = ("Action %d: "):format(i) .. G.string.rep("does one careful thing in the camp. ", 24),
            parameters = {type = "object", properties = {what = {type = "string", description = "what to act on"}},
                required = {"what"}}}
    end
    return fns
end

-- (what reaches the brain: each message and its size; the definition by its kid, whatever this shard's id)
local upN, partN = 0, 0
local up0 = AG.onUp
AG.onUp = function(kind, s, ...)
    upN = upN + 1
    if kind == "part" then partN = partN + 1 end
    if kind == "part" or (G.type(s) == "string" and #s > 4000) then out("brain message", kind, G.type(s) == "string" and #s or -1) end
    return up0(kind, s, ...)
end
local function sageKid()
    for kid in G.pairs(AG.brain.defs or {}) do if kid:find("^sage:") then return kid end end
    return nil
end

local function finish(ok, why)
    out("RESULT", ok and "PASS" or "FAIL", why)
    out("DONE")
end

later(3, function()
    G.pcall(function() G.ThePlayer.components.health:SetInvincible(true) end)
    out("bigdef: koetama", G.tostring(K.online), K.version, "api", G.ProxComms.version)
    waitFor(function() return AG.brain and AG.brain.maxPersona == 32768 and AG.brain.on end, 40, function()
        local b = AG.brain or {}
        out("brain caps", "on", G.tostring(b.on), "persona", G.tostring(b.maxPersona), "functions", G.tostring(b.maxFn),
            "state", G.tostring(b.maxState), "bigFeeds", G.tostring(b.bigFeeds), "koetama", K.version)
        if b.maxPersona ~= 32768 then return finish(false, "Koetama's hello has no agent_persona 32768") end
        local fns = functions(64)
        local def = {persona = persona(32768), name = "Sage", functions = fns, hears = "none", stream = false}
        local ok, why = G.ProxComms.agent("sage", def)
        out("defined", G.tostring(ok), G.tostring(why), "persona", #def.persona, "functions", #fns,
            "json bytes", #J.encode(fns) + #def.persona, "personamax()", G.ProxComms.personamax(),
            "agentfunctions()", G.ProxComms.agentfunctions())
        out("kid", AG.kid("sage"), "shard", AG.shard())
        waitFor(function() return sageKid() ~= nil end, 20, function()
            local kid = sageKid()
            local keys = {}
            for k in G.pairs(AG.brain.defs or {}) do keys[#keys + 1] = k end
            out("brain defs", G.table.concat(keys, ","), "messages", upN, "parts", partN)
            local d = kid and AG.brain.defs[kid]
            local np, nf = d and #d.def.persona or 0, d and #d.def.functions or 0
            out("brain got", d and "yes" or "NO", "persona", np, "functions", nf)
            if not d then return finish(false, "the definition never reached the brain (the RPC)") end
            if np ~= 32768 or nf ~= 64 then return finish(false, "the brain got it cut: " .. np .. " / " .. nf) end
            waitFor(function() return AG.brain.known and AG.brain.known[kid] ~= nil end, 40, function()
                local v = AG.brain.known and AG.brain.known[kid]
                out("koetama knows", v and "yes" or "NO", "version", G.tostring(v), "definitions in a feed (bytes)",
                    defBytes, "last feed (bytes)", G.tostring(K.lastSize))
                if not v then return finish(false, "Koetama never listed it in agents_known") end
                finish(true, "a ~100 KB definition: shard -> brain (in parts) -> Koetama")
            end)
        end)
    end)
end)
