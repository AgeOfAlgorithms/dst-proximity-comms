-- Keyboard keys for the talk key: by name ("V", "F5", "LSHIFT" - DST's KEY_<name> constants), shown with DST's own
-- labels (STRINGS.UI.CONTROLSSCREEN.INPUTS), and checked against the game's bindings as they are on this PC
-- (TheInputProxy:GetLocalizedControl: a single key bound to a control on the keyboard).
local Keys = {}

-- the chat's own keys: never the talk key
Keys.RESERVED = {ENTER = true, KP_ENTER = true, TAB = true, ESCAPE = true}

function Keys.code(name)
    if type(name) ~= "string" or not name:match("^[%w_]+$") then return nil end
    local v = rawget(_G, "KEY_" .. name)
    return type(v) == "number" and v or nil
end

-- a key code's name (the shortest of DST's KEY_* names for it), or nil
function Keys.nameOf(code)
    local best
    for k, v in pairs(_G) do
        if v == code and type(k) == "string" and k:sub(1, 4) == "KEY_" then
            local n = k:sub(5)
            if not best or #n < #best or (#n == #best and n < best) then best = n end
        end
    end
    return best
end

-- how a key is shown ("V", "F5", "Left Shift")
function Keys.label(name)
    local code = Keys.code(name)
    local inputs = STRINGS and STRINGS.UI and STRINGS.UI.CONTROLSSCREEN and STRINGS.UI.CONTROLSSCREEN.INPUTS
    return code and inputs and inputs[1] and inputs[1][code] or tostring(name)
end

-- the game's control a key is bound to on this PC (its name as the Controls screen shows it), or nil
function Keys.gameUse(code)
    if not (code and TheInputProxy and TheInputProxy.GetLocalizedControl) then return nil end
    -- (only the engine's own controls: below CONTROL_CUSTOM_START - asking the engine about it, or anything past it,
    --  is an assert that crashes the game; DST's update of 2026-10-22 added it, 103, and the mod crashed 5 s in)
    local last = rawget(_G, "CONTROL_CUSTOM_START") or rawget(_G, "VIRTUAL_CONTROL_START") or 10000
    for k, v in pairs(_G) do
        if type(k) == "string" and k:sub(1, 8) == "CONTROL_" and type(v) == "number" and v >= 0 and v < last then
            local ok, device, n, input1 = pcall(TheInputProxy.GetLocalizedControl, TheInputProxy, 0, v, false, true)
            if ok and device == 1 and n == 1 and input1 == code then
                local names = STRINGS and STRINGS.UI and STRINGS.UI.CONTROLSSCREEN and STRINGS.UI.CONTROLSSCREEN.CONTROLS
                return names and names[v + 1] or k
            end
        end
    end
    return nil
end

-- whether a key may be the talk key: nil (fine), or why not ("reserved", or the game's control)
function Keys.refusal(name)
    if not Keys.code(name) then return "unknown" end
    if Keys.RESERVED[name] then return "reserved" end
    return Keys.gameUse(Keys.code(name))
end

return Keys
