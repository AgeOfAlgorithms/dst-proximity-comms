-- Proximity Comms' settings: three pages (Chat, Voice, Translate), mouse or controller (DST's own spinners and
-- buttons; focus moves with the D-pad, B closes). Opened with /pc settings, the button on the chat line, or the
-- controller's command wheel (Quick chat -> Proximity Comms).
local Screen = require "widgets/screen"
local Widget = require "widgets/widget"
local Text = require "widgets/text"
local TEMPLATES = require "widgets/redux/templates"
local C = require "proxcomms/config"
local Settings = require "proxcomms/settings"
local Strings = require "proxcomms/strings"
local Keys = require "proxcomms/keys"
local L = Strings.L

local LANGS = {
    {"", nil}, {"en", "English"}, {"zh", "中文 (普通话)"}, {"ru", "Русский"}, {"es", "Español"}, {"fr", "Français"},
    {"de", "Deutsch"}, {"it", "Italiano"}, {"pt", "Português"}, {"nl", "Nederlands"}, {"pl", "Polski"}, {"uk", "Українська"},
    {"yue", "粵語"}, {"ja", "日本語"}, {"ko", "한국어"}, {"auto", "Auto"}, {"cs", "Čeština"}, {"sk", "Slovenčina"},
    {"ro", "Română"}, {"hr", "Hrvatski"}, {"bg", "Български"}, {"fi", "Suomi"}, {"sv", "Svenska"}, {"hu", "Magyar"},
    {"da", "Dansk"}, {"et", "Eesti"}, {"lv", "Latviešu"}, {"lt", "Lietuvių"}, {"sl", "Slovenščina"}, {"el", "Ελληνικά"},
}

local ROW_W, ROW_H = 640, 34
local PER_PAGE = 8              -- players on one Players page

local PCSettingsScreen = Class(Screen, function(self, CL, K, page)
    Screen._ctor(self, "PCSettingsScreen")
    self.CL, self.K = CL, K
    self.page = page or 1

    self.black = self:AddChild(TEMPLATES.BackgroundTint(0.5))
    self.root = self:AddChild(Widget("root"))
    self.root:SetScaleMode(SCALEMODE_PROPORTIONAL)
    self.root:SetHAnchor(ANCHOR_MIDDLE)
    self.root:SetVAnchor(ANCHOR_MIDDLE)

    self.window = self.root:AddChild(TEMPLATES.RectangleWindow(1000, 620, L("TITLE")))
    self.window:SetScale(1, 1)          -- (the template draws at 0.7: too small for the Voice page's rows)
    self.tabs = {}
    local names = {L("PAGE_CHAT"), L("PAGE_VOICE"), L("PAGE_PLAYERS"), L("PAGE_TRANSLATE")}
    for i, n in ipairs(names) do
        local b = self.root:AddChild(TEMPLATES.StandardButton(function() self:ShowPage(i) end, n, {190, 45}))
        b:SetPosition((i - (#names + 1) / 2) * 200, 205)        -- (under the window's title: at 250 the four tabs hid it, 2026-10-16)
        self.tabs[i] = b
    end
    for i, b in ipairs(self.tabs) do
        if self.tabs[i - 1] then b:SetFocusChangeDir(MOVE_LEFT, self.tabs[i - 1]) end
        if self.tabs[i + 1] then b:SetFocusChangeDir(MOVE_RIGHT, self.tabs[i + 1]) end
    end
    self.close = self.root:AddChild(TEMPLATES.StandardButton(function() self:Close() end, L("CLOSE"), {190, 45}))
    self.close:SetPosition(0, -285)
    self:ShowPage(self.page)
end)

function PCSettingsScreen:Close()
    TheFrontEnd:PopScreen(self)
end

function PCSettingsScreen:OnControl(control, down)
    -- (while a talk key is being bound, the keyboard is the key's; Esc - also the game's Cancel - ends the binding
    --  and must not close the screen as it is let go)
    if self.binding then
        if control == CONTROL_CANCEL and not down then self:EndBinding() end
        return true
    end
    if control == CONTROL_CANCEL and self.bindEndedAt and GetStaticTime() - self.bindEndedAt < 0.5 then return true end
    if PCSettingsScreen._base.OnControl(self, control, down) then return true end
    if not down and control == CONTROL_CANCEL then
        self:Close()
        return true
    end
    return false
end

-- the talk key: press the button, then the key (Esc: keep the old one). Refused: the chat's keys, and a key the game
-- itself is bound to on this PC (its Controls screen)
function PCSettingsScreen:KeyRow()
    local w = Widget("keyrow")
    w.label = w:AddChild(Text(CHATFONT, 24, L("ROW_KEY")))
    w.label:SetPosition(-155, 0)
    w.label:SetRegionSize(330, ROW_H)
    w.label:SetHAlign(ANCHOR_RIGHT)
    w.label:SetColour(unpack(UICOLOURS.GOLD))
    w.button = w:AddChild(TEMPLATES.StandardButton(function() self:StartBinding() end, Keys.label(Settings.talkKey), {300, 40}))
    w.button:SetPosition(170, 0)
    w.focus_forward = w.button
    self.keyRow = w
    return w
end

function PCSettingsScreen:StartBinding()
    self.binding = true
    self.keyRow.button:SetText(L("PRESS_KEY"))
    if self.keyNote then self.keyNote:SetString("") end
end

function PCSettingsScreen:EndBinding(note)
    self.binding = false
    self.bindEndedAt = GetStaticTime()
    if self.keyRow then self.keyRow.button:SetText(Keys.label(Settings.talkKey)) end
    if self.keyNote then self.keyNote:SetString(note or "") end
end

function PCSettingsScreen:OnRawKey(key, down)
    if self.binding then
        if down then
            local name = Keys.nameOf(key)
            local why = "unknown"
            if name then why = Keys.refusal(name) end          -- (nil: the key is free)
            if key == KEY_ESCAPE or why == "unknown" then
                self:EndBinding()
            elseif why == "reserved" then
                self:EndBinding(L("KEY_RESERVED", Keys.label(name)))
            elseif why then
                self:EndBinding(L("KEY_TAKEN", Keys.label(name), why))
            else
                Settings.talkKey = name
                Settings.save()
                self:EndBinding(L("KEY_SET", Keys.label(name)))
            end
        end
        return true
    end
    return PCSettingsScreen._base.OnRawKey(self, key, down)
end

function PCSettingsScreen:GetHelpText()
    local id = TheInput:GetControllerID()
    return TheInput:GetLocalizedControl(id, CONTROL_CANCEL) .. " " .. STRINGS.UI.HELP.BACK
end

-- a row: a label and a spinner over options {{text, data}}; changed(data)
function PCSettingsScreen:Spinner(label, options, current, changed)
    local data = {}
    for _, o in ipairs(options) do data[#data + 1] = {text = o[1], data = o[2]} end
    local w = TEMPLATES.LabelSpinner(label, data, 330, 300, ROW_H, 10, CHATFONT, 24, 0, function(v) changed(v) end)
    w.spinner:SetSelected(current)
    return w
end

function PCSettingsScreen:Line(text, colour, size)
    local t = Text(CHATFONT, size or 22, text)
    t:SetRegionSize(ROW_W + 200, ROW_H * 1.5)
    t:EnableWordWrap(true)
    t:SetColour(unpack(colour or UICOLOURS.GOLD_UNIMPORTANT or {0.8, 0.75, 0.6, 1}))
    return t
end

local function percents(lo, hi, step)
    local out = {}
    for v = lo, hi, step do out[#out + 1] = {v .. "%", v / 100} end
    return out
end

-- a player's row on the Players page: their volume (0-150 %), and Reset (100 %)
function PCSettingsScreen:PlayerRow(p)
    local Settings_, CL = Settings, self.CL
    local uid = p.uid
    local row = Widget("player_row")
    local name = p.name .. (CL.isMuted(uid) and ("  " .. L("MUTED_TAG")) or "")
    local spin = row:AddChild(self:Spinner(name, percents(0, Settings_.VOL_MAX * 100, 10),
        math.floor(Settings_.volumeOf(uid) * 10 + 0.5) / 10,
        function(v) Settings_.names[uid] = p.name Settings_.setVolume(uid, v) end))
    local reset = row:AddChild(TEMPLATES.StandardButton(function()
        Settings_.names[uid] = p.name
        Settings_.setVolume(uid, 1)
        spin.spinner:SetSelected(1)
    end, L("RESET"), {120, 40}))
    reset:SetPosition(400, 0)
    row.spin, row.reset = spin, reset
    row.focus_forward = spin
    return row
end

function PCSettingsScreen:ShowPage(i)
    self.page = i
    if self.body then self.body:Kill() end
    self.body = self.root:AddChild(Widget("body"))
    self.rows = {}
    local CL, K = self.CL, self.K
    local y = 155
    local function add(w, focusable, h)
        self.body:AddChild(w)
        w:SetPosition(0, y)
        y = y - (h or ROW_H) - 4
        if focusable ~= false then self.rows[#self.rows + 1] = w end
        return w
    end
    self.keyRow, self.keyNote, self.binding = nil, nil, false
    if i == 1 then
        local modes = {}
        for _, m in ipairs(C.MODES) do modes[#modes + 1] = {L(C.MODE_KEY[m]), m} end
        add(self:Spinner(L("ROW_MODE"), modes, CL.mode, function(v) CL.setMode(v) end))
        add(self:Spinner(L("ROW_ENTER"), {{L("KEY_ENTER"), true}, {L("KEY_GAME"), false}}, Settings.enterChat,
            function(v) Settings.enterChat = v Settings.save() end))
        add(self:Spinner(L("ROW_BUBBLES"), {{L("SHOW"), true}, {L("HIDE"), false}}, Settings.bubbles,
            function(v) Settings.bubbles = v Settings.save() end))
        add(self:Spinner(L("ROW_STYLE"), {{L("STYLE_CLEAR"), "clear"}, {L("STYLE_GAME"), "game"}}, Settings.bubbleStyle,
            function(v) Settings.bubbleStyle = v Settings.save() end))
        local opacities = {}
        for v = 0, 100, 10 do opacities[#opacities + 1] = {v .. "%", v / 100} end
        add(self:Spinner(L("ROW_OPACITY"), opacities, math.floor(Settings.bubbleOpacity * 10 + 0.5) / 10,
            function(v) Settings.bubbleOpacity = v Settings.save() end))
        local sizes = {}
        for v = 70, 160, 10 do sizes[#sizes + 1] = {v .. "%", v / 100} end
        add(self:Spinner(L("ROW_TEXT"), sizes, math.floor(Settings.textSize * 10 + 0.5) / 10,
            function(v) Settings.textSize = v Settings.save() end))
        local r = CL.ranges
        add(self:Line(L("ROW_RANGES") .. ": " .. L("RANGES", r.whisperTiles, C.outerTiles(r, "w"), r.speakTiles,
            C.outerTiles(r, "s"), r.yellTiles, C.outerTiles(r, "y"))), false, ROW_H * 1.25)
        local me = CL.client(CL.me())
        if me and me.admin then
            local tiles = {}
            for v = C.TILES_MIN, C.TILES_MAX do tiles[#tiles + 1] = {tostring(v), v} end
            local wh, sp, ye = r.whisperTiles, r.speakTiles, r.yellTiles
            -- (the server keeps Whisper < Speak < Yell, C.ranges)
            local function send() CL.rpc("ranges", sp, math.max(ye, sp + 1), math.min(wh, sp - 1)) end
            add(self:Spinner(L("ROW_WHISPER"), tiles, wh, function(v) wh = v send() end))
            add(self:Spinner(L("ROW_SPEAK"), tiles, sp, function(v) sp = v send() end))
            add(self:Spinner(L("ROW_YELL"), tiles, ye, function(v) ye = v send() end))
        end
    elseif i == 2 then
        if K.online ~= true then
            add(self:Line(L("NEED_KOETAMA"), UICOLOURS.WHITE), false, ROW_H * 1.5)
            add(TEMPLATES.StandardButton(function() VisitURL(C.KOETAMA_URL) end, L("OPEN_PAGE"), {260, 45}))
        else
            add(self:Line(K.statusLines()[1], UICOLOURS.WHITE), false, ROW_H * 1.5)
        end
        add(self:Spinner(L("ROW_MIC"), {{L("MIC_AUTO"), "auto"}, {L("MIC_PTT"), "ptt"}, {L("MIC_ALWAYS"), "always"}, {L("MIC_OFF"), "off"}},
            Settings.mic, function(v) Settings.mic = v Settings.save() K.poke() end))
        add(self:KeyRow())
        self.keyNote = add(self:Line("", nil, 18), false, ROW_H * 0.8)
        add(self:Spinner(L("ROW_VOLUME"), percents(0, 100, 10), math.floor(Settings.voiceVolume * 10 + 0.5) / 10,
            function(v) Settings.voiceVolume = v Settings.save() end))
        add(self:Spinner(L("ROW_LIVE"), {{L("ON"), true}, {L("OFF"), false}}, Settings.live,
            function(v) Settings.live = v Settings.save() end))
        local langs = {}
        for _, l in ipairs(LANGS) do langs[#langs + 1] = {l[2] or L("LANG_GAME"), l[1]} end
        add(self:Spinner(L("ROW_LANG"), langs, Settings.lang, function(v) Settings.lang = v Settings.save() K.poke() end))
        add(self:Line(L("K_PRIVACY"), nil, 18), false, ROW_H * 1.5)
    elseif i == 3 then
        -- every other player's voice volume, 0-150 % (100 %: as they are), only for you - as the Teardown mod's Players
        -- (the user, 2026-10-16); PER_PAGE at a time, with pages beyond. Their lines and voice muted: "/pc mute".
        add(self:Line(L("PLAYERS_HEAD"), UICOLOURS.WHITE), false, ROW_H * 1.2)
        local others = CL.others()
        table.sort(others, function(a, b) return a.name:lower() < b.name:lower() end)
        if #others == 0 then add(self:Line(L("PLAYERS_NONE")), false) end
        local pages = math.max(1, math.ceil(#others / PER_PAGE))
        self.playersPage = math.max(1, math.min(pages, self.playersPage or 1))
        local first = (self.playersPage - 1) * PER_PAGE
        for k = first + 1, math.min(#others, first + PER_PAGE) do
            add(self:PlayerRow(others[k]))
        end
        if pages > 1 then
            local nav = Widget("players_nav")
            local prev = nav:AddChild(TEMPLATES.StandardButton(function() self.playersPage = self.playersPage - 1 self:ShowPage(3) end,
                "<", {70, 40}))
            local next_ = nav:AddChild(TEMPLATES.StandardButton(function() self.playersPage = self.playersPage + 1 self:ShowPage(3) end,
                ">", {70, 40}))
            local label = nav:AddChild(Text(CHATFONT, 22, L("PLAYERS_PAGE", self.playersPage, pages)))
            prev:SetPosition(-110, 0)
            next_:SetPosition(110, 0)
            if self.playersPage <= 1 then prev:Disable() end
            if self.playersPage >= pages then next_:Disable() end
            nav.focus_forward = self.playersPage < pages and next_ or prev
            add(nav)
        end
    else
        if K.online ~= true then
            add(self:Line(L("NEED_KOETAMA"), UICOLOURS.WHITE), false, ROW_H * 1.5)
            add(TEMPLATES.StandardButton(function() VisitURL(C.KOETAMA_URL) end, L("OPEN_PAGE"), {260, 45}))
        else
            local head = K.into == nil and L("TR_WAIT") or (K.into == "" and L("TR_OFF") or L("TR_INTO", Strings.langName(K.into)))
            add(self:Line(head, UICOLOURS.WHITE), false, ROW_H * 1.5)
            local states = Strings.get("TR_STATES")
            for _, key in ipairs(K.pairKeys) do
                local p = K.pairs[key]
                local st = states[p.state] or p.state
                if p.state == "downloading" then st = string.format(st, math.floor(p.progress * 100)) end
                add(self:Line(L("TR_PAIR", p.from, p.to, st)), false)
            end
            add(self:Line(L("TR_CHOOSE"), nil, 20), false, ROW_H * 1.5)
        end
    end
    -- focus: tabs -> rows -> Close
    local first = self.rows[1] or self.close
    for _, b in ipairs(self.tabs) do b:SetFocusChangeDir(MOVE_DOWN, first) end
    for k, w in ipairs(self.rows) do
        w:SetFocusChangeDir(MOVE_UP, self.rows[k - 1] or self.tabs[self.page])
        w:SetFocusChangeDir(MOVE_DOWN, self.rows[k + 1] or self.close)
    end
    self.close:SetFocusChangeDir(MOVE_UP, self.rows[#self.rows] or self.tabs[self.page])
    self.default_focus = first
    if TheInput:ControllerAttached() then first:SetFocus() end
end

return PCSettingsScreen
