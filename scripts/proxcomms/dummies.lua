-- Test figures (/pc dummy): a whisperer, a speaker and a yeller in front of this player, seen by this player only
-- (client-side entities, never networked). They take turns on their lines, 7 s apart, through the same paths as real
-- players' lines (so walking back and forth shows every range: the words, the garbled zone, nothing). With Koetama,
-- each also talks with a recorded test voice (the profile's test_voices 1-3), to check direction, loudness and the
-- camera maths alone.
local C = require "proxcomms/config"
local Strings = require "proxcomms/strings"
local L = Strings.L

local D = {list = {}, turn = 0, nextAt = 0, lineId = 1000000, CL = nil}

D.TURN = 7
D.TALK = 5.5                 -- s the test voice plays in a turn
D.MODES = {"w", "s", "y"}
D.TINT = {{0.8, 0.7, 1, 0.9}, {1, 1, 1, 0.9}, {1, 0.75, 0.5, 0.9}}
-- the lines the profile's test voices say (koetama/dont-starve-together-proximity-comms.json)
D.LINES = {
    "I am the whisperer. Stay close, or you will not hear me at all.",
    "I am the speaker. This is my normal voice, and it carries a fair distance.",
    "I am the yeller! You can hear me from far away!",
}

function D.uid(i) return "pcdummy" .. i end

function D.entity(uid)
    for _, d in ipairs(D.list) do
        if d.uid == uid then return d.ent end
    end
    return nil
end

function D.ids()
    local out = {}
    for _, d in ipairs(D.list) do out[#out + 1] = d.uid end
    return out
end

function D.any() return #D.list > 0 end

function D.remove(d)
    if d.ent and d.ent.IsValid and d.ent:IsValid() then d.ent:Remove() end
    for i, x in ipairs(D.list) do
        if x == d then table.remove(D.list, i) break end
    end
end

function D.clear()
    while #D.list > 0 do D.remove(D.list[1]) end
end

-- a figure: the player's own look (its build is loaded for sure), tinted by its mode
function D.make(i, x, z)
    local ent
    if CreateEntity then
        ent = CreateEntity()
        ent.entity:AddTransform()
        ent.entity:AddAnimState()
        ent:AddTag("FX")
        ent:AddTag("NOCLICK")
        ent.persists = false
        ent.AnimState:SetBank("wilson")
        local build = ThePlayer and ThePlayer.AnimState and ThePlayer.AnimState:GetBuild() or "wilson"
        ent.AnimState:SetBuild(build)
        ent.AnimState:PlayAnimation("idle_loop", true)
        ent.AnimState:SetMultColour(D.TINT[i][1], D.TINT[i][2], D.TINT[i][3], D.TINT[i][4])
        ent.Transform:SetPosition(x, 0, z)
    end
    return {i = i, uid = D.uid(i), ent = ent, x = x, z = z, mode = D.MODES[i], name = Strings.get("DUMMY_NAMES")[i],
        talkUntil = 0}
end

-- where "ahead" is: the camera's forward on the ground
function D.ahead(dist, side)
    local x, z = D.CL.myPos()
    if not x then return nil end
    local h = (TheCamera and TheCamera:GetHeading() or 0) * math.pi / 180
    local fx, fz = -math.cos(h), -math.sin(h)
    local rx, rz = math.cos(h + math.pi / 2), math.sin(h + math.pi / 2)
    return x + fx * dist + rx * side, z + fz * dist + rz * side
end

function D.command(arg)
    arg = (arg or ""):lower()
    if arg == "clear" then
        D.clear()
        D.CL.system(L("DUMMY_GONE"))
        return
    end
    local n = tonumber(arg)
    if n and n >= 1 and n <= 3 then
        for _, d in ipairs(D.list) do if d.i == n then D.remove(d) break end end
        local x, z = D.ahead(3 * C.TILE, 0)
        if x then D.list[#D.list + 1] = D.make(n, x, z) end
    else
        D.clear()
        for i = 1, 3 do
            local x, z = D.ahead(3 * C.TILE, (i - 2) * 2 * C.TILE)
            if x then D.list[#D.list + 1] = D.make(i, x, z) end
        end
    end
    D.turn, D.nextAt = 0, 0
    D.CL.system(L("DUMMY_DONE"))
end

function D.tick(now)
    if #D.list == 0 or now < D.nextAt then return end
    D.nextAt = now + D.TURN
    D.turn = D.turn % #D.list + 1
    local d = D.list[D.turn]
    d.talkUntil = now + D.TALK
    D.lineId = D.lineId + 1
    local CL = D.CL
    if d.ent and d.ent.AnimState then
        d.ent.AnimState:PlayAnimation("dial_loop", true)
        if d.ent.DoTaskInTime then
            d.ent:DoTaskInTime(D.TALK, function(e) if e.AnimState then e.AnimState:PlayAnimation("idle_loop", true) end end)
        end
    end
    if d.mode == "w" then
        CL.onNative(d.uid, d.name, D.LINES[d.i], {0.8, 0.7, 1, 1}, true)
    else
        CL.onLine(d.uid, d.name, D.LINES[d.i], d.mode, D.lineId, d.x, d.z, false)
    end
end

-- for the Koetama feed: each figure as a test voice, talking during its turn, with its mode's range
function D.speakers()
    local out = {}
    local now = GetTime()
    for _, d in ipairs(D.list) do
        out[#out + 1] = {id = d.uid, name = d.name, test_voice = d.i, talking = now < d.talkUntil,
            position = {d.x, 1.6, d.z}, range = C.voiceRange(D.CL.ranges, d.mode)}
    end
    return out
end

return D
