-- Each player's own settings, kept on their PC (TheSim's persistent string "proxcomms_settings", JSON).
local J = require "proxcomms/json"
local C = require "proxcomms/config"

local FILE = "proxcomms_settings"

local Settings = {
    mode = "s",              -- the chat mode (and the voice's): w / s / y / g
    bubbles = true,          -- speech bubbles over heads
    bubbleStyle = "clear",   -- clear (a see-through box, Pangolin) / game (DST's hand-drawn letters, no box)
    bubbleOpacity = 0.6,     -- 0..1: the Clear style's box (0: none)
    enterChat = true,        -- Enter opens the chat line, and DST's Y / U don't (false: DST's keys, Y and U)
    textSize = 1,            -- 0.7 .. 1.6
    mic = "auto",            -- auto (controller: always, else push to talk) / ptt / always / off
    talkKey = "V",           -- push to talk: a key's name (DST's KEY_<name>), bound on the Voice page
    voiceVolume = 1,         -- 0..1: other players' voices
    live = true,             -- live words while talking
    lang = "",               -- the language I speak ("": the game's language)
    vol = {},                -- userid -> 0..2 (only for me)
    muted = {},              -- userid -> name (only for me)
    names = {},              -- userid -> the name last seen (for the lists)
    pointed = 0,             -- sessions the quiet pointer to Koetama was shown in (at most 3)
    loaded = false,
}

local FIELDS = {"mode", "bubbles", "bubbleStyle", "bubbleOpacity", "enterChat", "textSize", "mic", "talkKey", "voiceVolume", "live", "lang", "vol", "muted", "names", "pointed"}

function Settings.apply(t)
    if type(t) ~= "table" then return end
    if C.validMode(t.mode) then Settings.mode = t.mode end
    if type(t.bubbles) == "boolean" then Settings.bubbles = t.bubbles end
    if t.bubbleStyle == "clear" or t.bubbleStyle == "game" then Settings.bubbleStyle = t.bubbleStyle end
    if type(t.bubbleOpacity) == "number" then Settings.bubbleOpacity = math.max(0, math.min(1, t.bubbleOpacity)) end
    if type(t.enterChat) == "boolean" then Settings.enterChat = t.enterChat end
    if type(t.textSize) == "number" then Settings.textSize = math.max(0.7, math.min(1.6, t.textSize)) end
    if t.mic == "auto" or t.mic == "ptt" or t.mic == "always" or t.mic == "off" then Settings.mic = t.mic end
    if type(t.talkKey) == "string" and #t.talkKey <= 16 and t.talkKey:match("^[%w_]+$") then Settings.talkKey = t.talkKey end
    if type(t.voiceVolume) == "number" then Settings.voiceVolume = math.max(0, math.min(1, t.voiceVolume)) end
    if type(t.live) == "boolean" then Settings.live = t.live end
    if type(t.lang) == "string" and #t.lang <= 8 then Settings.lang = t.lang end
    if type(t.pointed) == "number" then Settings.pointed = t.pointed end
    for _, k in ipairs({"vol", "muted", "names"}) do
        if type(t[k]) == "table" then
            local out = {}
            for uid, v in pairs(t[k]) do
                if type(uid) == "string" and #uid <= 64 then
                    if k == "vol" and type(v) == "number" then out[uid] = math.max(0, math.min(Settings.VOL_MAX or 1.5, v))
                    elseif k ~= "vol" and type(v) == "string" then out[uid] = v:sub(1, 128) end
                end
            end
            Settings[k] = out
        end
    end
end

function Settings.load(done)
    if not (TheSim and TheSim.GetPersistentString) then Settings.loaded = true if done then done() end return end
    TheSim:GetPersistentString(FILE, function(ok, data)
        if ok and type(data) == "string" and data ~= "" then Settings.apply(J.decode(data)) end
        Settings.loaded = true
        if done then done() end
    end)
end

function Settings.save()
    if not (TheSim and TheSim.SetPersistentString) then return end
    local t = {}
    for _, k in ipairs(FIELDS) do t[k] = Settings[k] end
    TheSim:SetPersistentString(FILE, J.encode(t), false)
end

-- one other player's volume, only for me (0..VOL_MAX: 150 %, as the Teardown mod's)
Settings.VOL_MAX = 1.5

function Settings.volumeOf(uid)
    return Settings.vol[uid] or 1
end

function Settings.setVolume(uid, v)
    v = math.max(0, math.min(Settings.VOL_MAX, math.floor(v * 20 + 0.5) / 20))
    Settings.vol[uid] = v ~= 1 and v or nil
    Settings.save()
end

return Settings
