-- Dev only (tools/devtest, SCENE=history): a translated line in the chat history - its original's rows smaller than
-- its translation's - in the HUD's history and the chat line's scrollable one; each row's text and size logged, and a
-- screenshot of each ("[PCTEST] SHOT ...", tools/devtest/shots.ps1).
local G, out, later = ...
local CL = G.require "proxcomms/client"
local K = G.require "proxcomms/koetama"
local D = G.require "proxcomms/dummies"

local SPANISH = "¿Alguien tiene comida? Tengo mucha hambre."
local ENGLISH = "Does anyone have food? I'm very hungry."

-- every chat row (widgets/redux/chatline) under a widget, with its text and size
local function rows(w, outRows)
    outRows = outRows or {}
    if w.message and w.SetChatData and w.message.GetString then outRows[#outRows + 1] = w end
    for _, c in G.pairs(w.children or {}) do rows(c, outRows) end
    return outRows
end
local function report(tag, root)
    for _, r in G.ipairs(rows(root)) do
        local s = r.message:GetString() or ""
        if r.root and r.root.shown ~= false and s ~= "" then
            out(tag, G.string.format("size %.1f", r.message.size or -1), s)
        end
    end
end

local t = 3
local function at(dt, fn) t = t + dt later(t, fn) end
local uid
at(0, function()
    G.pcall(function() G.ThePlayer.components.health:SetInvincible(true) end)
    D.CL = CL
    local x, z = D.ahead(8, -3)
    local d = D.make(2, x, z)
    d.uid, d.name = "pctest_wendy", "Wendy"
    if d.ent and d.ent.AnimState then d.ent.AnimState:SetBuild("wendy") d.ent.AnimState:SetMultColour(1, 1, 1, 1) end
    D.list[#D.list + 1] = d
    D.nextAt = 1e12
    uid = d.uid
    out("history: koetama", K.online)
end)
at(1, function()
    CL.onLine(uid, "Wendy", SPANISH, "s", 7000001, D.list[1].x, D.list[1].z, false)
end)
at(1, function()
    local b = CL.bubbles[uid] and CL.bubbles[uid].cur
    out("original's history message", b and b.histMsg ~= nil)
    if not K.online then CL.translated(uid, "Wendy", ENGLISH, b) end    -- (no Koetama here: its answer, by hand)
end)
at(K.online and 8 or 1, function()
    local b = CL.bubbles[uid] and CL.bubbles[uid].cur
    out("translation", b and b.tr or "none", "marked small", b and b.histMsg and b.histMsg.m_colour.pc_small)
    report("hud row", G.ThePlayer.HUD)
    out("SHOT history_hud")
end)
at(2, function()
    G.TheFrontEnd:PushScreen(G.require("screens/chatinputscreen")(false))
end)
at(1.5, function()
    report("scroll row", G.TheFrontEnd:GetActiveScreen())
    out("SHOT history_scroll")
end)
at(1.5, function()
    G.TheFrontEnd:GetActiveScreen():Close()
    D.clear()
    out("DONE")
end)
