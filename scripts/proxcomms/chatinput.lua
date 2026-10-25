-- DST's own chat line (ChatInputScreen), extended (AddClassPostConstruct): the mode where it said "say:" / "whisper:"
-- is a button (Whisper / Speak / Yell / Global; Tab, a click or the controller's misc button changes it), Enter says
-- the line in that mode (Speak and Yell through the server to the players near; Whisper and Global by DST's own Run,
-- untouched), our commands (/s /y /w /g, /pc ...) are run here and the game's own (/emote, /rescue ...) as before, Up / Down
-- bring back the last lines, and a button at the end opens Proximity Comms' settings.
local C = require "proxcomms/config"
local Strings = require "proxcomms/strings"
local L = Strings.L


return function(CL, openSettings)
    return function(self)
        local TextButton = require "widgets/textbutton"
        local vkb = TheInput ~= nil and TheInput:PlatformUsesVirtualKeyboard() or false

        -- DST's whisper key (U) opens a whisper line; otherwise this player's mode
        self.pc_mode = self.whisper and "w" or CL.mode

        local function label()
            if self.pc_modebtn then
                self.pc_modebtn:SetText(L(C.MODE_KEY[self.pc_mode]) .. ":")
                self.pc_modebtn:SetTextColour(unpack(CL.MODE_COLOUR[self.pc_mode]))
            end
            if self.chat_type then
                self.chat_type:SetString(L(C.MODE_KEY[self.pc_mode]) .. ":")
            end
        end

        -- (when it closed: the Enter that sent a line must not open it again)
        local close = self.Close
        self.Close = function(s, ...)
            CL.chatClosedAt = GetStaticTime and GetStaticTime() or GetTime()
            return close(s, ...)
        end

        local function refocus()
            if self.chat_edit then
                self.chat_edit:SetFocus()
                self.chat_edit:SetEditing(true)
            end
        end

        function self:PCCycle()
            self.pc_mode = C.nextMode(self.pc_mode)
            self.whisper = self.pc_mode == "w"
            CL.setMode(self.pc_mode)
            label()
            refocus()
        end

        if not vkb and self.chat_type then
            self.chat_type:Hide()
            self.pc_modebtn = self.root:AddChild(TextButton("pc_mode"))
            self.pc_modebtn:SetFont(TALKINGFONT)
            self.pc_modebtn:SetTextSize(30)
            self.pc_modebtn:SetPosition(-480, 0, 0)
            self.pc_modebtn:SetOnClick(function() self:PCCycle() end)
            self.pc_setbtn = self.root:AddChild(TextButton("pc_settings"))
            self.pc_setbtn:SetFont(TALKINGFONT)
            self.pc_setbtn:SetTextSize(22)
            self.pc_setbtn:SetText(L("TITLE"))
            self.pc_setbtn:SetPosition(445 + self.pc_setbtn:GetSize() * 0.5, 0, 0)
            self.pc_setbtn:SetOnClick(function()
                self:Close()
                openSettings(1)
            end)
            -- (clicking a button takes the focus from the line: that must not close the chat)
            local stop = self.chat_edit.OnStopForceEdit
            self.chat_edit.OnStopForceEdit = function(...)
                if (self.pc_modebtn and self.pc_modebtn.focus) or (self.pc_setbtn and self.pc_setbtn.focus) then return end
                if stop then return stop(...) end
            end
        end
        label()

        -- Tab is ours when no word prediction is up (DST's emoji / emote completion uses it then); a tab never
        -- goes into the text
        local predicting = function()
            local p = self.chat_edit and self.chat_edit.prediction_widget
            return p ~= nil and p.word_predictor ~= nil and p.word_predictor.prediction ~= nil
        end
        local onText = self.chat_edit.OnTextInput
        self.chat_edit.OnTextInput = function(edit, text, ...)
            if text == "\t" then return true end
            return onText(edit, text, ...)
        end
        -- (on the TEXT FIELD, not the screen: the chat line force-edits, and FrontEnd:OnRawKey then hands every key
        --  to the text field alone - a screen-level handler never saw Tab; found 2026-10-13)
        local s = self
        local editRawKey = self.chat_edit.OnRawKey
        self.chat_edit.OnRawKey = function(edit, key, down, ...)
            if s.runtask ~= nil then return true end
            if key == KEY_TAB and not predicting() then
                if down then s:PCCycle() end
                return true
            end
            if (key == KEY_UP or key == KEY_DOWN) and not predicting() and #CL.recall > 0 then
                if down then
                    local n = #CL.recall
                    if key == KEY_UP then
                        s.pc_recall = math.max(1, (s.pc_recall or (n + 1)) - 1)
                    else
                        s.pc_recall = math.min(n + 1, (s.pc_recall or (n + 1)) + 1)
                    end
                    edit:SetString(CL.recall[s.pc_recall] or "")
                end
                return true
            end
            return editRawKey(edit, key, down, ...)
        end

        -- controllers: the misc button changed say <-> whisper AND sent; now it changes the mode (A sends)
        local onControl = self.OnControl
        self.OnControl = function(s, control, down)
            if s.runtask == nil and not vkb and TheInput:ControllerAttached() and control == CONTROL_MENU_MISC_2 then
                if not down then s:PCCycle() end
                return true
            end
            return onControl(s, control, down)
        end
        local helpText = self.GetHelpText
        self.GetHelpText = function(s)
            local t = helpText(s)
            if TheInput:ControllerAttached() and not vkb then
                local id = TheInput:GetControllerID()
                t = TheInput:GetLocalizedControl(id, CONTROL_CANCEL) .. " " .. STRINGS.UI.HELP.BACK .. "  "
                    .. TheInput:GetLocalizedControl(id, CONTROL_MENU_MISC_2) .. " " .. L("MODE_HINT"):gsub("^Tab[:：]%s*", "") .. "  "
                    .. TheInput:GetLocalizedControl(id, CONTROL_ACCEPT) .. " " .. L(C.MODE_KEY[s.pc_mode])
            end
            return t
        end

        -- Enter: the line in this mode
        local run = self.Run
        self.Run = function(s)
            local str = s.chat_edit:GetString()
            str = str ~= nil and str:match("^%s*(.-%S)%s*$") or ""
            if str == "" then return end
            if str:sub(1, 1) == "/" then
                if CL.command(str) then return end
                CL.remember(str)
                return run(s)
            end
            CL.remember(str)
            -- (sent from a controller: the four dots first, as in the Teardown mod)
            if TheInput:ControllerAttached() and str:sub(1, #C.PAD_MARK) ~= C.PAD_MARK then
                str = C.PAD_MARK .. str
                s.chat_edit:SetString(str)
            end
            if s.pc_mode == "w" or s.pc_mode == "g" then
                -- (Whisper and Global are DST's own: its Run sends them, with any other mod's hooks on it)
                s.whisper = s.pc_mode == "w"
                return run(s)
            end
            if #str > C.MAX_LEN * 4 or (str.utf8len and str:utf8len() > C.MAX_LEN) then
                CL.system(L("TOO_LONG", C.MAX_LEN))
                return
            end
            CL.say(str, s.pc_mode)
        end
    end
end
