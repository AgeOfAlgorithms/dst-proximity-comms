-- The speech bubbles over heads: a see-through dark box (its opacity a setting) in Pangolin, with a tail on the side
-- facing the speaker, following them every frame (the "Clear" style), or DST's own look (TALKINGFONT, no box; the
-- "Game's" style, as FollowText draws chat). Plus:
--   - the garbled letters (⬚) of a Speak / Yell line heard from its buffer, revealed walking in;
--   - long lines: three lines show, the rest scrolls up at reading pace (the bubble stays until the end);
--   - a speaker off screen: their bubble docks on the screen edge on their side, with their name;
--   - two bubbles that would overlap: the higher one is moved above the other;
--   - Yell bigger, Whisper smaller and paler, ALL CAPS shaking; live words while someone talks (Koetama), "♪" while
--     their voice is heard; a translation under the line, in pink.
-- Everything it shows comes from proxcomms/client.lua (CL.bubbles, CL.live) and proxcomms/koetama.lua (K.talking).
local Widget = require "widgets/widget"
local Text = require "widgets/text"
local NineSlice = require "widgets/nineslice"
local Image = require "widgets/image"
local T = require "proxcomms/text"
local Settings = require "proxcomms/settings"

local LINES = 3
local WRAP = 560          -- the text's width, before the HUD's scale
local HOLD, PER_LINE = 1.5, 1.8
local SIZE = 28           -- (FollowText draws chat at 35: a fifth smaller - the user, 2026-10-13: "the fonts are a bit big")
local MARGIN = 24
local TR_COLOUR = {1, 0.6, 0.78, 1}
local TR_ORIGINAL = 0.6   -- a translated line's original, against its translation
-- the box (images/pc_bubble.xml, tools/make_bubble.py): white, tinted to BOX_RGB at Settings.bubbleOpacity
local ATLAS = "images/pc_bubble.xml"
local BOX_RGB = {0.04, 0.04, 0.06}
local CORNER = 12         -- a corner piece's size (NineSlice's corners and edges stick out this far beyond its centre)
local PAD_X, PAD_Y = 12, 6
local TAIL = 12           -- how far a tail sticks out of the box (its textures: 24 x 12 and 12 x 24)
-- a tail on each side of the box, the one facing the speaker shown: {texture, its centre's direction from the box}
local SIDES = {
    bottom = {"tail_down.tex", 0, -1}, top = {"tail_up.tex", 0, 1},
    left = {"tail_left.tex", -1, 0}, right = {"tail_right.tex", 1, 0},
}
-- the styles (Settings.bubbleStyle): the font, its size against TALKINGFONT's, and the box. "pc_pangolin": the Teardown
-- mod's Pangolin (fonts/pc_pangolin.zip, loaded by modmain; Chinese and the like from the game's fallback fonts)
local STYLES = {
    clear = {font = "pc_pangolin", scale = 1, box = true},
    game = {font = TALKINGFONT, scale = 1, box = false},
}

local function style()
    return STYLES[Settings.bubbleStyle] or STYLES.clear
end

-- which side of a box (w x h, centred on 0, 0) faces a point, and where along that side its tail goes
local function tailSide(w, h, lx, ly)
    local reachX, reachY = math.max(0, w * 0.5 - CORNER - 6), math.max(0, h * 0.5 - CORNER)
    -- (the side the point is farthest beyond: a speaker off the right of the screen, a little lower than his docked
    --  bubble, gets a tail on the right)
    local outX, outY = math.abs(lx) - w * 0.5, math.abs(ly) - h * 0.5
    local side
    if outY >= outX then side = ly < 0 and "bottom" or "top"
    else side = lx > 0 and "right" or "left" end
    if side == "bottom" or side == "top" then return side, math.max(-reachX, math.min(reachX, lx)) end
    return side, math.max(-reachY, math.min(reachY, ly))
end

local Bubble = Class(Widget, function(self)
    Widget._ctor(self, "pc_bubble")
    self:SetScaleMode(SCALEMODE_PROPORTIONAL)
    self:SetMaxPropUpscale(MAX_HUD_SCALE)
    self:SetClickable(false)
    self.root = self:AddChild(Widget("root"))
    self.box = self.root:AddChild(NineSlice(ATLAS))
    self.box:Hide()
    self.tails = {}
    for side, s in pairs(SIDES) do
        self.tails[side] = self.root:AddChild(Image(ATLAS, s[1]))
        self.tails[side]:Hide()
    end
    self.name = self.root:AddChild(Text(TALKINGFONT, SIZE * 0.6))
    self.text = self.root:AddChild(Text(TALKINGFONT, SIZE))
    self.tr = self.root:AddChild(Text(TALKINGFONT, SIZE * 0.75))
    self.name:Hide()
    self.tr:Hide()
end)

local PCBubbles = Class(Widget, function(self, owner, CL, K)
    Widget._ctor(self, "pc_bubbles")
    self.owner, self.CL, self.K = owner, CL, K
    self.pool = {}            -- key -> Bubble
    self.measure = self:AddChild(Text(TALKINGFONT, SIZE))
    self.measure:Hide()
    self:StartUpdating()
end)

-- the size of a string (lines joined by "\n") in a font at a size (the hidden measuring Text)
function PCBubbles:Size(s, size, font)
    if font and self.measureFont ~= font then
        self.measure:SetFont(font)
        self.measureFont = font
    end
    self.measure:SetSize(size)
    self.measure:SetString(s)
    local w, h = self.measure:GetRegionSize()
    return w or 0, h or 0
end

function PCBubbles:Width(s, size, font)
    return (self:Size(s, size, font))
end

-- the lines a text wraps into in a font at a size (cached per bubble)
function PCBubbles:Wrap(text, size, font, maxw)
    return T.wrap(text, maxw or WRAP, function(s) return self:Width(s, size, font) end)
end

-- where above an entity's head a bubble sits (DST's talker offset), in screen pixels
local function headPos(ent)
    if ent and ent.AnimState and ent:IsValid() then
        local off = ent.components and ent.components.talker and ent.components.talker.offset
        local ox, oy, oz = 0, -400, 0
        if off then ox, oy, oz = off.x, off.y, off.z end
        return TheSim:GetScreenPos(ent.AnimState:GetSymbolPosition("", ox, oy, oz))
    end
    return nil
end

local function worldPos(x, z)
    if not (x and z) then return nil end
    return TheSim:GetScreenPos(x, 3.5, z)
end

-- the proportional scale the engine gives a SCALEMODE_PROPORTIONAL widget (DST's screens are laid out for 1280 x 720)
local function propScale()
    local w, h = TheSim:GetScreenSize()
    return math.min(MAX_HUD_SCALE or 1.25, math.min(w / RESOLUTION_X, h / RESOLUTION_Y))
end

-- everything to draw now: {key, uid, text lines, colour, size, tr lines, caps, dockable, anchor x / y, name}
function PCBubbles:Collect(now)
    local CL, K = self.CL, self.K
    local items = {}
    local me = CL.me()
    local st = style()
    local font = st.font
    local size0 = SIZE * (Settings.textSize or 1) * st.scale
    for uid, s in pairs(CL.bubbles) do
        for _, slot in ipairs({"cur", "prev"}) do
            local b = s[slot]
            if b and CL.visible(b) and not (slot == "cur" and CL.live[uid] and CL.live[uid].text ~= "" and b.t < CL.live[uid].t) then
                local trSize = size0 * (b.mode == "y" and 1.2 or (b.mode == "w" and 0.85 or 1))
                -- (translated: the translation is the line to read, at full size; the original over it, smaller -
                --  the user, 2026-10-16)
                local size = b.tr and trSize * TR_ORIGINAL or trSize
                local text = CL.bubbleText(b)
                if b.wrapFor ~= text or b.wrapSize ~= size or b.wrapFont ~= font then
                    b.wrapFor, b.wrapSize, b.wrapFont = text, size, font
                    b.lines = self:Wrap(text, size, font)
                    b.extra = #b.lines > LINES and (HOLD + (#b.lines - LINES) * PER_LINE) or 0
                end
                local trLines
                local trText = CL.trText(b)                  -- (garbled as the line is, CL.shareOf)
                if trText then
                    if b.trWrapFor ~= trText or b.trWrapFont ~= font or b.trWrapSize ~= trSize then
                        b.trWrapFor, b.trWrapFont, b.trWrapSize, b.trLines = trText, font, trSize, self:Wrap(trText, trSize, font)
                    end
                    trLines = b.trLines
                end
                local first = 1
                if #b.lines > LINES then
                    local age = now - b.t - HOLD
                    first = math.max(1, math.min(#b.lines - LINES + 1, 1 + math.floor(math.max(0, age) / PER_LINE)))
                end
                local shown = {}
                for i = first, math.min(#b.lines, first + LINES - 1) do shown[#shown + 1] = b.lines[i] end
                local col = CL.modeColour(b.mode, b.level == "mumble")
                items[#items + 1] = {key = uid .. ":" .. slot, uid = uid, lines = shown, colour = {col[1], col[2], col[3], 1},
                    nameColour = b.colour, font = font,
                    size = size, trSize = trSize, tr = trLines, caps = b.caps, dock = not (b.native and b.mode == "g"), x = b.x, z = b.z,
                    name = b.name, prev = slot == "prev", scrolled = #b.lines > LINES}
            end
        end
    end
    -- live words (and "♪" while a voice is heard)
    for uid, l in pairs(CL.live) do
        local text = CL.liveText(l, uid)
        if text and Settings.bubbles then
            local size = size0 * (l.mode == "y" and 1.2 or (l.mode == "w" and 0.85 or 1))
            if l.wrapFor ~= text or l.wrapSize ~= size or l.wrapFont ~= font then
                l.wrapFor, l.wrapSize, l.wrapFont, l.lines = text, size, font, self:Wrap(text, size, font)
            end
            local lines = l.lines
            local shown = {}
            for i = math.max(1, #lines - LINES + 1), #lines do shown[#shown + 1] = lines[i] end
            local c = CL.modeColour(l.mode)
            items[#items + 1] = {key = uid .. ":live", uid = uid, lines = shown, colour = {c[1], c[2], c[3], 0.9}, size = size,
                nameColour = CL.colourOf(uid), font = font,
                dock = true, x = l.x, z = l.z, name = l.name or CL.nameOf(uid)}
        end
    end
    for id, on in pairs(K and K.talking or {}) do
        if on and id ~= me and not CL.live[id] and not (CL.bubbles[id] and CL.bubbles[id].cur) and Settings.bubbles then
            local c = CL.colourOf(id)
            items[#items + 1] = {key = id .. ":talk", uid = id, lines = {"♪"}, colour = {c[1], c[2], c[3], 0.9}, size = size0, font = font,
                dock = false}
        end
    end
    return items
end

function PCBubbles:OnUpdate(dt)
    local CL = self.CL
    local ok, err = pcall(CL.tick, dt)
    if not ok then print("[Proximity Comms] tick: " .. tostring(err)) end
    local now = GetTime()
    local items = self:Collect(now)
    local sw, sh = TheSim:GetScreenSize()
    local hud = TheFrontEnd:GetHUDScale()
    local k = propScale() * hud
    local opacity = Settings.bubbleOpacity or 0.6
    local box = style().box and opacity > 0
    local padX, padY, tailH = 0, 0, 0
    if box then padX, padY, tailH = PAD_X, PAD_Y, TAIL end
    local used = {}
    local placed = {}
    -- anchors first (on screen or docked), lower ones first so the higher one moves up
    for _, it in ipairs(items) do
        local ent = CL.entity(it.uid)
        local ax, ay = headPos(ent)
        if not ax then ax, ay = worldPos(it.x, it.z) end
        it.ax, it.ay = ax, ay
    end
    -- (ties by key: the same order every frame, no flicker between two heads at one height)
    table.sort(items, function(a, b)
        if (a.ay or 0) ~= (b.ay or 0) then return (a.ay or 0) < (b.ay or 0) end
        return a.key < b.key
    end)
    for _, it in ipairs(items) do
        if it.ax then
            -- (sizes in the bubble's own units: k of them make a screen pixel)
            local w, h = self:Size(table.concat(it.lines, "\n"), it.size, it.font)
            h = math.max(h, #it.lines * it.size * 0.9)
            local trH = 0
            if it.tr then
                local tw
                tw, trH = self:Size(table.concat(it.tr, "\n", 1, math.min(LINES, #it.tr)), it.trSize, it.font)
                w = math.max(w, tw)
            end
            local boxW, boxH = w + 2 * padX, h + trH + 2 * padY
            -- (the box, with room below it for the tail: the tail's tip is the anchor)
            local pw, ph = boxW * k, (boxH + tailH) * k
            local x, y = it.ax, it.ay + ph * 0.5
            local off = x < 0 or x > sw or it.ay < 0 or it.ay > sh
            if off and not it.dock then
                it.skip = true
            else
                local docked = false
                local minx, maxx = MARGIN + pw * 0.5, sw - MARGIN - pw * 0.5
                local miny, maxy = MARGIN + ph * 0.5, sh - MARGIN - ph * 0.5
                if x < minx or x > maxx or y < miny or y > maxy then docked = off end
                x = math.max(minx, math.min(maxx, x))
                y = math.max(miny, math.min(maxy, y))
                if it.prev then y = y + ph * 0.25 end
                -- (above any bubble it would overlap)
                for _, p in ipairs(placed) do
                    if math.abs(p.x - x) < (p.w + pw) * 0.5 and math.abs(p.y - y) < (p.h + ph) * 0.5 then
                        y = p.y + (p.h + ph) * 0.5 + 4
                    end
                end
                -- the tail: on the side of the box facing the speaker's head (off screen too), along it toward them -
                -- worked out every frame, so it follows them (and the camera)
                if box then
                    local cyPx = y + tailH * 0.5 * k     -- (the box's centre on screen: above the tail's room)
                    it.tailSide, it.tailAt = tailSide(boxW, boxH, (it.ax - x) / k, (it.ay - cyPx) / k)
                end
                if it.caps then x, y = x + math.random(-2, 2), y + math.random(-2, 2) end
                placed[#placed + 1] = {x = x, y = y, w = pw, h = ph}
                it.px, it.py, it.docked, it.h, it.trH, it.boxW, it.boxH = x, y, docked, h, trH, boxW, boxH
            end
        else
            it.skip = true
        end
    end
    for _, it in ipairs(items) do
        if not it.skip then
            local w = self.pool[it.key]
            if not w then
                w = self:AddChild(Bubble())
                self.pool[it.key] = w
            end
            used[it.key] = true
            if w.font ~= it.font then
                w.font = it.font
                w.text:SetFont(it.font)
                w.tr:SetFont(it.font)
                w.name:SetFont(it.font)
            end
            w.root:SetScale(hud)
            -- (the box's centre: above the tail's room)
            local cy = tailH * 0.5
            if box then
                if w.opacity ~= opacity then
                    w.opacity = opacity
                    w.box:SetTint(BOX_RGB[1], BOX_RGB[2], BOX_RGB[3], opacity)
                    for _, t in pairs(w.tails) do t:SetTint(BOX_RGB[1], BOX_RGB[2], BOX_RGB[3], opacity) end
                end
                w.box:Show()
                w.box:SetSize(math.max(1, it.boxW - 2 * CORNER), math.max(1, it.boxH - 2 * CORNER))
                w.box:SetPosition(0, cy, 0)
                -- (the tail just outside the box's edge on its side, at its place along it)
                for side, t in pairs(w.tails) do
                    if side == it.tailSide then
                        local s = SIDES[side]
                        if s[3] ~= 0 then
                            t:SetPosition(it.tailAt, cy + s[3] * (it.boxH + TAIL) * 0.5, 0)
                        else
                            t:SetPosition(s[2] * (it.boxW + TAIL) * 0.5, cy + it.tailAt, 0)
                        end
                        t:Show()
                    else
                        t:Hide()
                    end
                end
            else
                w.box:Hide()
                for _, t in pairs(w.tails) do t:Hide() end
            end
            w.text:SetSize(it.size)
            w.text:SetColour(unpack(it.colour))
            w.text:SetString(table.concat(it.lines, "\n"))
            w.text:SetPosition(0, cy + it.trH * 0.5, 0)
            if it.tr then
                local n = math.min(LINES, #it.tr)
                local trLines = {}
                for i = 1, n do trLines[i] = it.tr[i] end
                w.tr:Show()
                w.tr:SetSize(it.trSize)
                w.tr:SetColour(unpack(TR_COLOUR))
                w.tr:SetString(table.concat(trLines, "\n"))
                w.tr:SetPosition(0, cy - it.h * 0.5, 0)
            else
                w.tr:Hide()
            end
            if it.docked and it.name then
                w.name:Show()
                w.name:SetColour(unpack(it.nameColour or it.colour))
                w.name:SetString(it.name .. ":")
                -- (above the box; below it when the tail is on top, pointing at a speaker above the screen)
                local dir = (box and it.tailSide == "top") and -1 or 1
                w.name:SetPosition(0, cy + dir * (it.boxH * 0.5 + it.size * 0.4), 0)
            else
                w.name:Hide()
            end
            w:SetPosition(it.px, it.py, 0)
            w:Show()
        end
    end
    for key, w in pairs(self.pool) do
        if not used[key] then
            w:Kill()
            self.pool[key] = nil
        end
    end
end

return PCBubbles
