-- Text in any language (pure Lua 5.1, no game calls): UTF-8 characters, cleaning a line or a name, the garbled
-- letters of a line half heard, ALL CAPS, the units of a spoken line (Koetama's word times), word wrapping.
-- Ported from Proximity Comms for Teardown (chat_core.lua: PC.clean, PC.garble, PC.voiceUnits ...).
local T = {}

-- one character: a lead byte and at most 3 continuation bytes (a lead byte and 200 KB of them is not "one character")
T.CHAR = "[%z\1-\127\194-\244][\128-\191]?[\128-\191]?[\128-\191]?"
T.GARBLE = "\226\172\154"   -- ⬚ (U+2B1A): in DST's full fallback font, which TALKINGFONT falls back to

function T.code(ch)
    local b1 = ch:byte(1)
    if not b1 then return 0 end
    if b1 < 0x80 then return b1 end
    if b1 < 0xE0 then return (b1 - 0xC0) * 64 + ((ch:byte(2) or 0x80) - 0x80) end
    if b1 < 0xF0 then return ((b1 - 0xE0) * 64 + ((ch:byte(2) or 0x80) - 0x80)) * 64 + ((ch:byte(3) or 0x80) - 0x80) end
    return (((b1 - 0xF0) * 64 + ((ch:byte(2) or 0x80) - 0x80)) * 64 + ((ch:byte(3) or 0x80) - 0x80)) * 64 + ((ch:byte(4) or 0x80) - 0x80)
end

function T.char(c)
    if c < 0x80 then return string.char(c) end
    if c < 0x800 then return string.char(0xC0 + math.floor(c / 64), 0x80 + c % 64) end
    if c < 0x10000 then return string.char(0xE0 + math.floor(c / 4096), 0x80 + math.floor(c / 64) % 64, 0x80 + c % 64) end
    return string.char(0xF0 + math.floor(c / 262144), 0x80 + math.floor(c / 4096) % 64, 0x80 + math.floor(c / 64) % 64, 0x80 + c % 64)
end

function T.len(s)
    local k = 0
    for _ in (s or ""):gmatch(T.CHAR) do k = k + 1 end
    return k
end

-- the first n characters (never a letter cut in half)
function T.head(s, n)
    local out, k = {}, 0
    for ch in (s or ""):gmatch(T.CHAR) do
        k = k + 1
        if k > n then break end
        out[k] = ch
    end
    return table.concat(out)
end

-- the last n characters
function T.tail(s, n)
    local all = {}
    for ch in (s or ""):gmatch(T.CHAR) do all[#all + 1] = ch end
    if #all <= n then return s or "" end
    return table.concat(all, "", #all - n + 1)
end

-- at most n bytes, never cutting a character
function T.cutBytes(s, n)
    if #s <= n then return s end
    local i = n
    while i > 0 do
        local b = s:byte(i + 1)
        if not b or b < 0x80 or b >= 0xC0 then break end
        i = i - 1
    end
    return s:sub(1, i)
end

-- "cjk" (a syllable by itself: Han, kana, Hangul), "space", "pause" (punctuation that pauses), "other", "letter"
function T.kind(ch)
    local c = T.code(ch)
    if c < 0x80 then
        if ch:match("^[%w]$") then return "letter" end
        if ch == " " or ch == "\t" then return "space" end
        if ch:match("^[%.,;:!%?]$") then return "pause" end
        return "other"
    end
    if c == 0x3000 then return "space" end
    if c == 0xA1 or c == 0xBF or c == 0x60C or c == 0x61B or c == 0x61F or c == 0x964 or c == 0x965 then return "pause" end
    if (c >= 0x3001 and c <= 0x3002) or (c >= 0xFF01 and c <= 0xFF0F) or (c >= 0xFF1A and c <= 0xFF1F) then return "pause" end
    if (c >= 0x80 and c <= 0xBF) or (c >= 0x2000 and c <= 0x2BFF) or (c >= 0x3003 and c <= 0x303F) or (c >= 0xFE00 and c <= 0xFE0F) then return "other" end
    if c >= 0x300 and c <= 0x36F then return "other" end
    if (c >= 0x1100 and c <= 0x11FF) or (c >= 0x3040 and c <= 0x9FFF) or (c >= 0xAC00 and c <= 0xD7AF) or (c >= 0xF900 and c <= 0xFAFF) or c >= 0x20000 then
        return "cjk"
    end
    return "letter"
end

-- "upper" / "lower" for cased letters (Latin, Greek, Cyrillic, Armenian), "none" for uncased letters, "other"
function T.case(ch)
    local k = T.kind(ch)
    if k ~= "letter" and k ~= "cjk" then return "other" end
    local c = T.code(ch)
    if c < 0x80 then
        if c >= 65 and c <= 90 then return "upper" elseif c >= 97 and c <= 122 then return "lower" end
        return "none"
    end
    if c >= 0xC0 and c <= 0xDE and c ~= 0xD7 then return "upper" end
    if c >= 0xDF and c <= 0xFF and c ~= 0xF7 then return "lower" end
    if c >= 0x100 and c <= 0x17F then return (c % 2 == 0) and "upper" or "lower" end
    if c >= 0x386 and c <= 0x3AB then return "upper" end
    if c >= 0x3AC and c <= 0x3CE then return "lower" end
    if c >= 0x400 and c <= 0x42F then return "upper" end
    if c >= 0x430 and c <= 0x45F then return "lower" end
    if (c >= 0x460 and c <= 0x52F) or (c >= 0x1E00 and c <= 0x1EFF) then return (c % 2 == 0) and "upper" or "lower" end
    if c >= 0x531 and c <= 0x556 then return "upper" end
    if c >= 0x561 and c <= 0x587 then return "lower" end
    return "none"
end

-- a line written all in capitals (2+ cased letters, none lower case): its bubble shakes
function T.allCaps(text)
    local n = 0
    for ch in (text or ""):gmatch(T.CHAR) do
        local k = T.case(ch)
        if k == "lower" then return false end
        if k == "upper" then n = n + 1 end
    end
    return n >= 2
end

-- ---- cleaning: invisible and direction-changing characters, invalid UTF-8, accent towers, control bytes
local function stripped(c)
    return (c >= 0x200B and c <= 0x200F) or (c >= 0x2028 and c <= 0x202E) or (c >= 0x2060 and c <= 0x206F) or c == 0xFEFF
        or c == 0xAD or c == 0x34F or c == 0x61C or c == 0x115F or c == 0x1160 or c == 0x17B4 or c == 0x17B5
        or (c >= 0x180B and c <= 0x180F) or c == 0x2800 or c == 0x3164 or c == 0xFFA0 or (c >= 0xFE00 and c <= 0xFE0F)
        or (c >= 0xFFF9 and c <= 0xFFFB) or (c >= 0x1D173 and c <= 0x1D17A) or (c >= 0xE0000 and c <= 0xE0FFF)
end
local function space(c)
    return c == 0x20 or c == 0xA0 or (c >= 0x2000 and c <= 0x200A) or c == 0x202F or c == 0x205F or c == 0x3000 or c == 0x1680
end
local function mark(c)
    return (c >= 0x300 and c <= 0x36F) or (c >= 0x483 and c <= 0x489) or (c >= 0x1AB0 and c <= 0x1AFF)
        or (c >= 0x1DC0 and c <= 0x1DFF) or (c >= 0x20D0 and c <= 0x20FF) or (c >= 0xFE20 and c <= 0xFE2F)
end
function T.valid(ch)
    local n, b = #ch, ch:byte(1)
    if not b then return false end
    local want = b < 0x80 and 1 or (b < 0xE0 and 2 or (b < 0xF0 and 3 or 4))
    if n ~= want then return false end
    if n == 1 then return true end
    local c = T.code(ch)
    if (n == 2 and c < 0x80) or (n == 3 and c < 0x800) or (n == 4 and (c < 0x10000 or c > 0x10FFFF)) then return false end
    return not (c >= 0xD800 and c <= 0xDFFF)
end

-- a line as it may be shown: at most max characters (150, DST's MAX_CHAT_INPUT_LENGTH), trimmed, "" when nothing visible
function T.clean(text, max)
    if type(text) ~= "string" then return "" end
    max = max or 150
    if #text > max * 12 + 16 then text = text:sub(1, max * 12 + 16) end
    local out, run, visible = {}, 0, false
    for ch in text:gmatch(T.CHAR) do
        if T.valid(ch) then
            local c = T.code(ch)
            if stripped(c) then
            elseif mark(c) then
                run = run + 1
                if run <= 2 then out[#out + 1] = ch end
            else
                run = 0
                out[#out + 1] = ch
                if c > 31 and c ~= 127 and not space(c) then visible = true end
            end
        end
    end
    if not visible then return "" end
    text = table.concat(out):gsub("[%z\1-\31\127]", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return T.head(text, max)
end

-- ---- garbling: a line heard from beyond its words' range shows ⬚ for each letter not made out. A fixed share of the
-- letters (frac 0..1, picked per line by its seed) shows, so walking closer uncovers more of the same line; spaces
-- and punctuation stay (the sentence's shape shows). fracs: a share per letter (a spoken line: each word as clearly
-- as it was heard when said).
function T.hash01(a, b, c)
    return ((a * 73856093 + b * 19349663 + c * 83492791) % 1000003) / 1000003
end
function T.garble(text, frac, seed, fracs)
    local out, i = {}, 0
    for sp, w in (text or ""):gmatch("(%s*)(%S+)") do
        out[#out + 1] = sp
        for ch in w:gmatch(T.CHAR) do
            i = i + 1
            if (#ch == 1 and ch:find("%p")) or T.hash01(seed, i, 0) < math.max(frac, fracs and fracs[i] or 0) then
                out[#out + 1] = ch
            else
                out[#out + 1] = T.GARBLE
            end
        end
    end
    return table.concat(out)
end

-- ---- a spoken line's units (Koetama's word times): runs of letters between spaces, each CJK character on its own
-- (Koetama splits the same way: engine/asr.py units())
function T.units(text)
    local out, cur, sep = {}, nil, ""
    for ch in (text or ""):gmatch(T.CHAR) do
        if ch:find("^%s$") then
            cur, sep = nil, sep .. ch
        elseif T.kind(ch) == "cjk" then
            out[#out + 1] = {s = sep, w = ch}
            cur, sep = nil, ""
        elseif cur then
            cur.w = cur.w .. ch
        else
            cur = {s = sep, w = ch}
            out[#out + 1] = cur
            sep = ""
        end
    end
    return out
end

-- units i..j as text (the first one's space dropped)
function T.join(us, i, j)
    local out = {}
    for k = i, j do out[#out + 1] = (k > i and us[k].s or "") .. us[k].w end
    return table.concat(out)
end

-- word times travel between the games as 4 hex digits a unit in 1/100 s (an RPC string)
function T.timesHex(times)
    local out = {}
    for i, t in ipairs(times or {}) do
        out[i] = string.format("%04x", math.max(0, math.min(65535, math.floor((tonumber(t) or 0) * 100 + 0.5))))
    end
    return table.concat(out)
end
function T.timesOf(hex)
    if type(hex) ~= "string" or hex == "" or #hex % 4 ~= 0 or hex:find("[^%x]") then return nil end
    local out = {}
    for k = 1, #hex, 4 do out[#out + 1] = tonumber(hex:sub(k, k + 3), 16) / 100 end
    return out
end

-- ---- word wrapping by a width function (pixels of a string): words, and CJK characters each on their own; a word
-- wider than the line is cut between characters. -> lines
function T.wrap(text, maxw, width)
    local lines, cur = {}, ""
    local function push(s) lines[#lines + 1] = s end
    local function add(piece, sep)
        local try = cur == "" and piece or (cur .. sep .. piece)
        if width(try) <= maxw then cur = try return end
        if cur ~= "" then push(cur) cur = "" end
        if width(piece) <= maxw then cur = piece return end
        for ch in piece:gmatch(T.CHAR) do                     -- (one long word: cut it)
            if cur ~= "" and width(cur .. ch) > maxw then push(cur) cur = "" end
            cur = cur .. ch
        end
    end
    for _, u in ipairs(T.units(text)) do
        local sep = u.s ~= "" and " " or ""
        add(u.w, sep)
    end
    if cur ~= "" then push(cur) end
    return lines
end

return T
