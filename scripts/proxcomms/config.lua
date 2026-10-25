-- The numbers the chat runs on (pure Lua). Distances are in world units: one turf tile is 4 units (TILE_SCALE).
local C = {}

C.NAMESPACE = "proxcomms"
C.VERSION = "0.2.0"
C.KOETAMA_URL = "https://github.com/AgeOfAlgorithms/koetama"
C.KOETAMA_PORT = 47170            -- the profile's (koetama/dont-starve-together-proximity-comms.json)
C.KOETAMA_MIN = "0.5.5"           -- older: feeds over 1 KB wait 1 s in DST's HTTP client (no "100 Continue")

C.TILE = 4
-- defaults (the user, 2026-10-16: "whisper should be much smaller than speak" - 8, 18 and 32 tiles); the host's mod
-- settings and admins (/pc range) change them. Whisper is DST's own (TheNet:Say, whispered): DST shows it within 40
-- units (chathistory.lua, PLAYER_CAMERA_SEE_DISTANCE), the mod within its own range instead, garbled beyond as Speak
C.WHISPER_TILES = 8
C.SPEAK_TILES = 18
C.YELL_TILES = 32
C.TILES_MIN, C.TILES_MAX = 2, 64
C.WHISPER_BUFFER = 1.4            -- the garbled zone beyond the words' range, as a share of it (Teardown's +40 %)
C.SPEAK_BUFFER = 1.4
C.YELL_BUFFER = 1.375             -- (+37.5 %)
C.SLACK = 0.5                     -- the server sends a line this share past its outer range too (walking in while it is up)
C.VOICE_NEAR = 0.5                -- a voice is at full loudness within this share of its words' range
C.MAX_LEN = 150                   -- DST's MAX_CHAT_INPUT_LENGTH
C.NAME_LEN = 32
-- a line sent from a controller starts with this (as in the Teardown mod: four dots, a pad's face buttons). U+2237: in
-- DST's full fallback fonts, so it shows over heads and in the history (U+2058, the diamond of dots, is in none)
C.PAD_MARK = "∷ "

C.MODES = {"w", "s", "y", "g"}    -- Whisper (DST's own), Speak, Yell, Global (DST's own Say)
C.MODE_KEY = {w = "WHISPER", s = "SPEAK", y = "YELL", g = "GLOBAL"}

-- the ranges for given tiles: {w = {inner, outer}, s = ..., y = ...} in units; Whisper < Speak < Yell
function C.ranges(speakTiles, yellTiles, whisperTiles)
    local sp = math.max(C.TILES_MIN, math.min(C.TILES_MAX - 1, tonumber(speakTiles) or C.SPEAK_TILES))
    local ye = math.max(sp + 1, math.min(C.TILES_MAX, tonumber(yellTiles) or C.YELL_TILES))
    local wh = math.max(1, math.min(sp - 1, tonumber(whisperTiles) or C.WHISPER_TILES))
    local wi, si, yi = wh * C.TILE, sp * C.TILE, ye * C.TILE
    return {
        whisperTiles = wh, speakTiles = sp, yellTiles = ye,
        w = {wi, wi * C.WHISPER_BUFFER},
        s = {si, si * C.SPEAK_BUFFER},
        y = {yi, yi * C.YELL_BUFFER},
    }
end

-- a mode's tiles to where it is garbled to, rounded (for the texts)
function C.outerTiles(r, mode)
    return math.floor(r[mode][2] / C.TILE + 0.5)
end

-- a voice's [near, far] in a mode (Koetama's "range")
function C.voiceRange(r, mode)
    local m = r[mode] or r.s
    return {m[1] * C.VOICE_NEAR, m[2]}
end

function C.validMode(m)
    return m == "w" or m == "s" or m == "y" or m == "g"
end

function C.prevMode(m)
    for i, x in ipairs(C.MODES) do
        if x == m then return C.MODES[(i - 2) % #C.MODES + 1] end
    end
    return "s"
end

function C.nextMode(m)
    for i, x in ipairs(C.MODES) do
        if x == m then return C.MODES[i % #C.MODES + 1] end
    end
    return "s"
end

-- "0.5.4" < "0.5.5"
function C.olderThan(v, min)
    local a, b = {}, {}
    for n in tostring(v or ""):gmatch("%d+") do a[#a + 1] = tonumber(n) end
    for n in tostring(min):gmatch("%d+") do b[#b + 1] = tonumber(n) end
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then return x < y end
    end
    return false
end

return C
