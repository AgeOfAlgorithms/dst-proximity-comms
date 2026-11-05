-- Dev only (tools/devtest, SCENE=agents2, FAKE_LLM=1): agent API 2 end to end in a real world, with Koetama 0.5.14 and
-- the fake model of tools/devtest/fake_llm.py (its scores: topic 0.95, or 0.05 for "ignore me").
-- 1. SCORES: a dog that hears everything near it, with criteria; the mod answers a turn whose topic is 0.5 or more.
--    "Rex, good boy!" is scored and answered; "ignore me please" is scored and skipped (no words, onSkip).
-- 2. AGENTS HEAR AGENTS: two villagers that hear near and hear agents (hearagents 2). A player's "hello there" starts
--    them; each answers it (count 1), the other's line (2), the other's again (3) - and a count-3 line reaches no one:
--    their talk stops by itself.
-- Logged ([PCTEST] lines); no screenshots.
local G, out, later = ...
local CL = G.require "proxcomms/client"
local K = G.require "proxcomms/koetama"
local AG = G.require "proxcomms/agents"
local D = G.require "proxcomms/dummies"

local J = G.require "proxcomms/json"

local got = {scores = {}, skips = {}, replies = {}, errors = {}}
local spawned = {}

-- (what goes to Koetama and comes back, for the log: the definitions, the lines, the scores, the replies)
local feed0, scores0, reply0 = AG.feed, AG.onScores, AG.onReply
AG.feed = function(f)
    feed0(f)
    if f.agents then out("feed agents", J.encode(f.agents):sub(1, 600)) end
    if f.to_agent then out("feed lines", J.encode(f.to_agent):sub(1, 400)) end
    if f.agent_decisions then out("feed decisions", J.encode(f.agent_decisions)) end
end
AG.onScores = function(o) out("koetama scores", J.encode(o)) scores0(o) end
AG.onReply = function(o)
    if o.final ~= false then out("koetama reply", G.tostring(o.agent), "skipped", G.tostring(o.skipped), G.tostring(o.text)) end
    reply0(o)
end

local function waitFor(ok, limit, fn)
    local t0 = G.GetStaticTime()
    local function poll()
        if ok() or G.GetStaticTime() - t0 > limit then fn() return end
        later(0.5, poll)
    end
    poll()
end

local function body(prefab, ahead, side)
    local x, z = D.ahead(ahead, side)
    local e = G.SpawnPrefab(prefab)
    e.Transform:SetPosition(x, 0, z)
    if e.components.locomotor then e.components.locomotor:Stop() end
    if e.brain then e:StopBrain() end
    spawned[#spawned + 1] = e
    return e
end

local function replied(who) return function(text, info)
    got.replies[#got.replies + 1] = {who = who, text = text, depth = info and info.depth, t = G.GetStaticTime()}
    out("reply", who, "count", G.tostring(info and info.depth), text)
end end

later(3, function()
    G.pcall(function() G.ThePlayer.components.health:SetInvincible(true) end)
    D.CL = CL
    out("agents2: koetama", K.online, K.version, "llm", K.features and K.features.llm,
        "agent_scores", K.features and K.features.agent_scores, "api", G.ProxComms.version,
        "brain scores", G.tostring(AG.brain.scores), "brain llm", G.tostring(AG.brain.llm))
    local dog = body("perd", 6, 0)
    local ok, why = G.ProxComms.agent("rex", {
        persona = "You are Rex, a dog in a Don't Starve world. Answer with a short bark.",
        name = "Rex", entity = dog, hears = "near", stream = false, max_words = 10,
        criteria = {{name = "topic", description = "Rex is the topic: someone talks to him or about him"},
            {name = "interest", description = "something a dog would care about"}},
        onScores = function(scores, info)
            got.scores[#got.scores + 1] = {scores = scores, info = info}
            local answer = (scores.topic or 0) >= 0.5
            out("scores", "turn", info.turn, "topic", G.tostring(scores.topic), "interest", G.tostring(scores.interest),
                "from", G.table.concat(info.from, ","), "text", G.table.concat(info.text, " / "), "->", answer and "answer" or "skip")
            return answer
        end,
        onSkip = function(info) got.skips[#got.skips + 1] = info out("skip", G.table.concat(info.from, ",")) end,
        onReply = replied("rex"),
        onError = function(code, why2) got.errors[#got.errors + 1] = code out("error", code, G.tostring(why2)) end,
    })
    out("rex defined", ok, G.tostring(why))
end)

later(4, function()
    waitFor(function() return AG.owner ~= nil and G.ProxComms.scores() end, 40, function()
        out("brain", G.tostring(AG.owner), "status", G.ProxComms.status(), "scores()", G.ProxComms.scores())
        CL.say("Rex, good boy!", "s")
        waitFor(function() return #got.replies >= 1 or #got.errors > 0 end, 30, function()
            out("CHECK scored+answered", #got.scores >= 1 and #got.replies >= 1 and got.replies[1].who == "rex")
            CL.say("ignore me please", "s")
            waitFor(function() return #got.skips >= 1 or #got.errors > 0 end, 30, function()
                out("CHECK scored+skipped", #got.skips >= 1 and #got.replies == 1)
                G.ProxComms.agent("rex", nil)
                -- 2. two villagers who talk among themselves, counted
                local gus, mira = body("pigman", 5, -2), body("pigman", 5, 2)
                for _, v in G.ipairs({{"gus", "Gus", gus}, {"mira", "Mira", mira}}) do
                    G.ProxComms.agent(v[1], {
                        persona = "You are " .. v[2] .. ", a villager. Answer in a few words.",
                        name = v[2], entity = v[3], hears = "near", hearagents = 2, stream = false, max_words = 10,
                        onReply = replied(v[1]),
                        onError = function(code, why2) got.errors[#got.errors + 1] = code out("error", code, G.tostring(why2)) end,
                    })
                end
                local before = #got.replies
                later(2, function()
                    CL.say("hello there", "s")
                    -- (quiet for 15 s: their talk is over)
                    local lastN, quietSince = -1, G.GetStaticTime()
                    waitFor(function()
                        if #got.replies ~= lastN then lastN, quietSince = #got.replies, G.GetStaticTime() end
                        return #got.replies > before and G.GetStaticTime() - quietSince > 15
                    end, 120, function()
                        local n, maxDepth = 0, 0
                        for i = before + 1, #got.replies do
                            n = n + 1
                            maxDepth = G.math.max(maxDepth, got.replies[i].depth or 0)
                        end
                        out("villagers", "replies", n, "highest count", maxDepth, "errors", G.table.concat(got.errors, ","))
                        out("CHECK agents talked", n >= 3 and maxDepth >= 2)
                        out("CHECK talk ended at the count", maxDepth <= 3)
                        G.ProxComms.agent("gus", nil)
                        G.ProxComms.agent("mira", nil)
                        for _, e in G.ipairs(spawned) do if e:IsValid() then e:Remove() end end
                        out("DONE")
                    end)
                end)
            end)
        end)
    end)
end)
