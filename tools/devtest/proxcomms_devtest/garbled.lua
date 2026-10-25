-- Dev only (tools/devtest, SCENE=garbled): a translated line heard from the garbled zone - its translation garbled as
-- the line is, filling in when the speaker comes close - then the history; logged, and a screenshot of each stage.
local G, out, later = ...
local CL = G.require "proxcomms/client"
local K = G.require "proxcomms/koetama"
local D = G.require "proxcomms/dummies"

local LINE = "Hola amigos, vamos a la base antes de la noche."
local ENGLISH = "Hello friends, let's go to the base before nightfall."
local d, b

local function place(dist)
    local x, z = D.ahead(dist, 0)
    d.x, d.z = x, z
    d.ent.Transform:SetPosition(x, 0, z)
end

local function state(tag)
    out(tag, "level", b.level, "| line:", CL.bubbleText(b), "| translation:", G.tostring(CL.trText(b)))
end

later(3, function()
    G.pcall(function() G.ThePlayer.components.health:SetInvincible(true) end)
    D.CL = CL
    local r = CL.ranges.s
    out("garbled: koetama", K.online, "speak", r[1], r[2])
    d = D.make(2, 0, 0)
    d.uid, d.name = "pcgarb_wolfgang", "Wolfgang"
    d.ent.AnimState:SetBuild("wolfgang")
    d.ent.AnimState:SetMultColour(1, 1, 1, 1)
    D.list[#D.list + 1] = d
    D.nextAt = 1e12
    place((r[1] + r[2]) / 2)                            -- (the middle of Speak's garbled zone)
end)
later(4, function()
    CL.onLine(d.uid, d.name, LINE, "s", 9200001, d.x, d.z, false)
    b = CL.bubbles[d.uid].cur
    out("asked for its translation", b.trAsked == true)
end)
later(5, function()
    if not b.tr then CL.translated(d.uid, d.name, ENGLISH, b) end   -- (no Koetama here: its answer, by hand)
end)
later(6, function() state("far") out("SHOT garbled_far") end)
later(8, function() place(10) end)                          -- (walks in: well within Speak)
later(9, function() state("near") out("SHOT garbled_near") end)
later(11, function()
    for i = 1, 6 do
        local m = G.ChatHistory:GetChatMessageAtIndex(i)
        if m then out("history", G.tostring(m.sender), "|", G.tostring(m.message), "| small", G.tostring(m.m_colour and m.m_colour.pc_small)) end
    end
    D.clear()
    CL.bubbles = {}
    out("DONE")
end)
