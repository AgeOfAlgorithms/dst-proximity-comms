-- The server half (each shard's server: the surface, the caves). It sends a Speak or Yell line only to the players in
-- reach of it (and a margin to walk in while it is up), live words of a spoken line the same way, keeps the session's
-- ONE voice room for the whole world (the master shard picks it, every shard hands it to its players), the list of
-- players in Global (their voice heard by no one: Global is text only, koetama.lua), and the ranges (the host's mod settings, changed
-- by admins with /pc range). Whisper and Global lines are DST's own chat (TheNet:Say): not here.
--
-- Every handler takes the sender as DST gives it (the player entity: a client cannot pose as someone else) and checks
-- every argument; each kind of call has a token bucket per player.
local T = require "proxcomms/text"
local C = require "proxcomms/config"

local S = {
    whisper = C.WHISPER_TILES, speak = C.SPEAK_TILES, yell = C.YELL_TILES,
    saved = nil,              -- {speak, yell} an admin set (kept in the world's save)
    voice = true,             -- the host's setting: voice rooms on
    region = "",              -- the host's setting: the voice server's region ("" auto)
    room = nil, key = nil,    -- the session's voice room (the master's choice, copied to the other shards)
    vmodes = {},              -- (master) userid -> voice mode
    global = {},              -- userid -> true: their voice is in Global now (every shard keeps a copy)
    buckets = {},             -- userid -> kind -> {n, t}
    lineId = 0,
}
S.ranges = C.ranges(S.speak, S.yell, S.whisper)

local function clientRPC(name) return GetClientModRPC(C.NAMESPACE, name) end
local function shardRPC(name) return GetShardModRPC(C.NAMESPACE, name) end

local function toShards(name, shard, ...)
    -- (a world without caves has no other shard: nothing to send, and nothing must break)
    pcall(SendModRPCToShard, shardRPC(name), shard, ...)
end

function S.isMaster()
    return TheWorld == nil or TheWorld.ismastershard ~= false
end

-- (modmain, on the server) the host's mod settings
function S.configure(speakTiles, yellTiles, voiceOn, region, whisperTiles)
    S.speak, S.yell = tonumber(speakTiles) or C.SPEAK_TILES, tonumber(yellTiles) or C.YELL_TILES
    S.whisper = tonumber(whisperTiles) or C.WHISPER_TILES
    if S.saved then S.speak, S.yell, S.whisper = S.saved.speak, S.saved.yell, S.saved.whisper or S.whisper end
    S.ranges = C.ranges(S.speak, S.yell, S.whisper)
    S.speak, S.yell, S.whisper = S.ranges.speakTiles, S.ranges.yellTiles, S.ranges.whisperTiles
    S.voice = voiceOn ~= false
    S.region = type(region) == "string" and region or ""
end

-- a token bucket: at most burst at once, then rate a second
function S.allow(uid, kind, rate, burst)
    local now = GetTime()
    local per = S.buckets[uid]
    if not per then per = {} S.buckets[uid] = per end
    local b = per[kind]
    if not b then b = {n = burst, t = now} per[kind] = b end
    b.n = math.min(burst, b.n + (now - b.t) * rate)
    b.t = now
    if b.n < 1 then return false end
    b.n = b.n - 1
    return true
end

-- the sender, if it is a real player here
function S.who(player)
    if type(player) ~= "table" or type(player.userid) ~= "string" or player.userid == "" then return nil end
    if player.IsValid and not player:IsValid() then return nil end
    if not player.Transform then return nil end
    return player.userid
end

function S.pos(player)
    local x, _, z = player.Transform:GetWorldPosition()
    return x, z
end

-- the userids of the players on this shard within reach of (x, z)
function S.near(x, z, reach)
    local out, r2 = {}, reach * reach
    for _, p in ipairs(AllPlayers) do
        if p.userid and p.userid ~= "" and p.Transform then
            local px, _, pz = p.Transform:GetWorldPosition()
            local dx, dz = px - x, pz - z
            if dx * dx + dz * dz <= r2 then out[#out + 1] = p.userid end
        end
    end
    return out
end

function S.nameOf(player)
    local n = T.clean(type(player.name) == "string" and player.name or "", C.NAME_LEN)
    return n ~= "" and n or "?"
end

-- how far a mode's line is sent: its outer range and the margin
function S.reach(mode)
    return (S.ranges[mode] or S.ranges.s)[2] * (1 + C.SLACK)
end

-- ---- RPC handlers (MOD_RPC, client -> server)

-- a client starts (or asks again until it has heard back): everything it needs now
function S.onHello(player)
    local uid = S.who(player)
    if not uid or not S.allow(uid, "hello", 1, 3) then return end
    SendModRPCToClient(clientRPC("state"), uid, S.speak, S.yell, (S.voice and S.room) or "", (S.voice and S.key) or "",
        S.region, S.globalList(), S.voice, S.whisper)
end

-- a Speak or Yell line. Spoken ones (Koetama) carry utt (the line's number), times (each unit's start in 1/100 s,
-- 4 hex digits each) and age (s since the line began, when its words were sent)
function S.onSay(player, text, mode, utt, times, age)
    local uid = S.who(player)
    if not uid or type(text) ~= "string" or (mode ~= "s" and mode ~= "y") then return end
    if #text > C.MAX_LEN * 12 + 16 then return end
    if not S.allow(uid, "say", 1, 6) then return end
    text = T.clean(text, C.MAX_LEN)
    if text == "" then return end
    local voice = type(utt) == "number" and utt == utt
    if voice then
        local ts = T.timesOf(times)
        if not ts or #ts ~= #T.units(text) then times = "" end
        age = math.max(0, math.min(120, tonumber(age) or 0))
    else
        utt, times, age = 0, "", 0
    end
    S.lineId = S.lineId + 1
    local x, z = S.pos(player)
    local to = S.near(x, z, S.reach(mode))
    SendModRPCToClient(clientRPC("line"), to, uid, S.nameOf(player), text, mode, S.lineId, x, z, voice, utt, times, age)
    if not voice then
        player:PushEvent("ontalk", {})         -- (the character's own talk sound and mouth, from the server's stategraph)
    end
    if TheWorld then
        TheWorld:PushEvent("proxcomms_said", {player = player, userid = uid, mode = mode, text = text, voice = voice,
            x = x, z = z, range = S.ranges[mode][1], reach = S.ranges[mode][2]})
    end
    if S.A then S.A.hear(uid, S.nameOf(player), text, mode, x, z) end   -- (the agents that hear it)
end

-- the words so far of a line being spoken ("" = they just started talking), to the players in reach of its mode
function S.onLive(player, utt, text, mode)
    local uid = S.who(player)
    if not uid or type(text) ~= "string" or type(utt) ~= "number" or not (mode == "w" or mode == "s" or mode == "y") then return end
    if #text > 4000 or not S.allow(uid, "live", 8, 16) then return end
    text = T.clean(T.tail(text, 200), 200)
    local x, z = S.pos(player)
    SendModRPCToClient(clientRPC("live"), S.near(x, z, S.reach(mode)), uid, S.nameOf(player), utt, text, mode, x, z)
end

-- this player's voice mode (where their voice goes: Global = everyone, any shard)
function S.onVmode(player, mode)
    local uid = S.who(player)
    if not uid or not C.validMode(mode) or not S.allow(uid, "vmode", 4, 8) then return end
    if S.isMaster() then S.setVmode(uid, mode) else toShards("vmode", SHARDID.MASTER, uid, mode) end
end

-- a voice room Koetama offered this player (32 and 64 lower-case hex digits)
function S.onRoom(player, room, key)
    local uid = S.who(player)
    if not uid or not S.validRoom(room, key) or not S.allow(uid, "room", 1, 3) then return end
    if S.isMaster() then S.offerRoom(room, key) else toShards("room_offer", SHARDID.MASTER, room, key) end
end

-- an admin changes the ranges (tiles)
function S.onRanges(player, speak, yell, whisper)
    local uid = S.who(player)
    if not uid or type(speak) ~= "number" or type(yell) ~= "number" or not S.allow(uid, "ranges", 1, 3) then return end
    local c = TheNet:GetClientTableForUser(uid)
    if not (c and c.admin) then return end
    S.setRanges(speak, yell, type(whisper) == "number" and whisper or S.whisper, true)
    toShards("ranges", nil, S.speak, S.yell, S.whisper)
end

-- ---- the voice room
function S.validRoom(room, key)
    return type(room) == "string" and type(key) == "string" and #room == 32 and #key == 64
        and not room:find("[^0-9a-f]") and not key:find("[^0-9a-f]")
end

-- (master) the first room offered is the session's; every offer (also from a shard that started late) re-sends it
function S.offerRoom(room, key)
    if not S.voice then return end
    if not S.room then S.room, S.key = room, key end
    S.publishRoom()
end

function S.publishRoom()
    if not (S.voice and S.room) then return end
    SendModRPCToClient(clientRPC("room"), nil, S.room, S.key, S.region)
    if S.isMaster() then toShards("room_set", nil, S.room, S.key) end
end

-- (another shard) the master's room
function S.onShardRoomSet(shard, room, key)
    if S.isMaster() or not S.validRoom(room, key) then return end
    S.room, S.key = room, key
    S.publishRoom()
end

function S.onShardRoomOffer(shard, room, key)
    if S.isMaster() and S.validRoom(room, key) then S.offerRoom(room, key) end
end

-- ---- Global voices
function S.globalList()
    local ids = {}
    for uid in pairs(S.global) do ids[#ids + 1] = uid end
    table.sort(ids)
    return table.concat(ids, ",")
end

function S.setVmode(uid, mode)
    S.vmodes[uid] = mode
    local was = S.global[uid] == true
    local now = mode == "g"
    if was == now then return end
    S.global[uid] = now or nil
    local list = S.globalList()
    SendModRPCToClient(clientRPC("global"), nil, list)
    toShards("global", nil, list)
end

function S.onShardVmode(shard, uid, mode)
    if S.isMaster() and type(uid) == "string" and C.validMode(mode) then S.setVmode(uid, mode) end
end

function S.onShardGlobal(shard, list)
    if S.isMaster() or type(list) ~= "string" or #list > 64 * 40 then return end
    S.global = {}
    for uid in list:gmatch("[^,]+") do S.global[uid] = true end
    SendModRPCToClient(clientRPC("global"), nil, list)
end

-- ---- ranges
function S.setRanges(speak, yell, whisper, save)
    S.ranges = C.ranges(speak, yell, whisper)
    S.speak, S.yell, S.whisper = S.ranges.speakTiles, S.ranges.yellTiles, S.ranges.whisperTiles
    if save then S.saved = {speak = S.speak, yell = S.yell, whisper = S.whisper} end
    SendModRPCToClient(clientRPC("ranges"), nil, S.speak, S.yell, S.whisper)
end

function S.onShardRanges(shard, speak, yell, whisper)
    if type(speak) == "number" and type(yell) == "number" then
        S.setRanges(speak, yell, type(whisper) == "number" and whisper or S.whisper, true)
    end
end

-- (the world component) what an admin set, kept with the world (a world saved before Whisper had a range: the host's)
function S.save()
    return S.saved and {speak = S.saved.speak, yell = S.saved.yell, whisper = S.saved.whisper} or nil
end
function S.load(data)
    if type(data) == "table" and type(data.speak) == "number" and type(data.yell) == "number" then
        local whisper = type(data.whisper) == "number" and data.whisper or S.whisper
        S.saved = {speak = data.speak, yell = data.yell, whisper = whisper}
        S.setRanges(data.speak, data.yell, whisper, true)
    end
end

return S
