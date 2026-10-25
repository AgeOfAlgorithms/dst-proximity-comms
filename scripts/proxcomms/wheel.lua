-- Quick chat on a controller builds a message (the user, 2026-10-13), on DST's command wheel:
--   X   on a folder: open it; on a line (or a player's name): add it to the message and go back to Quick chat's main
--       wheel
--   Y   take the last piece back
--   A   send the message and close (whatever is picked; the user, 2026-10-15)
--   B   one wheel back; on Quick chat's main wheel: cancel (the message goes, the wheel closes)
--   hold B (W.HOLD s, still held: W.tick)   cancel from anywhere
-- The message shows in the wheel's centre.
--
-- The game side is W.env (modmain): now(), inQuick() (one of Quick chat's wheels is open), atMain() (its main wheel),
-- item() (the picked item's data: .pc_text for a line, .nestedwheel for a folder; nil: nothing picked), close() (the
-- whole command wheel), back() (one wheel up), toMain() (Quick chat's main wheel), open(name) (a folder's wheel),
-- refresh() (the centre's text).
local T = require "proxcomms/text"
local C = require "proxcomms/config"

local W = {draft = {}, held = {}, consumed = {}, HOLD = 0.5, DOUBLE = 0.35, env = nil, CL = nil}

function W.text()
    return table.concat(W.draft, " ")
end

-- add a piece (false: the message, with the controller's mark, would be over a chat line's length)
function W.add(piece)
    local t = #W.draft > 0 and (W.text() .. " " .. piece) or piece
    if T.len(C.PAD_MARK .. t) > C.MAX_LEN then return false end
    W.draft[#W.draft + 1] = piece
    if W.env then W.env.refresh() end
    return true
end

function W.pop()
    local p = table.remove(W.draft)
    if W.env then W.env.refresh() end
    return p
end

-- (the wheel closed: the message and any hold go; a hold that closed it still swallows its own release)
function W.clear()
    W.draft, W.held, W.accept = {}, {}, nil
end

function W.post()
    local t = W.text()
    W.draft = {}
    if t ~= "" and W.CL then W.CL.say(C.PAD_MARK .. t, W.CL.mode) end
    return t
end

local function cancel()
    W.draft = {}
    if W.env then W.env.close() end
end

-- every frame: holding B cancels the moment it is long enough
function W.tick()
    local env = W.env
    if not (env and env.inQuick()) then W.held = {} return end
    local t0 = W.held.b
    if t0 and env.now() - t0 >= W.HOLD then
        W.held.b, W.consumed.b = nil, true
        cancel()
    end
end

-- a control while one of Quick chat's wheels is open: true when it was ours (the wheel does not see it)
function W.control(control, down)
    local env = W.env
    if not (env and env.inQuick()) then
        if control == CONTROL_CANCEL and not down and W.consumed.b then W.consumed.b = nil return true end
        return false
    end
    if control == CONTROL_ACCEPT then
        -- (on the release of a press made in Quick chat: the press that opened it from DST's wheel is not a send)
        if down then
            W.accept = true
            return true
        end
        if not W.accept then return true end
        W.accept = nil
        W.post()
        env.close()
        return true
    elseif control == CONTROL_MENU_MISC_1 then                 -- X
        if down then
            local item = env.item()
            if item and item.nestedwheel then
                env.open(item.nestedwheel.name)
            elseif item and item.pc_text and W.add(item.pc_text) then
                env.toMain()
            end
        end
        return true
    elseif control == CONTROL_MENU_MISC_2 then                 -- Y
        if down then W.pop() end
        return true
    elseif control == CONTROL_CANCEL then
        if down then
            W.held.b, W.consumed.b = env.now(), nil
            return true
        end
        local t0 = W.held.b
        W.held.b = nil
        if W.consumed.b then W.consumed.b = nil return true end
        if t0 and env.now() - t0 >= W.HOLD then cancel() return true end
        if env.atMain() then cancel() else env.back() end
        return true
    end
    return false
end

-- the command wheel's own button (R3 on an Xbox pad): one press is DST's command wheel as always; a second press
-- within W.DOUBLE s goes straight to Quick chat (the user, 2026-10-13; L3 stays the target lock). DST opens and closes
-- the wheel on the button's RELEASE, so releases are counted. -> true: this release was the double press (Quick chat
-- opened; the wheel must not close)
function W.wheelButton(down, wheelOpen, now)
    if down then return false end
    if wheelOpen and W.lastTap and now - W.lastTap < W.DOUBLE then
        W.lastTap = nil
        return true
    end
    W.lastTap = now
    return false
end

return W
