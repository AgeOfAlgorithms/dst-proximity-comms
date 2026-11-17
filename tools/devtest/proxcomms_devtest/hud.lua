-- Dev only (tools/devtest, SCENE=hud): bubbles of speakers off the screen on every side, kept out from behind the
-- game's HUD (the user, 2026-11-16: "the speech bubbles are often drawn behind the game's own UI when players speak off
-- the screen"). Logs the HUD boxes measured, and screenshots with the boxes drawn (CL.showHud) and without.
local G, out, later = ...
local CL = G.require "proxcomms/client"
local D = G.require "proxcomms/dummies"

local cast = {}
local function figure(key, build, name, dist, side)
    local x, z = D.ahead(dist, side)
    local d = D.make(2, x, z)
    d.uid, d.name = "pchud_" .. key, name
    if d.ent and d.ent.AnimState then d.ent.AnimState:SetBuild(build) end
    D.list[#D.list + 1] = d
    D.nextAt = 1e12
    cast[key] = d
end

local id = 6000000
local function line(key, text)
    local d = cast[key]
    id = id + 1
    CL.onLine(d.uid, d.name, text, "y", id, d.x, d.z, false)
end

local SPOTS = {   -- {key, build, name, ahead, side}: off the screen on each side and corner
    {"r", "wolfgang", "Wolfgang", 2, 45}, {"l", "wendy", "Wendy", 2, -45},
    {"t", "willow", "Willow", 40, 0}, {"b", "wx78", "WX-78", -26, 0},
    {"tl", "wickerbottom", "Wickerbottom", 34, -40}, {"tr", "woodie", "Woodie", 34, 40},
    {"bl", "wes", "Wes", -22, -40}, {"br", "webber", "Webber", -22, 40},
}

local function lines()
    for _, s in G.ipairs(SPOTS) do line(s[1], s[3] .. " here - can you read this over the HUD?") end
end

local function boxes()
    local pb = G.ThePlayer and G.ThePlayer.HUD and G.ThePlayer.HUD.pc_bubbles
    for _, r in G.ipairs(pb and pb.hudRects or {}) do
        out("HUD box", r.name, G.math.floor(r[1]), G.math.floor(r[2]), G.math.floor(r[3]), G.math.floor(r[4]))
    end
    local sw, sh = G.TheSim:GetScreenSize()
    out("screen", sw, sh, "hud scale", G.TheFrontEnd:GetHUDScale())
end

local function placed()
    local pb = G.ThePlayer and G.ThePlayer.HUD and G.ThePlayer.HUD.pc_bubbles
    for key, w in G.pairs(pb and pb.pool or {}) do
        local p = w:GetWorldPosition()
        out("bubble", key, G.math.floor(p.x), G.math.floor(p.y), w.shown and "shown" or "hidden")
    end
end

later(3, function()
    G.pcall(function() G.ThePlayer.components.health:SetInvincible(true) end)
    D.CL = CL
    local q = G.ThePlayer.HUD.controls and G.ThePlayer.HUD.controls.networkchatqueue
    if q then q:Hide() end
    for _, s in G.ipairs(SPOTS) do figure(s[1], s[2], s[3], s[4], s[5]) end
end)
later(4, function() lines() end)
later(5.5, function()
    CL.showHud = true
    boxes()
    placed()
end)
later(6, function() out("SHOT hud_boxes") end)
later(8, function() CL.showHud = false lines() end)
later(9.5, function() placed() out("SHOT hud_plain") end)
-- (the crafting menu open: a big box on the left)
later(11, function()
    local cm = G.ThePlayer.HUD.controls and G.ThePlayer.HUD.controls.craftingmenu
    if cm and cm.Open then G.pcall(cm.Open, cm) end
    lines()
end)
later(12.5, function() CL.showHud = true boxes() end)
later(13, function() out("SHOT hud_crafting") end)
-- (the user, 2026-11-16: two bubbles docked on an edge, one speaker moving - they flickered, switching places. Wolfgang
--  walks down the right edge past Woodie; both bubbles' places logged ten times a second: they must glide, and
--  change places once at most)
later(14.5, function()
    CL.showHud = false
    local cm = G.ThePlayer.HUD.controls and G.ThePlayer.HUD.controls.craftingmenu
    if cm and cm.Close then G.pcall(cm.Close, cm) end
    CL.bubbles = {}
    line("tr", "Woodie, staying right here by the trees")
    line("r", "Wolfgang walking down past Woodie now")
end)
local function bubbleY(key)
    local pb = G.ThePlayer and G.ThePlayer.HUD and G.ThePlayer.HUD.pc_bubbles
    local w = pb and pb.pool[key]
    return w and w.place and G.math.floor(w.place[2]) or -1
end
for i = 0, 40 do
    later(15 + i * 0.1, function()
        local d = cast.r
        if d and d.ent and d.ent.Transform then
            local x, z = D.ahead(40 - 70 * i / 40, 45)
            d.ent.Transform:SetPosition(x, 0, z)
            d.x, d.z = x, z
        end
        out("walk", i, "wolfgang", bubbleY("pchud_r:cur"), "woodie", bubbleY("pchud_tr:cur"))
    end)
end
later(19.5, function() out("DONE") end)
