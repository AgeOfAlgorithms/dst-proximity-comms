-- The talk strip at the bottom of the screen while the talk key is held (as the Teardown mod's, voice.lua's
-- PC.drawTalk; the user, 2026-10-16): the four modes, the current one lit in its colour; talk key + Tab moves the light
-- to the next (it slides there, the new name pops). A dot left of them in the mode's colour - red and pulsing while
-- your voice is heard; under them what the microphone does and "V + Tab: change". It fades out just after the key is
-- let go. (The modes are the chat's: CL.mode, the voice's too.)
local Widget = require "widgets/widget"
local Text = require "widgets/text"
local NineSlice = require "widgets/nineslice"
local C = require "proxcomms/config"
local Settings = require "proxcomms/settings"
local Strings = require "proxcomms/strings"
local Keys = require "proxcomms/keys"
local L = Strings.L

local ATLAS = "images/pc_bubble.xml"   -- (the bubbles' white rounded box, tinted)
local CORNER = 12
local CW, CH, GAP = 104, 32, 6        -- a mode's cell
local DOT_W = 40                      -- the dot's room on the left
local PAD = 10
local SHOW = 0.3                      -- s it stays (fading) after the key is let go
local ANIM = 0.3                      -- s of a switch's slide and pop
local Y = 120                         -- its middle above the screen's bottom

local function easeOut(x)
    x = math.max(0, math.min(1, x))
    return 1 - (1 - x) * (1 - x) * (1 - x)
end

local function box(parent)
    local b = parent:AddChild(NineSlice(ATLAS))
    return b
end

local TalkStrip = Class(Widget, function(self, CL, K)
    Widget._ctor(self, "pc_talkstrip")
    self.CL, self.K = CL, K
    self:SetScaleMode(SCALEMODE_PROPORTIONAL)
    self:SetMaxPropUpscale(MAX_HUD_SCALE)
    self:SetHAnchor(ANCHOR_MIDDLE)
    self:SetVAnchor(ANCHOR_BOTTOM)
    self:SetClickable(false)
    self.root = self:AddChild(Widget("root"))
    local n = #C.MODES
    self.w = DOT_W + n * CW + (n - 1) * GAP + 2 * PAD
    self.h = CH + 2 * PAD + 22
    self.bg = box(self.root)
    self.bg:SetSize(self.w - 2 * CORNER, self.h - 2 * CORNER)
    self.light = box(self.root)
    self.light:SetSize(CW - 2 * CORNER, CH - 2 * CORNER)
    self.dot = box(self.root)
    self.dot:SetSize(1, 1)
    self.dot:SetScale(0.7, 0.7)
    self.labels = {}
    for i, m in ipairs(C.MODES) do
        local t = self.root:AddChild(Text(UIFONT, 26, L(C.MODE_KEY[m])))
        t:SetPosition(self:cellX(i), self:rowY(), 0)
        self.labels[i] = t
    end
    self.hint = self.root:AddChild(Text(UIFONT, 18, ""))
    self.hint:SetPosition(DOT_W / 2, -self.h / 2 + PAD + 8, 0)
    self.dot:SetPosition(-self.w / 2 + PAD + DOT_W / 2, self:rowY(), 0)
    self.mode, self.modeFrom, self.modeT = nil, nil, -1e9
    self.held, self.heldT = false, -1e9
    self:Hide()
    self:StartUpdating()
end)

-- (a mode's cell, from the strip's middle)
function TalkStrip:cellX(i)
    return -self.w / 2 + PAD + DOT_W + (i - 1) * (CW + GAP) + CW / 2
end

function TalkStrip:rowY()
    return self.h / 2 - PAD - CH / 2
end

-- what the microphone does now, for the line under the modes
function TalkStrip:what()
    local K = self.K
    if K.online ~= true then return L("TALK_NO_KOETAMA") end
    if K.talking and K.talking[self.CL.me()] then return L("TALK_TALKING") end
    local listen = K.listen and K.listen() or "push_to_talk"
    if listen == "off" then return L("TALK_MIC_OFF") end
    return listen == "always" and L("MIC_ALWAYS") or L("MIC_PTT")
end

function TalkStrip:OnUpdate(dt)
    local CL, K = self.CL, self.K
    local now = GetStaticTime and GetStaticTime() or GetTime()
    local held = K.talkKey == true
    if held ~= self.held then self.held, self.heldT = held, now end
    local idx = {}
    for i, m in ipairs(C.MODES) do idx[m] = i end
    if self.mode ~= CL.mode then
        if self.mode and held then self.modeFrom, self.modeT = self.mode, now end
        self.mode = CL.mode
    end
    local a = held and 1 or (1 - (now - self.heldT) / SHOW)
    if a <= 0 then
        if self.shown then self:Hide() end
        return
    end
    if not self.shown then self:Show() end
    local k = easeOut((now - self.modeT) / ANIM)
    local cur = idx[self.mode] or 2
    local from = idx[self.modeFrom or self.mode] or cur
    local pos = from + (cur - from) * k
    local col = CL.MODE_COLOUR[self.mode] or {1, 1, 1, 1}
    self.root:SetPosition(0, Y - (held and 0 or 10 * (1 - a)), 0)
    self.bg:SetTint(0, 0, 0, 0.62 * a)
    self.light:SetTint(col[1], col[2], col[3], 0.35 * a)
    self.light:SetPosition(self:cellX(1) + (pos - 1) * (CW + GAP), self:rowY(), 0)
    -- (the dot: red and pulsing while your voice is heard)
    local talking = K.talking and K.talking[CL.me()]
    if talking then
        local r = 0.7 + 0.25 * math.abs(math.sin(now * 9))
        self.dot:SetScale(r, r)
        self.dot:SetTint(1, 0.35, 0.3, a)
    else
        self.dot:SetScale(0.7, 0.7)
        self.dot:SetTint(col[1], col[2], col[3], a)
    end
    for i, t in ipairs(self.labels) do
        local mc = CL.MODE_COLOUR[C.MODES[i]] or {1, 1, 1, 1}
        if i == cur then
            t:SetColour(1, 1, 1, a)
            t:SetSize(28)
            local s = k < 1 and (1 + 0.35 * math.sin(k * math.pi)) or 1   -- (the new mode pops)
            t:SetScale(s, s)
        else
            t:SetColour(mc[1], mc[2], mc[3], 0.55 * a)
            t:SetSize(24)
            t:SetScale(1, 1)
        end
    end
    self.hint:SetColour(1, 1, 1, 0.65 * a)
    local what = self:what()
    if self.mode == "g" then what = what .. " - " .. L("TALK_GLOBAL") end
    self.hint:SetString(what .. "    " .. L("TALK_CHANGE", Keys.label(Settings.talkKey)))
end

return TalkStrip
