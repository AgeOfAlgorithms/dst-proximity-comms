-- Dev only (tools/devtest, SHOTS=1): stages the mod's features for screenshots (the Workshop page's pictures, the
-- user 2026-10-16). Each scene logs "[PCTEST] SHOT <name>", and tools/devtest/shots.ps1 presses Steam's screenshot key.
-- Characters stand in with their own looks (client-side figures, as /pc dummy's), and say their lines through the
-- mod's own paths.
local G, out, later = ...
local CL = G.require "proxcomms/client"
local K = G.require "proxcomms/koetama"
local D = G.require "proxcomms/dummies"
local W = G.require "proxcomms/wheel"

local cast = {}
local function figure(key, build, name, dist, side, tags)
    local x, z = D.ahead(dist, side)
    local d = D.make(2, x, z)
    d.uid, d.name = "pcshot_" .. key, name
    if d.ent and d.ent.AnimState then
        d.ent.AnimState:SetBuild(build)
        d.ent.AnimState:SetMultColour(1, 1, 1, 1)
        for _, t in G.ipairs(tags or {}) do d.ent:AddTag(t) end
        -- (facing the camera)
        d.ent.Transform:SetRotation(G.TheCamera:GetHeading() + 180)
    end
    D.list[#D.list + 1] = d
    D.nextAt = 1e12                    -- (the figures' own turns: off - they say only the scenes' lines)
    cast[key] = d
    return d
end

local id = 5000000
local function line(key, text, mode)
    local d = cast[key]
    id = id + 1
    if d.ent and d.ent.AnimState then d.ent.AnimState:PlayAnimation("dial_loop", true) end
    if mode == "w" then
        CL.onNative(d.uid, d.name, text, nil, true)
    else
        CL.onLine(d.uid, d.name, text, mode, id, d.x, d.z, false)
    end
end

local function clean()
    CL.bubbles, CL.live = {}, {}
    for _, d in G.ipairs(D.list) do
        if d.ent and d.ent.AnimState then d.ent.AnimState:PlayAnimation("idle_loop", true) end
    end
end

local function cut()
    D.clear()
    cast = {}
    clean()
end

local t = 3
local function at(dt, fn) t = t + dt later(t, fn) end

at(0, function()
    G.pcall(function() G.ThePlayer.components.health:SetInvincible(true) end)
    D.CL = CL
    out("shots: start", "koetama", K.online, K.version)
end)
-- 1. the modes at once
at(1, function()
    figure("wendy", "wendy", "Wendy", 9, -10)
    figure("wolfgang", "wolfgang", "Wolfgang", 12, 0)
    figure("willow", "willow", "Willow", 9, 10)
end)
at(1, function()
    line("wendy", "psst... the pig king is this way", "w")
    line("wolfgang", "Wolfgang found berries! Who is hungry?", "s")
    line("willow", "HOUNDS! EVERYONE TO THE BASE!", "y")
    CL.say("Coming, wait for me!", "s")
end)
at(1.5, function() out("SHOT modes") end)
-- (the chat history: shown for the modes' shot only - its coloured lines; the rest without it)
local function history(show)
    local q = G.ThePlayer.HUD.controls and G.ThePlayer.HUD.controls.networkchatqueue
    if q then if show then q:Show() else q:Hide() end end
end
at(0.5, function() history(false) end)
-- 2. far away: garbled, on the screen's edge with the name, the tail pointing off screen
at(3, function()
    cut()
    figure("wolfgang", "wolfgang", "Wolfgang", 4, 21 * 4)
end)
at(0.5, function() line("wolfgang", "I found a beefalo herd past the swamp, bring a spear", "s") end)
at(1.5, function() out("SHOT far") end)
-- 3. a translation (by this PC's Koetama, into its language), pink under the line
at(3, function()
    cut()
    figure("wendy", "wendy", "Wendy", 8, -3)
end)
at(0.5, function() line("wendy", "¿Alguien tiene comida? Tengo mucha hambre.", "s") end)
at(6, function()
    local b = CL.bubbles[cast.wendy.uid] and CL.bubbles[cast.wendy.uid].cur
    out("translation", b and b.tr or "none")
    out("SHOT translation")
end)
-- 4. live words while someone talks (with Koetama), and ♪ while a voice is heard
at(3, function()
    cut()
    figure("willow", "willow", "Willow", 8, 4)
end)
at(0.5, function()
    CL.onLive(cast.willow.uid, "Willow", 77, "so I was thinking we could build the base right next to the", "s",
        cast.willow.x, cast.willow.z)
    if cast.willow.ent then cast.willow.ent.AnimState:PlayAnimation("dial_loop", true) end
end)
at(1, function() out("SHOT live") end)
-- 5. Wes: in brackets
at(3, function()
    cut()
    figure("wes", "wes", "Wes", 8, 0, {"mime"})
end)
at(0.5, function() line("wes", "I'm the best", "s") end)
at(1.2, function() out("SHOT wes") end)
-- 6. the talk key + Tab strip: Speak, then Tab to Yell
at(3, function()
    cut()
    CL.setMode("s")
    K.talkKey = true
end)
at(0.6, function() CL.talkTab(true) CL.talkTab(false) end)
at(0.8, function() out("SHOT talkstrip") end)
at(1, function() K.talkKey = false CL.setMode("s") end)
-- 7. the settings (Chat page)
at(1.5, function() CL.openSettings(1) end)
at(1.2, function() out("SHOT settings") end)
at(1, function() G.TheFrontEnd:GetActiveScreen():Close() end)
-- 8. Quick chat: a message built on the wheel
at(1.5, function()
    local hud = G.ThePlayer.HUD
    hud:OpenCommandWheel()
    local w = hud.controls.commandwheel
    w:Close()
    w:Open("pc_quick")
    W.clear()
    W.add("Where?")
    W.add("Food")
end)
at(1.2, function() out("SHOT quickchat") end)
at(1, function()
    G.ThePlayer.HUD:CloseCommandWheel()
    cut()
    history(true)
    out("DONE")
end)
