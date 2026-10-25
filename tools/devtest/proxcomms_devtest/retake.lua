-- Dev only: the screenshots' scenes again in a running test world, from DST's console (tools/devtest/shots.ps1 -Fresh
-- watches for them):  kleiloadlua("../mods/proxcomms_devtest/retake.lua")()
local function out(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
    print("[PCTEST] " .. table.concat(t, " "))
end
local function later(s, fn)
    staticScheduler:ExecuteInTime(s, function()
        local ok, err = pcall(fn)
        if not ok then out("ERROR", err) end
    end)
end
kleiloadlua("../mods/proxcomms_devtest/shots.lua")(_G, out, later)
