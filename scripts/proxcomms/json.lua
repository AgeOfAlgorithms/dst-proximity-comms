-- JSON for the Koetama link (pure Lua 5.1; ported from Proximity Comms for Teardown, voice.lua). DST's own json.lua
-- cannot tell an empty list from an empty object and writes whole numbers as "3.0" (Koetama wants 3 for ids), so:
--   J.encode(v): strings (invalid UTF-8 bytes become U+FFFD), finite numbers (whole ones without ".0"), booleans,
--     J.NULL / nil -> null, tables: an ARRAY when marked with J.array(t) or t[1] ~= nil, else an object (string keys,
--     sorted, "type" first).
--   J.decode(s): the value, or nil for anything malformed (never raises). Arrays come back marked, null as J.NULL.
local J = {}

J.NULL = setmetatable({}, {__tostring = function() return "null" end})
local ARRAY = {__jsonArray = true}
function J.array(t) return setmetatable(t or {}, ARRAY) end
function J.isArray(t) return type(t) == "table" and getmetatable(t) == ARRAY end

local ESC = {['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t"}
for b = 0, 31 do
    local ch = string.char(b)
    if not ESC[ch] then ESC[ch] = string.format("\\u%04x", b) end
end
local BAD = "\239\191\189"
local function seq(m)
    local c, n = m:byte(1), #m
    local len = (c >= 0xC2 and c <= 0xDF and 2) or (c >= 0xE0 and c <= 0xEF and 3) or (c >= 0xF0 and c <= 0xF4 and 4) or 0
    if len == 0 then return string.rep(BAD, n) end
    if n > len then return seq(m:sub(1, len)) .. string.rep(BAD, n - len) end
    if n < len then return string.rep(BAD, n) end
    local b2 = m:byte(2)
    if (c == 0xE0 and b2 < 0xA0) or (c == 0xED and b2 > 0x9F) or (c == 0xF0 and b2 < 0x90) or (c == 0xF4 and b2 > 0x8F) then
        return string.rep(BAD, n)
    end
    return m
end
local function str(s)
    local e = s
    if e:find("[\128-\255]") then e = e:gsub("[\128-\255][\128-\191]*", seq) end
    return '"' .. e:gsub('[%z\1-\31"\\]', ESC) .. '"'
end
local function num(n)
    if n ~= n or n == math.huge or n == -math.huge then return "null" end
    if n == math.floor(n) and math.abs(n) < 1e15 then return string.format("%.0f", n) end
    return string.format("%.14g", n)
end
local function keyOrder(a, b)
    if a == "type" then return b ~= "type" end
    if b == "type" then return false end
    return a < b
end
local function enc(v, out, depth)
    local t = type(v)
    if t == "string" then out[#out + 1] = str(v)
    elseif t == "number" then out[#out + 1] = num(v)
    elseif t == "boolean" then out[#out + 1] = v and "true" or "false"
    elseif t ~= "table" or v == J.NULL or depth > 32 then out[#out + 1] = "null"
    elseif getmetatable(v) == ARRAY or v[1] ~= nil then
        out[#out + 1] = "["
        for i = 1, #v do
            if i > 1 then out[#out + 1] = "," end
            enc(v[i], out, depth + 1)
        end
        out[#out + 1] = "]"
    else
        local keys = {}
        for k in pairs(v) do if type(k) == "string" then keys[#keys + 1] = k end end
        table.sort(keys, keyOrder)
        out[#out + 1] = "{"
        for i, k in ipairs(keys) do
            if i > 1 then out[#out + 1] = "," end
            out[#out + 1] = str(k)
            out[#out + 1] = ":"
            enc(v[k], out, depth + 1)
        end
        out[#out + 1] = "}"
    end
end
function J.encode(v)
    local out = {}
    enc(v, out, 0)
    return table.concat(out)
end

local function u8(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64) end
    if cp < 0x10000 then return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64) end
    return string.char(0xF0 + math.floor(cp / 262144), 0x80 + math.floor(cp / 4096) % 64, 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end
local UNESC = {['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t"}
local function skip(s, i) return s:find("[^ \t\r\n]", i) or #s + 1 end
local function decStr(s, i)
    local out = {}
    i = i + 1
    while true do
        local j = s:find('[%z\1-\31"\\]', i)
        if not j then return nil end
        out[#out + 1] = s:sub(i, j - 1)
        local ch = s:sub(j, j)
        if ch == '"' then return table.concat(out), j + 1 end
        if ch ~= "\\" then return nil end
        local e = s:sub(j + 1, j + 1)
        if e == "u" then
            local h = s:match("^%x%x%x%x", j + 2)
            if not h then return nil end
            local cp = tonumber(h, 16)
            i = j + 6
            if cp >= 0xD800 and cp <= 0xDBFF then
                local h2 = s:match("^\\u(%x%x%x%x)", i)
                local lo = h2 and tonumber(h2, 16)
                if lo and lo >= 0xDC00 and lo <= 0xDFFF then
                    cp, i = 0x10000 + (cp - 0xD800) * 1024 + (lo - 0xDC00), i + 6
                else
                    cp = 0xFFFD
                end
            elseif cp >= 0xDC00 and cp <= 0xDFFF then
                cp = 0xFFFD
            end
            out[#out + 1] = u8(cp)
        elseif UNESC[e] then
            out[#out + 1] = UNESC[e]
            i = j + 2
        else
            return nil
        end
    end
end
local function decNum(s, i)
    local _, e = s:find("^-?%d+", i)
    if not e then return nil end
    local _, f = s:find("^%.%d+", e + 1)
    if f then e = f end
    local _, x = s:find("^[eE][-+]?%d+", e + 1)
    if x then e = x end
    local n = tonumber(s:sub(i, e))
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    return n, e + 1
end
local dec
dec = function(s, i, depth)
    if depth > 64 then return nil end
    i = skip(s, i)
    local c = s:sub(i, i)
    if c == '"' then return decStr(s, i) end
    if c == "{" then
        local obj = {}
        i = skip(s, i + 1)
        if s:sub(i, i) == "}" then return obj, i + 1 end
        while true do
            if s:sub(i, i) ~= '"' then return nil end
            local k, v
            k, i = decStr(s, i)
            if not k then return nil end
            i = skip(s, i)
            if s:sub(i, i) ~= ":" then return nil end
            v, i = dec(s, i + 1, depth + 1)
            if v == nil then return nil end
            obj[k] = v
            i = skip(s, i)
            c = s:sub(i, i)
            if c == "}" then return obj, i + 1 end
            if c ~= "," then return nil end
            i = skip(s, i + 1)
        end
    end
    if c == "[" then
        local arr, n = J.array({}), 0
        i = skip(s, i + 1)
        if s:sub(i, i) == "]" then return arr, i + 1 end
        while true do
            local v
            v, i = dec(s, i, depth + 1)
            if v == nil then return nil end
            n = n + 1
            arr[n] = v
            i = skip(s, i)
            c = s:sub(i, i)
            if c == "]" then return arr, i + 1 end
            if c ~= "," then return nil end
            i = i + 1
        end
    end
    if s:sub(i, i + 3) == "true" then return true, i + 4 end
    if s:sub(i, i + 4) == "false" then return false, i + 5 end
    if s:sub(i, i + 3) == "null" then return J.NULL, i + 4 end
    return decNum(s, i)
end
function J.decode(s)
    if type(s) ~= "string" then return nil end
    local ok, v, i = pcall(dec, s, 1, 0)
    if not ok or v == nil or skip(s, i) <= #s then return nil end
    return v
end

return J
