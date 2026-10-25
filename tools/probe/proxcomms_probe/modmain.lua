-- QueryServer probe: what DST's HTTP client sends and gets back, against tools/probe/stub_server.py (or Koetama).
-- Every result is a log line starting "[PCPROBE]" (client_log.txt). Runs once at load (the main menu: a client-only
-- mod's modmain runs in the frontend), then quits the game (QUIT_WHEN_DONE).

local G = GLOBAL
local select, tostring, table, string = G.select, G.tostring, G.table, G.string
local TheSim = G.TheSim
local PORT = 47170
local BASE = "http://127.0.0.1:" .. PORT
local QUIT_WHEN_DONE = true

local function now() return G.GetTimeRealSeconds() end
local function out(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    G.print("[PCPROBE] " .. table.concat(parts, " "))
end

local steps = {}
local function nextstep()
    local s = table.remove(steps, 1)
    if s then s() else
        out("DONE")
        if QUIT_WHEN_DONE then G.RequestShutdown() end
    end
end

local function q(label, url, method, body, cb)
    local t = now()
    local ok, err = G.pcall(function()
        TheSim:QueryServer(url, function(result, isSuccessful, resultCode)
            local dt = (now() - t) * 1000
            out(label, "ok=" .. tostring(isSuccessful), "code=" .. tostring(resultCode),
                string.format("%.1fms", dt), "len=" .. tostring(result and #result),
                "body=" .. tostring(result and result:sub(1, 120)))
            if cb then cb(result, isSuccessful, resultCode, dt) end
        end, method, body)
    end)
    if not ok then
        out(label, "RAISED", err)
        if cb then cb(nil, false, -1, 0) end
    end
end

local feed = '{"type":"feed","session":1,"ack":0,"wait":0,"me":"KU_probe","name":"Wilson \\u00e9\\u00e8 \xe3\x81\x93\xe3\x82\x93","listen":"off"}'

-- 1. GET /
steps[#steps + 1] = function() q("get_root", BASE .. "/", "GET", nil, function() nextstep() end) end
-- 2. POST a feed (Content-Length? Content-Type?)
steps[#steps + 1] = function() q("post_feed", BASE .. "/", "POST", feed, function() nextstep() end) end
-- 3. POST with no body
steps[#steps + 1] = function() q("post_empty", BASE .. "/", "POST", "", function() nextstep() end) end
-- 4. POST 20 KB
steps[#steps + 1] = function()
    local big = '{"type":"feed","pad":"' .. string.rep("x", 20 * 1024) .. '"}'
    q("post_20kb", BASE .. "/", "POST", big, function() nextstep() end)
end
-- 5. localhost instead of 127.0.0.1
steps[#steps + 1] = function() q("get_localhost", "http://localhost:" .. PORT .. "/", "GET", nil, function() nextstep() end) end
-- 6. a status code (400) and a refused port
steps[#steps + 1] = function() q("status_400", BASE .. "/status/400", "POST", feed, function() nextstep() end) end
steps[#steps + 1] = function() q("status_503", BASE .. "/status/503", "POST", feed, function() nextstep() end) end
steps[#steps + 1] = function() q("refused", "http://127.0.0.1:47179/", "POST", feed, function() nextstep() end) end
-- 7. a 60 KB answer with UTF-8
steps[#steps + 1] = function()
    q("big_answer", BASE .. "/big/60", "GET", nil, function(result)
        if result then
            local okj, obj = G.pcall(G.json.decode, result)
            out("big_answer decoded=" .. tostring(okj and obj ~= nil), "text_bytes=" .. tostring(okj and obj and obj.text and #obj.text),
                "said_bytes=" .. tostring(okj and obj and obj.bytes))
        end
        nextstep()
    end)
end
-- 8. latency: 20 POSTs one after another
steps[#steps + 1] = function()
    local n, total, t0 = 0, 0, now()
    local function one()
        q("seq" .. n, BASE .. "/", "POST", feed, function(_, _, _, dt)
            n, total = n + 1, total + dt
            if n < 20 then one() else
                out(string.format("seq20 avg=%.1fms wall=%.0fms", total / 20, (now() - t0) * 1000))
                nextstep()
            end
        end)
    end
    one()
end
-- 9. concurrency: 4 requests held 1 s each, sent at once (1 s total = parallel; 4 s = one at a time)
steps[#steps + 1] = function()
    local left, t0 = 4, now()
    for i = 1, 4 do
        q("par" .. i, BASE .. "/hold/1", "POST", feed, function()
            left = left - 1
            if left == 0 then
                out(string.format("par4 wall=%.0fms", (now() - t0) * 1000))
                nextstep()
            end
        end)
    end
end
-- 10. long poll + an urgent request behind it: does the second come back before the first?
steps[#steps + 1] = function()
    local left, t0 = 2, now()
    q("longpoll", BASE .. "/hold/1", "POST", feed, function()
        out(string.format("longpoll back at %.0fms", (now() - t0) * 1000))
        left = left - 1
        if left == 0 then nextstep() end
    end)
    q("urgent", BASE .. "/", "POST", feed, function()
        out(string.format("urgent back at %.0fms", (now() - t0) * 1000))
        left = left - 1
        if left == 0 then nextstep() end
    end)
end
-- 11. a held answer longer than any client timeout we might hit (3 s)
steps[#steps + 1] = function() q("hold3", BASE .. "/hold/3", "POST", feed, function() nextstep() end) end

out("start", "QueryServer=" .. tostring(TheSim.QueryServer ~= nil), "frontend=" .. tostring(G.IsInFrontEnd and G.IsInFrontEnd()))
nextstep()
