-- Dev only (tools/devtest): drives the game for an automated in-game check of Proximity Comms. Every step logs a
-- "[PCTEST]" line to client_log.txt; "[PCTEST] SHOT <name>" asks tools/devtest/shots.ps1 for a screenshot.
local G = GLOBAL
local function out(...)
    local t = {}
    for i = 1, G.select("#", ...) do t[#t + 1] = G.tostring(G.select(i, ...)) end
    G.print("[PCTEST] " .. G.table.concat(t, " "))
end
local function later(s, fn)
    G.staticScheduler:ExecuteInTime(s, function()
        local ok, err = G.pcall(fn)
        if not ok then out("ERROR", err) end
    end)
end
if G.TheNet:IsDedicated() then return end
G.pcall(function() G.TheMixer:SetLevel("master", 0) end)

if G.IsInFrontEnd() then
    -- host an offline world in this process (the main menu's own OnHostButton path), on save slot 9
    out("frontend: hosting an offline world on slot 9")
    later(4, function()
        G.KnownModIndex:Enable("proxcomms")
        G.ShardSaveGameIndex:LoadSlotEnabledServerMods()
        G.KnownModIndex:Save()
        local ok = G.TheNet:StartServer(false, 9, G.ShardSaveGameIndex:GetSlotServerData(9))
        out("StartServer", ok)
        if ok then
            G.DisableAllDLC()
            G.StartNextInstance({reset_action = G.RESET_ACTION.LOAD_SLOT, save_slot = 9})
        end
    end)
    return
end

out("in game: waiting for the lobby")
local spawned = false
G.staticScheduler:ExecutePeriodic(1, function()
    G.pcall(function() G.TheMixer:SetLevel("master", 0) end)
    local scr = G.TheFrontEnd:GetActiveScreen()
    if not spawned and scr and scr.name == "LobbyScreen" then
        spawned = true
        out("lobby: spawning wilson")
        G.TheFrontEnd:PopScreen()
        G.TheNet:SendSpawnRequestToServer("wilson", "wilson_none", "", "", "", "", {}, nil, {})
    end
end)

local started = false
AddPlayerPostInit(function(inst)
    inst:DoTaskInTime(1, function()
        if inst ~= G.ThePlayer or started then return end
        started = true
        -- (SHOTS=1: the screenshots' scenes instead of the checks - shots.lua)
        -- (a scene instead: <name>.txt present -> <name>.lua; SHOTS=1 / SCENE=<name> in run.sh)
        for _, scene in G.ipairs({"shots", "history", "languages", "garbled", "agents"}) do
            if G.kleifileexists(MODROOT .. scene .. ".txt") then
                local fn = G.kleiloadlua(MODROOT .. scene .. ".lua")
                if type(fn) == "function" then fn(G, out, later) else out("ERROR", scene .. ".lua: " .. G.tostring(fn)) end
                return
            end
        end
        local CL = G.require "proxcomms/client"
        local K = G.require "proxcomms/koetama"
        local function state(tag)
            local n, list = 0, {}
            for uid, s in G.pairs(CL.bubbles) do
                n = n + 1
                list[#list + 1] = uid .. "=" .. G.tostring(s.cur and (s.cur.level .. ":" .. s.cur.full) or "-")
            end
            out(tag, "gotState", CL.gotState, "mode", CL.mode, "room", CL.room, "speak", CL.ranges.speakTiles, "yell",
                CL.ranges.yellTiles, "koetama", K.online, K.version, "bubbles", n, G.table.concat(list, " | "))
            local hud = G.ThePlayer.HUD
            out(tag, "hud", hud ~= nil, "pc_bubbles", hud ~= nil and hud.pc_bubbles ~= nil)
            if hud and hud.pc_bubbles then
                for key, w in G.pairs(hud.pc_bubbles.pool) do
                    local p = w:GetPosition()
                    out(tag, "  widget", key, G.string.format("%.0f,%.0f", p.x, p.y), (w.text:GetString():gsub("\n", " / ")))
                end
            end
        end
        later(3, function() state("start") end)
        later(4, function() CL.command("/pc dummy") out("dummies", #CL.D.list) end)
        later(6, function() CL.say("Hello from the test, this is Speak.", "s") end)
        later(8, function() state("after speak") out("SHOT speak") end)
        -- the bubbles' font (fonts/pc_pangolin.zip): its sizes beside the game's fonts' (zero or a missing font's: not
        -- loaded); Cyrillic is its own, Chinese, ∷ and ♪ the game's fallbacks
        later(9, function()
            local Text = G.require "widgets/text"
            local t = G.ThePlayer.HUD:AddChild(Text(G.TALKINGFONT, 28))
            t:Hide()
            for _, s in G.ipairs({"Hello there", "Привет, друзья", "你好朋友", "H⬚ll⬚", "∷ ♪"}) do
                local row = {}
                for _, f in G.ipairs({"pc_pangolin", G.DEFAULTFONT, G.TALKINGFONT}) do
                    t:SetFont(f)
                    t:SetString(s)
                    local w, h = t:GetRegionSize()
                    row[#row + 1] = G.string.format("%s=%.0fx%.0f", f, w or -1, h or -1)
                end
                out("font", s, G.table.concat(row, " "))
            end
            t:Kill()
            local hud = G.ThePlayer.HUD
            for key, w in G.pairs(hud.pc_bubbles.pool) do
                local side
                for k, tl in G.pairs(w.tails) do if tl.shown then side = k end end
                out("bubble", key, "font", w.font, "box", w.box.shown, "opacity", G.tostring(w.opacity), "tail", G.tostring(side))
            end
        end)
        later(11, function() CL.say("THIS IS A YELL FROM THE TEST!", "y") G.TheNet:Say("a global line from the test", false) end)
        later(13, function() state("after yell") out("SHOT yell") end)
        later(16, function() G.TheNet:Say("a whisper from the test", true) end)
        later(18, function() state("after whisper") out("SHOT whisper") end)
        later(20, function()
            local words = {}
            for i = 1, 45 do words[i] = "word" .. i end
            CL.say(G.table.concat(words, " "), "s")
        end)
        later(22, function() state("long line") out("SHOT long") end)
        later(27, function() state("long line scrolled") out("SHOT long_scrolled") end)
        later(26, function() state("spoken") out("SHOT spoken", "voice", K.voiceState, "speech", K.speech, K.mic) end)
        later(29, function()
            local ChatInputScreen = G.require "screens/chatinputscreen"
            G.TheFrontEnd:PushScreen(ChatInputScreen(false))
            local scr = G.TheFrontEnd:GetActiveScreen()
            out("chat line", scr.name, "mode button", scr.pc_modebtn and scr.pc_modebtn.text:GetString(), "settings", scr.pc_setbtn ~= nil)
            scr.chat_edit:OnRawKey(G.KEY_TAB, true)  -- (as a real key: the force-edited text field gets it)
            out("after Tab", scr.pc_mode, scr.pc_modebtn and scr.pc_modebtn.text:GetString(), "CL.mode", CL.mode)
        end)
        later(30, function() out("SHOT chatline") end)
        later(32, function()
            local scr = G.TheFrontEnd:GetActiveScreen()
            scr.chat_edit:SetString("typed in the chat line as a yell")
            scr:OnTextEntered()
        end)
        later(34, function() state("typed") out("SHOT typed") CL.setMode("s") end)
        later(36, function() CL.openSettings(1) out("settings", G.TheFrontEnd:GetActiveScreen().name) end)
        later(37, function() out("SHOT settings_chat") end)
        later(39, function() G.TheFrontEnd:GetActiveScreen():ShowPage(2) end)
        later(40, function() out("SHOT settings_voice") end)
        later(42, function() G.TheFrontEnd:GetActiveScreen():ShowPage(4) end)
        later(43, function() out("SHOT settings_translate") end)
        later(45, function() G.TheFrontEnd:GetActiveScreen():Close() end)
        later(46, function()
            local hud = G.ThePlayer.HUD
            hud:OpenCommandWheel()
            out("wheel open", hud:IsCommandWheelOpen())
            local items = hud.controls.commandwheel.items.root
            out("wheel items", #items, items[#items].label)
            hud.controls.commandwheel:Close()
            hud.controls.commandwheel:Open("pc_quick")
        end)
        later(47, function() out("SHOT wheel") end)
        later(49, function() G.ThePlayer.HUD:CloseCommandWheel() CL.command("/pc help") CL.command("/pc koetama") end)
        later(50, function() out("SHOT help") end)
        later(52, function() G.TheCamera:SetHeadingTarget(G.TheCamera:GetHeadingTarget() + 180) end)
        later(54, function() state("turned") out("SHOT turned") end)
        later(24, function()
            local d = CL.D.list[2]
            CL.onLine(d.uid, d.name, "hola amigos, ¿dónde está la base? Tengo comida para todos.", "s", 999001, d.x, d.z, false)
            out("spanish line", "koetama into", K.into, "lines waiting", G.next(K.lines) ~= nil)
        end)
        local function history(tag)
            for i = 25, 1, -1 do
                local m = G.ChatHistory:GetChatMessageAtIndex(i)
                if m then
                    local c = m.m_colour or {}
                    out(tag, "  chat", G.tostring(m.sender), "|", G.tostring(m.message),
                        G.string.format("| colour %.2f %.2f %.2f", c[1] or -1, c[2] or -1, c[3] or -1), "local", G.tostring(m.localonly))
                end
            end
        end
        for k = 0, 6 do
            later(60 + k * 15, function()
                local pairs_ = {}
                for key, p in G.pairs(K.pairs) do pairs_[#pairs_ + 1] = key .. "=" .. p.state .. G.string.format(" %.0f%%", p.progress * 100) end
                out("translation", "into", K.into, "pairs", G.table.concat(pairs_, ", "), "waiting", G.next(K.lines) ~= nil)
            end)
        end
        later(155, function() history("history") state("end") out("DONE") end)
    end)
end)
