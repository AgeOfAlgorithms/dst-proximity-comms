-- Proximity Comms for Don't Starve Together: proximity text chat (Whisper / Speak / Yell / Global) with its own
-- bubbles and a per-player history, and - with the free companion app Koetama running on a player's PC - proximity
-- voice, live captions and offline translation. The code is in scripts/proxcomms/ (PROJECT.md has the design).
local G = GLOBAL
local C = require "proxcomms/config"
local T = require "proxcomms/text"
local Strings = require "proxcomms/strings"
local Settings = require "proxcomms/settings"
local S = require "proxcomms/server"
local CL = require "proxcomms/client"
local K = require "proxcomms/koetama"
local D = require "proxcomms/dummies"
local Keys = require "proxcomms/keys"
local W = require "proxcomms/wheel"
local AG = require "proxcomms/agents"
AG.S, AG.CL, AG.K = S, CL, K
S.A, K.A = AG, AG
local L = Strings.L

CL.K, CL.D, K.CL, K.D, D.CL = K, D, CL, D, CL
W.CL = CL

-- the controller wheel's pictures (tools/make_wheel_icons.py)
Assets = {
    G.Asset("ATLAS", "images/pc_wheel.xml"),
    G.Asset("IMAGE", "images/pc_wheel.tex"),
    G.Asset("ATLAS", "images/pc_bubble.xml"),
    G.Asset("IMAGE", "images/pc_bubble.tex"),
    G.Asset("FONT", MODROOT .. "fonts/pc_pangolin.zip"),
}
local WHEEL_ATLAS = "images/pc_wheel.xml"

-- the bubbles' font, "pc_pangolin" (fonts/pc_pangolin.zip, tools/make_font.py). A mod's font is one of its assets, which
-- the game loads with the mod's prefab each time it registers the mods' prefabs (the front end, every world) and drops
-- with them: so it is (re)loaded right after, and let go of right before - as mods that add fonts do. Its missing
-- letters (Chinese, Japanese, Korean, ∷, ♪) come from the game's fallback fonts, outlined as it is.
local FONT, FONT_FILE = "pc_pangolin", MODROOT .. "fonts/pc_pangolin.zip"
local registerPrefabs = G.ModManager.RegisterPrefabs
G.ModManager.RegisterPrefabs = function(self, ...)
    local r = {registerPrefabs(self, ...)}
    G.TheSim:UnloadFont(FONT)
    G.TheSim:LoadFont(FONT_FILE, FONT)
    G.TheSim:SetupFontFallbacks(FONT, G.DEFAULT_FALLBACK_TABLE_OUTLINE)
    return G.unpack(r)
end
local unloadPrefabsFromData = G.ModManager.UnloadPrefabsFromData
G.ModManager.UnloadPrefabsFromData = function(self, ...)
    G.TheSim:UnloadFont(FONT)
    return unloadPrefabsFromData(self, ...)
end
-- (WHEEL_FOLDERS' order in strings.lua; Players goes in after Things, as in the Teardown mod's wheel)
local FOLDER_KEYS = {"callouts", "questions", "replies", "things", "insults", "social", "survival"}
local ICON_SCALE = 0.95       -- (112 px pictures: about the size of DST's own wheel pictures)

G.pcall(function() Strings.pick(G.LOC and G.LOC.GetLanguage and G.LOC.GetLanguage()) end)

local function safe(where, fn)
    return function(...)
        local ok, err = G.pcall(fn, ...)
        if not ok then G.print("[Proximity Comms] " .. where .. ": " .. G.tostring(err)) end
    end
end

-- ---- RPCs: registered on every machine in the same order (DST numbers them by it)
local NS = C.NAMESPACE
AddModRPCHandler(NS, "hello", safe("hello", function(p) S.onHello(p) end))
AddModRPCHandler(NS, "say", safe("say", function(p, ...) S.onSay(p, ...) end))
AddModRPCHandler(NS, "live", safe("live", function(p, ...) S.onLive(p, ...) end))
AddModRPCHandler(NS, "vmode", safe("vmode", function(p, ...) S.onVmode(p, ...) end))
AddModRPCHandler(NS, "room", safe("room", function(p, ...) S.onRoom(p, ...) end))
AddModRPCHandler(NS, "ranges", safe("ranges", function(p, ...) S.onRanges(p, ...) end))
AddModRPCHandler(NS, "agent_down", safe("agent_down", function(p, ...) AG.onDown(p, ...) end))
AddModRPCHandler(NS, "llm", safe("llm", function(p, ...) AG.onLlm(p, ...) end))
AddModRPCHandler(NS, "heard", safe("heard", function(p, ...) AG.onHeard(p, ...) end))

AddClientModRPCHandler(NS, "state", safe("state", function(...) CL.onState(...) end))
AddClientModRPCHandler(NS, "line", safe("line", function(...) CL.onLine(...) end))
AddClientModRPCHandler(NS, "live", safe("live", function(...) CL.onLive(...) end))
AddClientModRPCHandler(NS, "room", safe("room", function(...) CL.onRoom(...) end))
AddClientModRPCHandler(NS, "global", safe("global", function(...) CL.onGlobal(...) end))
AddClientModRPCHandler(NS, "ranges", safe("ranges", function(...) CL.onRanges(...) end))
AddClientModRPCHandler(NS, "agent_up", safe("agent_up", function(...) AG.onUp(...) end))
AddClientModRPCHandler(NS, "agent_owner", safe("agent_owner", function(...) AG.onOwner(...) end))

AddShardModRPCHandler(NS, "vmode", safe("shard vmode", function(shard, ...) S.onShardVmode(shard, ...) end))
AddShardModRPCHandler(NS, "room_offer", safe("shard room_offer", function(shard, ...) S.onShardRoomOffer(shard, ...) end))
AddShardModRPCHandler(NS, "room_set", safe("shard room_set", function(shard, ...) S.onShardRoomSet(shard, ...) end))
AddShardModRPCHandler(NS, "global", safe("shard global", function(shard, ...) S.onShardGlobal(shard, ...) end))
AddShardModRPCHandler(NS, "ranges", safe("shard ranges", function(shard, ...) S.onShardRanges(shard, ...) end))
AddShardModRPCHandler(NS, "agent_up", safe("shard agent_up", function(shard, ...) AG.onShardUp(shard, ...) end))
AddShardModRPCHandler(NS, "agent_down", safe("shard agent_down", function(shard, ...) AG.onShardDown(shard, ...) end))
AddShardModRPCHandler(NS, "llm_cand", safe("shard llm_cand", function(shard, ...) AG.onShardCand(shard, ...) end))
AddShardModRPCHandler(NS, "llm_owner", safe("shard llm_owner", function(shard, ...) AG.onShardOwner(shard, ...) end))

-- ---- the server (each shard): the host's mod settings, and what an admin changed (kept with the world)
local function worldInit(inst)
    if not G.TheNet:GetIsServer() then return end
    S.configure(GetModConfigData("speak_range"), GetModConfigData("yell_range"), GetModConfigData("voice") ~= false,
        GetModConfigData("voice_region") or "", GetModConfigData("whisper_range"))
    inst:AddComponent("proxcomms_store")
    inst:DoPeriodicTask(1, safe("agents", function() AG.serverTick() end))
end
AddPrefabPostInit("forest", worldInit)
AddPrefabPostInit("cave", worldInit)

-- ---- agents (AI characters) for any mod: GLOBAL.ProxComms (server; README "Agents", proxcomms/agents.lua)
G.rawset(G, "ProxComms", {
    version = AG.API,
    agent = AG.define, event = AG.event, note = AG.note, say = AG.say, forget = AG.forget, result = AG.result,
    status = AG.status,
})

-- "Proximity Comms" in DST's Miscellaneous window (the command wheel's User Commands) and the pause menu's Server
-- Actions: it opens the settings (on this player's PC only)
AddUserCommand("proxcomms", {
    prettyname = L("TITLE"),
    desc = L("MENU_DESC"),
    permission = G.COMMAND_PERMISSION.USER,
    slash = false,
    usermenu = false,
    servermenu = true,
    params = {},
    vote = false,
    localfn = function() if CL.openSettings then CL.openSettings(1) end end,
})

-- ---- the client (a dedicated server has no player, no HUD, no Koetama)
if G.TheNet:IsDedicated() then return end

Settings.load(function() CL.mode = Settings.mode end)

local PCSettingsScreen = require "screens/pc_settingsscreen"
local function openSettings(page)
    if G.TheFrontEnd and G.ThePlayer then G.TheFrontEnd:PushScreen(PCSettingsScreen(CL, K, page)) end
end
CL.openSettings = openSettings

-- the bubbles over heads, and the tick (CL.tick: the hello, the voice mode, timed words, Koetama, test figures)
AddClassPostConstruct("screens/playerhud", function(self)
    local PCBubbles = require "widgets/pc_bubbles"
    CL.init()
    K.online, K.startAt, K.polling, K.urgent, K.retryAt = nil, nil, false, false, 0
    D.clear()
    self.pc_bubbles = self:AddChild(PCBubbles(self.owner, CL, K))
    self.pc_bubbles:MoveToBack()
    self.pc_talk = self:AddChild(require("widgets/pc_talkstrip")(CL, K))
    -- (once, a little after joining: the talk key must not be one of the game's own keys on this PC)
    self.inst:DoStaticTaskInTime(5, function()
        local use = Keys.gameUse(Keys.code(Settings.talkKey))
        if use then CL.system(L("KEY_CLASH", Keys.label(Settings.talkKey), use)) end
    end)
end)

-- DST's own Say and Whisper: the line over the head is drawn by the mod (same look, scrolling, docked when the
-- speaker is off screen). Nothing of DST's is re-implemented: the original Networking_Say (or whatever another mod
-- chained before us) runs with every argument, as it is - the history, the word filter, the talk sound and mouth,
-- whatever Klei adds later - and only the text it puts over the head is blanked, once, through the talker (old chat
-- mods that copied Networking_Say broke when Klei changed it in 2022, e.g. Workshop 2531534743).
AddComponentPostInit("talker", function(self)
    local say = self.Say
    self.Say = function(t, script, ...)
        if t.pc_blank then
            t.pc_blank = nil
            script = ""
        end
        return say(t, script, ...)
    end
end)

local Networking_Say = G.Networking_Say
G.Networking_Say = function(guid, userid, name, prefab, message, colour, whisper, isemote, ...)
    local entity = G.Ents[guid]
    local talker = entity ~= nil and entity.components ~= nil and entity.components.talker or nil
    local ours = G.ThePlayer ~= nil and G.ThePlayer.HUD ~= nil and Settings.bubbles and not isemote and talker ~= nil
        and type(message) == "string"
    if ours then talker.pc_blank = true end
    local results = {Networking_Say(guid, userid, name, prefab, message, colour, whisper, isemote, ...)}
    local drawn = false
    if ours then
        if talker.pc_blank then
            talker.pc_blank = nil                    -- (DST did not put it over the head: neither do we)
        else
            local shown = message
            if talker.mod_str_fn then
                local ok, s = G.pcall(talker.mod_str_fn, message)
                if ok and type(s) == "string" then shown = s end
            end
            G.pcall(CL.onNative, userid, name, shown, colour, whisper)
            drawn = true
        end
    end
    -- a whisper is the mod's in every case (its range, its history line - DST's is kept out, below), bubbles on or off;
    -- not one DST turned away (too long)
    if not drawn and whisper and not isemote and G.ThePlayer ~= nil and type(message) == "string"
        and T.len(message) <= (G.MAX_CHAT_INPUT_LENGTH or C.MAX_LEN) then
        G.pcall(CL.onNative, userid, name, message, colour, true)
    end
    -- (my own Whisper / Global line, back from DST: to the server for the agents that hear it - it does not see it)
    if not isemote and G.ThePlayer ~= nil and userid == CL.me() and type(message) == "string" then
        CL.rpc("heard", message, whisper == true)
    end
    return G.unpack(results)
end

-- DST's own history line for a whisper: left out (DST adds the whole line for anyone within 40 units; the mod adds
-- it as heard, in its Whisper range, garbled "(far)" in its buffer - CL.onWhisper)
local OnSay = G.ChatHistory.OnSay
G.ChatHistory.OnSay = function(self, guid, userid, netid, name, prefab, message, colour, whisper, isemote, ...)
    if whisper and not isemote and G.ThePlayer ~= nil then return end
    return OnSay(self, guid, userid, netid, name, prefab, message, colour, whisper, isemote, ...)
end

-- the chat's own colour for our lines (a Yell orange, a garbled line grey, a translation pink)
local GenerateChatMessage = G.ChatHistory.GenerateChatMessage
G.ChatHistory.GenerateChatMessage = function(self, ...)
    local m = GenerateChatMessage(self, ...)
    if CL.histColour and m then m.m_colour = CL.histColour end
    CL.lastHistMsg = m                       -- (the message just made: a line's own, to shrink once it is translated)
    return m
end

-- the history's rows (the HUD's and the scrollable one's alike): a translated line's original smaller than its
-- translation under it (the user, 2026-10-16) - the original's colour table is marked pc_small (CL.translated)
AddClassPostConstruct("widgets/redux/chatline", function(self)
    local setChatData = self.SetChatData
    self.SetChatData = function(s, kind, alpha, message, m_colour, ...)
        local r = setChatData(s, kind, alpha, message, m_colour, ...)
        if s.message and alpha and alpha > 0 and message then
            local small = type(m_colour) == "table" and m_colour.pc_small == true
            if small ~= (s.pc_small == true) then
                s.pc_small = small
                s.message:SetSize(small and CL.HIST_SIZE * CL.HIST_ORIGINAL or CL.HIST_SIZE)
            end
            s.message:SetPosition(s.message:GetRegionSize() * 0.5 - 290, 0)   -- (as DST places it, at its size)
        end
        return r
    end
end)

-- the chat line
AddClassPostConstruct("screens/chatinputscreen", require("proxcomms/chatinput")(CL, openSettings))

-- push to talk: the talk key held while playing (not while typing or in a menu)
local function talkKeyCode()
    return Keys.code(Settings.talkKey) or G.KEY_V
end
-- Enter opens the chat line (the user, 2026-10-13: Enter, as in Teardown, and DST's Y / U no longer - the setting
-- "Open the chat with" gives them back). Only while playing: not over another screen, not while a text field (the
-- crafting search) has the keys, not right after the Enter that sent a line. It opens on the key's RELEASE, a frame
-- later, so no part of this Enter reaches the new chat line (its text field would take it as "send" and close).
local function chatMayOpen()
    local hud = G.ThePlayer and G.ThePlayer.HUD
    if not (Settings.enterChat and hud and G.TheFrontEnd:GetActiveScreen() == hud and not hud:IsChatInputScreenOpen()) then return false end
    local focus = G.TheFrontEnd.GetFocusWidget and G.TheFrontEnd:GetFocusWidget()
    if focus and (focus.editing or (focus.inst and focus.inst.TextEditWidget)) then return false end
    local now = G.GetStaticTime and G.GetStaticTime() or G.GetTime()
    return not (CL.chatClosedAt and now - CL.chatClosedAt < 0.4)
end
local function openChatOnEnter()
    if not chatMayOpen() then return end
    G.ThePlayer:DoStaticTaskInTime(0, function()
        if chatMayOpen() then G.TheFrontEnd:PushScreen(require("screens/chatinputscreen")(false)) end
    end)
end

if G.TheInput then G.TheInput:AddKeyHandler(function(key, down)
    if key == G.KEY_ENTER then
        if not down then openChatOnEnter() end
        return
    end
    if key ~= talkKeyCode() then return end
    if not down then K.setTalk(false) return end
    local hud = G.ThePlayer and G.ThePlayer.HUD
    if hud and G.TheFrontEnd:GetActiveScreen() == hud and not hud:IsChatInputScreenOpen() then K.setTalk(true) end
end) end

-- the message being built on Quick chat's wheels (proxcomms/wheel.lua): the game's side
W.env = {
    now = function() return G.GetStaticTime() end,
    wheel = function()
        local hud = G.ThePlayer and G.ThePlayer.HUD
        return hud and hud.controls and hud.controls.commandwheel
    end,
}
W.env.inQuick = function()
    local hud = G.ThePlayer and G.ThePlayer.HUD
    local w = W.env.wheel()
    return hud ~= nil and w ~= nil and hud:IsCommandWheelOpen() and type(w.pc_dataset) == "string" and w.pc_dataset:sub(1, 3) == "pc_"
end
W.env.atMain = function()
    local w = W.env.wheel()
    return w ~= nil and w.pc_dataset == "pc_quick"
end
-- the picked item's data (its widget is the wheel's focus)
W.env.item = function()
    local w = W.env.wheel()
    local focus = w and w.selected_label and w.selected_label._currentwidget
    if not focus then return nil end
    for _, v in ipairs(w.items[w.pc_dataset] or {}) do
        if v.widget == focus then return v end
    end
    return nil
end
W.env.toMain = function()
    local w = W.env.wheel()
    if not w then return end
    w:Close()
    w:Open("pc_quick")
end
-- a folder's wheel (as DST's wheel opens a nested one: close, then open it)
W.env.open = function(name)
    local w = W.env.wheel()
    if not w then return end
    w:Close()
    w:Open(name)
end
W.env.close = function()
    local hud = G.ThePlayer and G.ThePlayer.HUD
    if hud then hud:CloseCommandWheel() end
end
W.env.back = function()
    local w = W.env.wheel()
    if not w then return end
    local up = w.pc_dataset ~= "pc_quick" and "pc_quick" or nil
    w:Close()
    w:Open(up)
end
W.env.refresh = function()
    local w = W.env.wheel()
    if not (w and w.pc_draft) then return end
    local t = W.text()
    if t == "" then w.pc_draft:Hide() return end
    w.pc_draft:SetMultilineTruncatedString(t, 3, 560, nil, true)
    w.pc_draft:Show()
end
do
    local tick = CL.tick
    CL.tick = function(dt)
        tick(dt)
        W.tick()
    end
end

-- (the wheel's centre: the chat mode, in its colour)
function CL.showWheelMode(wheel)
    if not (wheel and wheel.pc_mode) then return end
    local text, colour = CL.modeLine()
    wheel.pc_mode:SetString(text)
    wheel.pc_mode:SetColour(G.unpack(colour))
    wheel.pc_mode:MoveToFront()
end

-- the controller's command wheel: a "Quick chat" folder (lines by topic, the other players' names, the mode, the
-- settings); a line goes in the current mode
local R, F = 175, 178

-- (every Quick chat item shows its label all the time, under its picture - the user, 2026-10-13; DST's wheel shows only
--  the focused item's)
local function labelled(item)
    local text = item.label
    item.postinit = function(w)
        local t = w:AddChild(require("widgets/text")(G.UIFONT, 22))
        t:SetMultilineTruncatedString(text, 2, 150, nil, true)
        t:SetPosition(0, -70)
        t:SetClickable(false)
    end
    return item
end

-- a line or a player's name on the wheel: on a controller, X / A take it into the message (W, proxcomms/wheel.lua);
-- with a mouse, a click says it at once. (ondown true: DST's wheel would hide the other items on A, as for a final
-- choice)
local function piece(text, icon)
    return labelled({label = text, pc_text = text, atlas = WHEEL_ATLAS, normal = icon, widget_scale = ICON_SCALE,
        ondown = function() return G.TheInput:ControllerAttached() end,
        execute = function()
            if G.TheInput:ControllerAttached() then
                W.add(text)
                return true                                  -- (the wheel stays open)
            end
            CL.say(text, CL.mode)
        end})
end

local function quickChat(CL)
    local folders = {}
    for i, f in ipairs(Strings.get("WHEEL_FOLDERS")) do
        local lines = {}
        local key = FOLDER_KEYS[i] or "callouts"
        for j, line in ipairs(f[2]) do
            lines[#lines + 1] = piece(line, "pc_" .. key .. "_" .. j .. ".tex")
        end
        folders[#folders + 1] = labelled({label = f[1], nestedwheel = {name = "pc_folder" .. i, items = lines, r = R, f = F},
            atlas = WHEEL_ATLAS, normal = "pc_" .. key .. ".tex", widget_scale = ICON_SCALE})
    end
    local people = {}
    for _, p in ipairs(CL.others()) do
        if #people < 8 then
            local n = p.name
            people[#people + 1] = piece(n, "pc_questions_1.tex")      -- (a person)
        end
    end
    if #people > 0 then
        table.insert(folders, math.min(5, #folders + 1), labelled({label = G.STRINGS.UI.COMMANDWHEEL.PLAYERLIST or "Players",
            nestedwheel = {name = "pc_people", items = people, r = R, f = F},
            atlas = WHEEL_ATLAS, normal = "pc_players.tex", widget_scale = ICON_SCALE}))
    end
    -- (the chat mode is not an item: it shows in the wheel's centre, LT / RT change it; the settings are in the
    --  Miscellaneous window - the user, 2026-10-13)
    return {label = L("WHEEL"), nestedwheel = {name = "pc_quick", items = folders, r = R, f = F},
        atlas = WHEEL_ATLAS, normal = "pc_quick.tex", widget_scale = ICON_SCALE}
end

AddClassPostConstruct("widgets/controls", function(self)
    local build = self.BuildCommandWheel
    self.BuildCommandWheel = function(s, ...)
        build(s, ...)
        -- (its help bar names the triggers: they change the chat mode while it is open; its centre shows the mode)
        local wheel = s.commandwheel
        if wheel and not wheel.pc_help then
            wheel.pc_help = true
            wheel.pc_mode = wheel:AddChild(require("widgets/text")(G.UIFONT, 36, ""))
            wheel.pc_mode:SetClickable(false)
            wheel.pc_mode:SetPosition(0, 0)
            wheel.pc_draft = wheel:AddChild(require("widgets/text")(G.UIFONT, 32, ""))
            wheel.pc_draft:SetClickable(false)
            wheel.pc_draft:SetPosition(0, 58)
            local open = wheel.Open
            wheel.Open = function(w, name, ...)
                w.pc_dataset = name or "root"
                CL.showWheelMode(w)
                local r = open(w, name, ...)
                W.env.refresh()
                -- (Quick chat's own wheels label every item: DST's moving label would say the focused one twice)
                if w.selected_label then
                    if type(name) == "string" and name:sub(1, 3) == "pc_" then w.selected_label:Hide() else w.selected_label:Show() end
                end
                return r
            end
            local help = wheel.GetHelpText
            wheel.GetHelpText = function(w, ...)
                local id = G.TheInput:GetControllerID()
                local function key(c) return G.TheInput:GetLocalizedControl(id, c) end
                local modes = key(G.CONTROL_OPEN_CRAFTING) .. "/" .. key(G.CONTROL_OPEN_INVENTORY) .. " " .. L("ROW_MODE")
                if type(w.pc_dataset) == "string" and w.pc_dataset:sub(1, 3) == "pc_" then
                    return key(G.CONTROL_MENU_MISC_1) .. " " .. L("WHEEL_ADD") .. "  " .. key(G.CONTROL_MENU_MISC_2) .. " "
                        .. L("WHEEL_UNDO") .. "  " .. key(G.CONTROL_ACCEPT) .. " " .. L("WHEEL_SEND") .. "  "
                        .. key(G.CONTROL_CANCEL) .. " " .. L("WHEEL_BACK") .. "  " .. L("WHEEL_HOLD", key(G.CONTROL_CANCEL))
                        .. " " .. L("WHEEL_CLOSE") .. "  " .. modes
                end
                local twice = key(G.CONTROL_OPEN_COMMAND_WHEEL)
                return (help(w, ...) or "") .. "  " .. twice .. twice .. " " .. L("WHEEL") .. "  " .. modes
            end
        end
        local root = s.commandwheel and s.commandwheel.items and s.commandwheel.items.root
        if not root then return end
        local items = {}
        for i, v in ipairs(root) do items[i] = v end
        local ok, item = G.pcall(quickChat, CL)
        if ok then items[#items + 1] = item end
        s.commandwheel:SetItems(items, R, F)
    end
    if self.commandwheel then self:BuildCommandWheel() end
end)

-- (the wheel is built again each time it opens: the players and the mode are up to date)
AddClassPostConstruct("screens/playerhud", function(self)
    -- (Enter is the chat's key: DST's Chat and Whisper keys, Y and U, do nothing while it is - a keyboard's only;
    --  a controller keeps its own way in)
    -- (the command wheel open, on a controller: the triggers cycle the chat mode - RT next, LT back - and open
    --  neither crafting nor the inventory meanwhile; the user, 2026-10-13)
    local onControl = self.OnControl
    self.OnControl = function(s, control, down, ...)
        if (control == G.CONTROL_TOGGLE_SAY or control == G.CONTROL_TOGGLE_WHISPER) and Settings.enterChat
            and not G.TheInput:ControllerAttached() then
            return true
        end
        if G.TheInput:ControllerAttached() and W.control(control, down) then return true end
        -- (the talk key held: Tab changes the mode, and DST's player list stays shut)
        if control == G.CONTROL_SHOW_PLAYER_STATUS and CL.talkTab(down) then return true end
        -- (the command wheel's button pressed twice: straight to Quick chat; once: DST's wheel, untouched)
        if control == G.CONTROL_OPEN_COMMAND_WHEEL and G.TheInput:ControllerAttached()
            and W.wheelButton(down, s:IsCommandWheelOpen(), G.GetStaticTime()) then
            local w = s.controls and s.controls.commandwheel
            if w and w.items and w.items.pc_quick then
                w:Close()
                w:Open("pc_quick")
            end
            return true
        end
        if (control == G.CONTROL_OPEN_INVENTORY or control == G.CONTROL_OPEN_CRAFTING or control == G.CONTROL_MENU_R2
            or control == G.CONTROL_MENU_L2) and s:IsCommandWheelOpen() and G.TheInput:ControllerAttached() then
            if down then
                local fwd = control == G.CONTROL_OPEN_INVENTORY or control == G.CONTROL_MENU_R2
                CL.setMode(fwd and C.nextMode(CL.mode) or C.prevMode(CL.mode))
                CL.showWheelMode(s.controls and s.controls.commandwheel)
            end
            return true
        end
        return onControl(s, control, down, ...)
    end
    local closeWheel = self.CloseCommandWheel
    self.CloseCommandWheel = function(s, ...)
        W.clear()
        return closeWheel(s, ...)
    end
    local open = self.OpenCommandWheel
    self.OpenCommandWheel = function(s, ...)
        if s.controls and s.controls.BuildCommandWheel then s.controls:BuildCommandWheel(s.is_split_screen) end
        return open(s, ...)
    end
end)
