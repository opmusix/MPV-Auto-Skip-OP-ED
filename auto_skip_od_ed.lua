local mp = require('mp')
local utils = require('mp.utils')
local msg = require('mp.msg')

------------------------------------------------------------
-- CONFIGURATION & STORAGE
------------------------------------------------------------
local config_file = mp.command_native({"expand-path", "~~/auto_skip_settings.json"})
local skip_op = true
local skip_ed = true
local op_timer = 3.0
local ed_timer = 5.0

------------------------------------------------------------
-- RUNTIME STATE
------------------------------------------------------------
local ranges = {}
local session_ignored = {} 
local active_timer = nil
local pending = nil
local time_left = 0
local current_file_path = nil

------------------------------------------------------------
-- KEYWORD PATTERNS
------------------------------------------------------------
local strict_op_patterns = {"op", "opening", "open", "オープニング", "ncop", "creditless op", "opening a", "opening 1"}
local strict_ed_patterns = {"ed", "ending", "end", "エンディング", "nced", "creditless ed", "ending a", "ending 1"}
local ambiguous_op_patterns = {"intro"}
local ambiguous_ed_patterns = {"credits"}
local protected_patterns = {"prologue", "part", "scene", "pv", "preview", "next episode", "recap", "ending end"}

local function merge_patterns(t1, t2)
    local res = {}
    for _, v in ipairs(t1) do table.insert(res, v) end
    if t2 then for _, v in ipairs(t2) do table.insert(res, v) end end
    return res
end

------------------------------------------------------------
-- SETTINGS MANAGEMENT
------------------------------------------------------------
local function clamp_timer(val)
    local n = tonumber(val)
    if not n then return 5.0 end
    if n < 3.0 then return 3.0 end
    if n > 30.0 then return 30.0 end
    return n
end

local function load_settings()
    local f = io.open(config_file, "r")
    if f then
        local data = utils.parse_json(f:read("*all"))
        f:close()
        if data then
            if data.skip_op ~= nil then skip_op = data.skip_op end
            if data.skip_ed ~= nil then skip_ed = data.skip_ed end
            if data.op_timer ~= nil then op_timer = clamp_timer(data.op_timer) end
            if data.ed_timer ~= nil then ed_timer = clamp_timer(data.ed_timer) end
        end
    end
end

local function save_settings()
    local f = io.open(config_file, "w")
    if f then
        f:write(utils.format_json({
            skip_op = skip_op, 
            skip_ed = skip_ed,
            op_timer = op_timer,
            ed_timer = ed_timer
        }))
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

local function get_color(t, max_t)
    if t > 3.0 then
        -- Smart transition from Green to Red proportional to user's custom timer
        local window = max_t - 3.0
        if window <= 0 then window = 1 end -- Failsafe
        local ratio = (max_t - t) / window -- 0 at start, 1 at t=3.0
        
        local r = math.floor(255 * ratio)
        local g = math.floor(255 * (1 - ratio))
        return string.format("%02X%02X%02X", 0, g, r) -- MPV ASS BGR Format
    else
        -- STRICTLY LOCKED 3-SECOND ALARMING COLORS (Cannot be changed)
        local blink = math.floor((mp.get_time() * 5) % 2)
        if blink == 0 then return "FFFFFF" else return "0000FF" end
    end
end

local function title_matches(title, patterns)
    for _, p in ipairs(patterns) do
        if title:find(p, 1, true) then return true end
    end
    return false
end

local function get_range_signature(r)
    return string.format("%s_%.2f_%.2f", r.type, r.start, r.end_)
end

------------------------------------------------------------
-- HEURISTIC CHAPTER CLUSTERING ENGINE
------------------------------------------------------------
local function scan_chapters()
    local filepath = mp.get_property("path")
    
    if filepath and filepath == current_file_path then return end
    current_file_path = filepath

    ranges = {}
    session_ignored = {} 
    clear_timer()
    pending = nil

    local count = mp.get_property_number("chapter-list/count", 0)
    local duration = mp.get_property_number("duration")
    if count == 0 or not duration then return end

    local has_strict_op, has_strict_ed = false, false
    for i = 0, count - 1 do
        local title = (mp.get_property("chapter-list/" .. i .. "/title") or ""):lower()
        if title_matches(title, strict_op_patterns) then has_strict_op = true end
        if title_matches(title, strict_ed_patterns) then has_strict_ed = true end
    end

    local op_patterns = has_strict_op and strict_op_patterns or merge_patterns(strict_op_patterns, ambiguous_op_patterns)
    local ed_patterns = has_strict_ed and strict_ed_patterns or merge_patterns(strict_ed_patterns, ambiguous_ed_patterns)
    
    local current_protected = merge_patterns(protected_patterns)
    if has_strict_op then current_protected = merge_patterns(current_protected, ambiguous_op_patterns) end
    if has_strict_ed then current_protected = merge_patterns(current_protected, ambiguous_ed_patterns) end

    local raw_chapters = {}
    local found_op, found_ed = false, false

    for i = 0, count - 1 do
        local start = mp.get_property_number("chapter-list/" .. i .. "/time")
        local title = (mp.get_property("chapter-list/" .. i .. "/title") or ""):lower()
        local next_start = (i == count - 1) and duration or mp.get_property_number("chapter-list/" .. (i + 1) .. "/time")

        table.insert(raw_chapters, {start = start, end_ = next_start, title = title, duration = next_start - start})
    end

    local chapters = {}
    local idx = 1
    while idx <= #raw_chapters do
        local cur = raw_chapters[idx]
        
        local is_op = title_matches(cur.title, op_patterns) and not title_matches(cur.title, ed_patterns) and not title_matches(cur.title, current_protected)
        local is_ed = title_matches(cur.title, ed_patterns) and not title_matches(cur.title, op_patterns) and not title_matches(cur.title, current_protected)

        if is_op or is_ed then
            local end_time = cur.end_
            local lookahead = idx + 1
            local current_target_patterns = is_op and op_patterns or ed_patterns
            
            while lookahead <= #raw_chapters do
                local next_title = raw_chapters[lookahead].title
                if title_matches(next_title, current_target_patterns) and not title_matches(next_title, current_protected) then
                    end_time = raw_chapters[lookahead].end_
                    lookahead = lookahead + 1
                else
                    break
                end
            end
            
            table.insert(chapters, {
                start = cur.start,
                end_ = end_time,
                title = cur.title,
                duration = end_time - cur.start
            })
            idx = lookahead
        else
            table.insert(chapters, cur)
            idx = idx + 1
        end
    end

    for _, c in ipairs(chapters) do
        if title_matches(c.title, op_patterns) then found_op = true end
        if title_matches(c.title, ed_patterns) then found_ed = true end
    end

    local best_op = {score = math.huge, chapter = nil}
    local best_ed = {score = math.huge, chapter = nil}

    for _, c in ipairs(chapters) do
        local t = c.title
        local is_op = title_matches(t, op_patterns)
        local is_ed = title_matches(t, ed_patterns)
        local protected = title_matches(t, current_protected)

        if is_op and not protected then
            table.insert(ranges, {start=c.start, end_=c.end_, type="op"})
        elseif is_ed and not protected then
            table.insert(ranges, {start=c.start, end_=c.end_, type="ed"})
        elseif not protected then
            local d = c.duration
            local pos_pct = c.start / duration

            if d >= 75 and d <= 110 then
                local dur_penalty = math.exp(math.abs(d - 90) / 10) - 1
                
                if pos_pct < 0.35 then
                    local score = dur_penalty + ((pos_pct - 0.18)^2 / (2 * 0.08^2))
                    if score < best_op.score then best_op = {score = score, chapter = c} end
                end
                
                if pos_pct > 0.65 then
                    local score = dur_penalty + ((pos_pct - 0.92)^2 / (2 * 0.06^2))
                    if score < best_ed.score then best_ed = {score = score, chapter = c} end
                end
            end
        end
    end

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

    local color = get_color(time_left, pending.max_timer)
    local display = math.ceil(time_left)
    mp.osd_message(ass_start .. "{\\an7\\fs12\\b1\\c&HFFFFFF&}Skipping in {\\c&H" .. color .. "&}" .. display .. ass_end, 0.25)
end

------------------------------------------------------------
-- LIVE TIMELINE MONITOR
------------------------------------------------------------
local function check(_, pos)
    if not pos then return end

    if pending then
        if pos < pending.start or pos >= pending.end_ then
            clear_timer()
            pending = nil
        end
        return
    end

    for _, r in ipairs(ranges) do
        if pos >= r.start and pos < r.end_ - 1 then
            local enabled = (r.type == "op" and skip_op) or (r.type == "ed" and skip_ed)
            local signature = get_range_signature(r)

            if enabled and not session_ignored[signature] then
                pending = r
                pending.max_timer = (r.type == "op") and op_timer or ed_timer
                time_left = pending.max_timer
                
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
    
    local signature = get_range_signature(pending)
    session_ignored[signature] = true
    
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
