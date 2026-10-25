-- Dev only (tools/devtest, SCENE=languages): the Workshop page's languages shot - Wolfgang speaking Russian and Wendy
-- Chinese beside you, each translated by this PC's Koetama (its models loaded first by a warm-up line each, and the
-- history left to fade), then "[PCTEST] SHOT languages" (tools/devtest/shots.ps1).
local G, out, later = ...
local CL = G.require "proxcomms/client"
local K = G.require "proxcomms/koetama"
local D = G.require "proxcomms/dummies"

local cast = {}
local function figure(key, build, name, dist, side)
    local x, z = D.ahead(dist, side)
    local d = D.make(2, x, z)
    d.uid, d.name = "pclang_" .. key, name
    if d.ent and d.ent.AnimState then
        d.ent.AnimState:SetBuild(build)
        d.ent.AnimState:SetMultColour(1, 1, 1, 1)
        d.ent.Transform:SetRotation(G.TheCamera:GetHeading() + 180)
    end
    D.list[#D.list + 1] = d
    D.nextAt = 1e12
    cast[key] = d
end

local id = 8000000
local function say(key, text)
    local d = cast[key]
    id = id + 1
    if d.ent and d.ent.AnimState then d.ent.AnimState:PlayAnimation("dial_loop", true) end
    CL.onLine(d.uid, d.name, text, "s", id, d.x, d.z, false)
end

local function tr(key)
    local b = CL.bubbles[cast[key].uid] and CL.bubbles[cast[key].uid].cur
    return b and b.tr
end

-- every 1 s until ok() or limit s: then fn
local function waitFor(ok, limit, fn)
    local t0 = G.GetStaticTime()
    local function poll()
        if ok() or G.GetStaticTime() - t0 > limit then fn() return end
        later(1, poll)
    end
    poll()
end

later(3, function()
    G.pcall(function() G.ThePlayer.components.health:SetInvincible(true) end)
    D.CL = CL
    -- (off the spawn gate: a few steps to the side)
    local x, z = D.ahead(0, 18)
    G.pcall(function() G.ThePlayer.Physics:Teleport(x, 0, z) end)
    out("languages: koetama", K.online, K.into)
end)
later(5, function()
    figure("wolfgang", "wolfgang", "Wolfgang", 9, -7)
    figure("wendy", "wendy", "Wendy", 9, 7)
    -- (warm-up: each language's model loads the first time - Russian downloads)
    say("wolfgang", "Привет!")
    say("wendy", "你好！")
    -- (ready: translated, or Koetama says the pair's model is ready - a bubble may be gone before a download ends)
    local function ready(lang)
        for k, p in G.pairs(K.pairs or {}) do
            if k:sub(1, #lang) == lang and p.state == "ready" then return true end
        end
        return false
    end
    waitFor(function() return (tr("wolfgang") or ready("ru")) and (tr("wendy") or ready("zh")) end, 240, function()
        local pairs_ = {}
        for k, p in G.pairs(K.pairs or {}) do pairs_[#pairs_ + 1] = k .. "=" .. G.tostring(p.state) end
        out("pairs", G.table.concat(pairs_, ", "))
        out("warm-up", tr("wolfgang") or "none", tr("wendy") or "none")
        CL.bubbles = {}
        for _, d in G.ipairs(D.list) do d.ent.AnimState:PlayAnimation("idle_loop", true) end
        -- (the history's warm-up lines fade first: 10 s, and 2 s of fading)
        later(13, function()
            say("wolfgang", "Вольфганг нашёл ягоды! Кто голоден?")
            later(1.5, function() say("wendy", "我们今晚在哪里过夜？") end)
            waitFor(function() return tr("wolfgang") and tr("wendy") end, 30, function()
                out("translations", tr("wolfgang") or "none", tr("wendy") or "none")
                later(0.8, function() out("SHOT languages") end)
                later(3, function()
                    D.clear()
                    CL.bubbles = {}
                    out("DONE")
                end)
            end)
        end)
    end)
end)
