-- Dev only (tools/devtest, SCENE=chatui): the chat on screen (the user, 2026-11-06): the game's lines at the bottom
-- hidden by default (the bubbles show what is said; the open chat shows it all), shown again by the setting; the open
-- chat's history at its size (Settings.chatSize, from its bottom left); the Chat page with the two new rows. Logged
-- and a screenshot each.
local G, out, later = ...
local CL = G.require "proxcomms/client"
local D = G.require "proxcomms/dummies"
local Settings = G.require "proxcomms/settings"

local t = 3
local function at(dt, fn) t = t + dt later(t, fn) end
local function q() return G.ThePlayer.HUD.controls.networkchatqueue end
local function root() return G.ThePlayer.HUD.controls.chat_queue_root end

at(0, function()
    G.pcall(function() G.ThePlayer.components.health:SetInvincible(true) end)
    D.CL = CL
    local px, pz = D.ahead(-6, -30)
    G.ThePlayer.Physics:Teleport(px, 0, pz)
end)
at(1.5, function()
    local x, z = D.ahead(3, 1.5)
    D.make(1, x, z)
    CL.say("Hello everyone, is anyone around here?", "s")
end)
at(1, function()
    local d = D.list[1]
    CL.onLine(d.uid, "Wendy", "Over here, by the berry bushes!", "s", 7100001, d.x, d.z, false)
end)
at(1.5, function()
    out("CHECK lines hidden by default", Settings.chatLines == false, "shown", G.tostring(q().shown))
    out("SHOT chatui_closed")
end)
at(1, function() G.TheFrontEnd:PushScreen(G.require("screens/chatinputscreen")(false)) end)
at(1.2, function()
    local s = G.TheFrontEnd:GetActiveScreen()
    local r = s.chat_queue_root
    local sc = r and r:GetScale()
    out("CHECK the open chat's history at its size", Settings.chatSize, "scale", sc and G.string.format("%.2f", sc.x))
    out("SHOT chatui_open")
end)
at(1.2, function() G.TheFrontEnd:GetActiveScreen():Close() end)
at(1, function() out("CHECK hidden again after the chat closed", G.tostring(q().shown)) end)
at(0.5, function()
    Settings.chatLines = true
    CL.applyChat()
    out("CHECK the setting shows them", G.tostring(q().shown), "scale", G.string.format("%.2f", root():GetScale().x))
    out("SHOT chatui_lines_on")
end)
at(1.2, function()
    Settings.chatLines = false
    CL.applyChat()
    CL.openSettings(1)
end)
at(1.2, function() out("SHOT chatui_settings") end)
at(1, function()
    G.TheFrontEnd:GetActiveScreen():Close()
    D.clear()
    out("DONE")
end)
