-- auto_skip_op_ed.lua
local mp = require('mp')
local utils = require('mp.utils')
local msg = require('mp.msg')

------------------------------------------------------------
-- CONFIGURATION & STORAGE
------------------------------------------------------------
local config_file = mp.command_native({"expand-path", "~~/auto_skip_settings.json"})
local skip_op = true
local skip_ed = true

------------------------------------------------------------
-- RUNTIME STATE
------------------------------------------------------------
local ranges = {}
local ignored = {}
local active_timer = nil
local pending = nil
local time_left = 0

------------------------------------------------------------
-- SETTINGS MANAGEMENT
------------------------------------------------------------
local function load_settings()
    local f = io.open(config_file, "r")
    if f then
        local data = utils.parse_json(f:read("*all"))
        f:close()
        if data then
            if data.skip_op ~= nil then skip_op = data.skip_op end
            if data.skip_ed ~= nil then skip_ed = data.skip_ed end
        end
    end
end

local function save_settings()
    local f = io.open(config_file, "w")
    if f then
        f:write(utils.format_json({skip_op = skip_op, skip_ed = skip_ed}))
        f:close()
    end
end

------------------------------------------------------------
-- UTILITIES
------------------------------------------------------------
local function clear_timer()
    if active_timer then
        active_timer:kill()
        active_timer = nil
    end
end

local function get_color(t)
    if t > 2.5 then
        local ratio = (5.0 - t) / 2.5
        local r = math.floor(255 * ratio)
        local g = math.floor(255 * (1 - ratio))
        return string.format("%02X%02X%02X", 0, g, r)
    else
        local blink = math.floor((mp.get_time() * 5) % 2)
        if blink == 0 then return "FFFFFF" else return "0000FF" end
    end
end

------------------------------------------------------------
-- HEURISTIC CHAPTER CLUSTERING ENGINE
------------------------------------------------------------
local function scan_chapters()
    ranges = {}
    ignored = {}
    clear_timer()
    pending = nil

    local count = mp.get_property_number("chapter-list/count", 0)
    local duration = mp.get_property_number("duration")
    if count == 0 or not duration then return end

    local chapters = {}
    local found_op, found_ed = false, false

    -- 1. Gather all chapters and durations
    for i = 0, count - 1 do
        local start = mp.get_property_number("chapter-list/" .. i .. "/time")
        local title = (mp.get_property("chapter-list/" .. i .. "/title") or ""):lower()
        local next_start = (i == count - 1) and duration or mp.get_property_number("chapter-list/" .. (i + 1) .. "/time")

        table.insert(chapters, {start = start, end_ = next_start, title = title, duration = next_start - start})
        if title:find("op") or title:find("opening") then found_op = true end
        if title:find("ed") or title:find("ending") then found_ed = true end
    end

    local best_op = {score = math.huge, chapter = nil}
    local best_ed = {score = math.huge, chapter = nil}

    -- 2. Analyze and score chapters
    for _, c in ipairs(chapters) do
        local t = c.title
        local is_op = t:find("op") or t:find("opening")
        local is_ed = t:find("ed") or t:find("ending")
        local protected = t:find("intro") or t:find("prologue") or t:find("part") or t:find("scene") or t:find("pv") or t:find("preview")

        -- Explicit matches bypass heuristics
        if is_op then
            table.insert(ranges, {start=c.start, end_=c.end_, type="op"})
        elseif is_ed then
            table.insert(ranges, {start=c.start, end_=c.end_, type="ed"})
        
        -- Heuristic candidate scoring (75-110s window)
        elseif not protected then
            local d = c.duration
            local pos_pct = c.start / duration

            if d >= 75 and d <= 110 then
                local dur_penalty = math.abs(d - 90) * 2 
                
                -- OP Candidate (early in file)
                if pos_pct < 0.35 then
                    local score = dur_penalty + (pos_pct * 100)
                    if score < best_op.score then best_op = {score = score, chapter = c} end
                end
                
                -- ED Candidate (late in file)
                if pos_pct > 0.65 then
                    local score = dur_penalty + (math.abs(pos_pct - 0.92) * 100)
                    if score < best_ed.score then best_ed = {score = score, chapter = c} end
                end
            end
        end
    end

    -- 3. Fallback to best heuristic candidates if explicit labels were missing
    if not found_op and best_op.chapter then
        table.insert(ranges, {start=best_op.chapter.start, end_=best_op.chapter.end_, type="op"})
    end
    if not found_ed and best_ed.chapter then
        table.insert(ranges, {start=best_ed.chapter.start, end_=best_ed.chapter.end_, type="ed"})
    end
end

------------------------------------------------------------
-- TICK ENGINE (OSD & COUNTDOWN)
------------------------------------------------------------
local function tick()
    time_left = time_left - 0.2
    local ass_start = mp.get_property("osd-ass-cc/0") or ""
    local ass_end = mp.get_property("osd-ass-cc/1") or ""

    if time_left <= 0 then
        clear_timer()
        mp.set_property_number("time-pos", pending.end_)
        mp.osd_message(ass_start .. "{\\an7\\fs12\\b1\\c&HFFFFFF&}✓ SKIPPED " .. pending.type:upper() .. ass_end, 2)
        pending = nil
        return
    end

    local color = get_color(time_left)
    local display = math.ceil(time_left)
    mp.osd_message(ass_start .. "{\\an7\\fs12\\b1\\c&HFFFFFF&}Skipping in {\\c&H" .. color .. "&}" .. display .. ass_end, 0.25)
end

------------------------------------------------------------
-- LIVE TIMELINE MONITOR
------------------------------------------------------------
local function check(_, pos)
    if not pos then return end

    -- Abort tracking if the user actively seeks outside the targeted play zone
    if pending then
        if pos < pending.start or pos >= pending.end_ then
            clear_timer()
            pending = nil
        end
        return
    end

    -- Track current position inside loaded ranges
    for _, r in ipairs(ranges) do
        if pos >= r.start and pos < r.end_ - 1 then
            local enabled = (r.type == "op" and skip_op) or (r.type == "ed" and skip_ed)

            if enabled and not ignored[tostring(r.start)] then
                pending = r
                time_left = 5.0
                tick()
                active_timer = mp.add_periodic_timer(0.2, tick)
                return
            end
        end
    end
end

------------------------------------------------------------
-- ACTIONS & INTERRUPTS
------------------------------------------------------------
local function on_pause(_, paused)
    if not paused or not pending or not active_timer then return end
    clear_timer()
    ignored[tostring(pending.start)] = true
    
    local ass_start = mp.get_property("osd-ass-cc/0") or ""
    local ass_end = mp.get_property("osd-ass-cc/1") or ""
    mp.osd_message(ass_start .. "{\\an7\\fs12\\b1\\c&H888888&}[SKIP CANCELLED]" .. ass_end, 2)
    
    pending = nil
    mp.add_timeout(0.01, function() mp.set_property_bool("pause", false) end)
end

local function status(name, val)
    local ass_start = mp.get_property("osd-ass-cc/0") or ""
    local ass_end = mp.get_property("osd-ass-cc/1") or ""
    if val then
        mp.osd_message(ass_start .. "{\\an7\\fs12\\b1\\c&HFFFFFF&}Skip " .. name .. ": {\\c&HFFFF00&}ON" .. ass_end, 4)
    else
        mp.osd_message(ass_start .. "{\\an7\\fs12\\b1\\c&H888888&}Skip " .. name .. ": OFF" .. ass_end, 4)
    end
end

local function toggle_op() skip_op = not skip_op; save_settings(); status("OP", skip_op) end
local function toggle_ed() skip_ed = not skip_ed; save_settings(); status("ED", skip_ed) end

------------------------------------------------------------
-- RUNTIME INITIALIZATION
------------------------------------------------------------
load_settings()

mp.register_event("playback-restart", scan_chapters)
mp.observe_property("time-pos", "number", check)
mp.observe_property("pause", "bool", on_pause)

mp.add_key_binding("alt+a", "toggle-op", toggle_op)
mp.add_key_binding("alt+s", "toggle-ed", toggle_ed)
