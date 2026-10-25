-- Dev only (tools/devtest, SCENE=agents, FAKE_LLM=1): an agent end to end in a real world - a Pigman a mod (this
-- test) defines through ProxComms (proxcomms/agents.lua), this player's Koetama (the host's, an admin's) with the fake
-- model of tools/devtest/fake_llm.py. The player says "Pigman, follow me!": the line to the agent, its reply as a bubble
-- over it and a chat line, its call to follow (the mod answers), the follow-up. Logged, and a screenshot.
local G, out, later = ...
local CL = G.require "proxcomms/client"
local K = G.require "proxcomms/koetama"
local AG = G.require "proxcomms/agents"
local D = G.require "proxcomms/dummies"

local pig
local got = {calls = {}, replies = {}, errors = {}}

local function waitFor(ok, limit, fn)
    local t0 = G.GetStaticTime()
    local function poll()
        if ok() or G.GetStaticTime() - t0 > limit then fn() return end
        later(0.5, poll)
    end
    poll()
end

later(3, function()
    G.pcall(function() G.ThePlayer.components.health:SetInvincible(true) end)
    D.CL = CL
    local x, z = D.ahead(8, 3)
    pig = G.SpawnPrefab("pigman")
    pig.Transform:SetPosition(x, 0, z)
    if pig.components.locomotor then pig.components.locomotor:Stop() end
    if pig.brain then pig:StopBrain() end
    local ok, err = G.ProxComms.agent("pigman", {
        persona = "You are a Pigman in a Don't Starve world. You grunt a lot and you follow whoever asks politely.",
        name = "Pigman", entity = pig, hears = "named", stream = false, max_words = 20,
        functions = {{name = "follow", description = "Follow a player",
            parameters = {type = "object", properties = {player = {type = "string"}}, required = {"player"}}}},
        state = function() return "day 1; a quiet meadow" end,
        onCall = function(c) got.calls[#got.calls + 1] = c return "ok: following " .. G.tostring(c.args.player) end,
        onReply = function(text, info) got.replies[#got.replies + 1] = text end,
        onError = function(code, why) got.errors[#got.errors + 1] = code .. " " .. G.tostring(why) end,
    })
    out("agents: koetama", K.online, K.version, "llm", K.features and K.features.llm, "defined", ok, err)
end)
later(4, function()
    -- (this player's Koetama says "llm" in its hello; its game tells the server within 10 s: the brain)
    waitFor(function() return AG.owner ~= nil end, 40, function()
        out("brain", G.tostring(AG.owner), "status", G.ProxComms.status(), "me", CL.me())
        CL.say("Pigman, follow me!", "s")
        waitFor(function() return #got.replies >= 2 or #got.errors > 0 end, 40, function()
            out("replies", G.table.concat(got.replies, " | "))
            for _, c in G.ipairs(got.calls) do out("call", c.name, G.tostring(c.args.player), "from", G.table.concat(c.from, ",")) end
            out("errors", G.table.concat(got.errors, " | "))
            local b = CL.bubbles["agent:pigman:" .. AG.shard()]
            out("bubble", b and b.cur and b.cur.full or "none")
            out("SHOT agent")
            later(2, function()
                for i = 1, 5 do
                    local m = G.ChatHistory:GetChatMessageAtIndex(i)
                    if m then out("history", G.tostring(m.sender), "|", G.tostring(m.message)) end
                end
                G.ProxComms.agent("pigman", nil)
                if pig and pig:IsValid() then pig:Remove() end
                out("DONE")
            end)
        end)
    end)
end)
