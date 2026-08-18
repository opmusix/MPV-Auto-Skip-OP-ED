local mp = require('mp')
local utils = require('mp.utils')

------------------------------------------------------------
-- CONFIGURATION & STORAGE
------------------------------------------------------------
local config_file = mp.command_native({"expand-path", "~~/auto_skip_settings.json"})

-- Master Toggles (These are the ONLY things saved/loaded from JSON now)
local skip_op = true
local skip_ed = true

-- Behavioral Features
local cancel_auto_resume = true  -- Pressing Space (Pause) cancels the skip AND instantly resumes playback.
local allow_reskip = true        -- Rewinding to BEFORE the OP/ED trigger point re-arms the skip.

-- Timing Configurations (Hardcoded here, will never be overwritten by JSON again)
local op_timer = 5.0
local ed_timer = 4.0

-- "leadin" defines how many seconds INSIDE the chapter the timer runs before skipping.
-- Example: OP starts at 00:37. Timer=5, Leadin=2. 
-- Timer appears at 00:34 (Green). Turns Red at 00:37. Skips at 00:39.
local op_leadin = 2.0   -- <--- FIXED TO 2.0 HERE!
local ed_leadin = 2.0   

-- Heuristic Fallback Bounds (for unnamed chapters)
local heuristic_min = 75.0
local heuristic_max = 110.0

------------------------------------------------------------
-- RUNTIME STATE
------------------------------------------------------------
local ranges = {}
local session_ignored = {} 
local active_timer = nil
local pending = nil
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
-- SETTINGS MANAGEMENT (Fixed to only handle toggles)
------------------------------------------------------------
local function load_settings()
    local f = io.open(config_file, "r")
    if f then
        local content = f:read("*all")
        f:close()
        if content and content ~= "" then
            local data = utils.parse_json(content)
            if data then
                if data.skip_op ~= nil then skip_op = data.skip_op end
                if data.skip_ed ~= nil then skip_ed = data.skip_ed end
            end
        end
    end
end

local function save_settings()
    local f = io.open(config_file, "w")
    if f then
        f:write(utils.format_json({
            skip_op = skip_op, 
            skip_ed = skip_ed
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

local function get_range_signature(r)
    return string.format("%s_%.2f_%.2f", r.type, r.start, r.end_)
end

local function title_matches(title, patterns)
    for _, p in ipairs(patterns) do
        if p:match("^[a-z0-9 %-]+$") then
            if title:find("%f[%w]" .. p .. "%f[%W]") then return true end
        else
            if title:find(p, 1, true) then return true end
        end
    end
    return false
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

    local chapters_native = mp.get_property_native("chapter-list")
    local duration = mp.get_property_number("duration")
    
    if not chapters_native or #chapters_native == 0 or not duration then return end

    local has_strict_op, has_strict_ed = false, false
    for _, c in ipairs(chapters_native) do
        local title = (c.title or ""):lower()
        if title_matches(title, strict_op_patterns) then has_strict_op = true end
        if title_matches(title, strict_ed_patterns) then has_strict_ed = true end
    end

    local op_patterns = has_strict_op and strict_op_patterns or merge_patterns(strict_op_patterns, ambiguous_op_patterns)
    local ed_patterns = has_strict_ed and strict_ed_patterns or merge_patterns(strict_ed_patterns, ambiguous_ed_patterns)
    local current_protected = merge_patterns(protected_patterns)
    if has_strict_op then current_protected = merge_patterns(current_protected, ambiguous_op_patterns) end
    if has_strict_ed then current_protected = merge_patterns(current_protected, ambiguous_ed_patterns) end

    local raw_chapters = {}
    for i, c in ipairs(chapters_native) do
        local start = c.time
        local title = (c.title or ""):lower()
        local next_start = (i == #chapters_native) and duration or chapters_native[i + 1].time
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
            
            table.insert(chapters, {start = cur.start, end_ = end_time, title = cur.title, duration = end_time - cur.start})
            idx = lookahead
        else
            table.insert(chapters, cur)
            idx = idx + 1
        end
    end

    local best_op, best_ed = {score = math.huge}, {score = math.huge}
    local found_op, found_ed = false, false

    for _, c in ipairs(chapters) do
        local t, d = c.title, c.duration
        local is_strict_op = title_matches(t, strict_op_patterns)
        local is_strict_ed = title_matches(t, strict_ed_patterns)
        local is_op = is_strict_op or (title_matches(t, op_patterns) and d >= heuristic_min and d <= heuristic_max)
        local is_ed = is_strict_ed or (title_matches(t, ed_patterns) and d >= heuristic_min and d <= heuristic_max)
        local protected = title_matches(t, current_protected)

        if is_op and not protected then
            table.insert(ranges, {start=c.start, end_=c.end_, type="op"}); found_op = true
        elseif is_ed and not protected then
            table.insert(ranges, {start=c.start, end_=c.end_, type="ed"}); found_ed = true
        elseif not protected then
            if d >= heuristic_min and d <= heuristic_max then
                local dur_penalty = math.exp(math.abs(d - 90) / 10) - 1
                local pos_pct = c.start / duration
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

    if not found_op and best_op.chapter then table.insert(ranges, {start=best_op.chapter.start, end_=best_op.chapter.end_, type="op"}) end
    if not found_ed and best_ed.chapter then table.insert(ranges, {start=best_ed.chapter.start, end_=best_ed.chapter.end_, type="ed"}) end
end

------------------------------------------------------------
-- TICK ENGINE (OSD & COUNTDOWN)
------------------------------------------------------------
local function tick()
    if not pending then return end

    local is_enabled = (pending.type == "op" and skip_op) or (pending.type == "ed" and skip_ed)
    if not is_enabled then
        clear_timer(); pending = nil; return
    end

    local pos = mp.get_property_number("time-pos", 0)
    -- Calculate precise time left to the absolute skip point
    local time_left = pending.skip_point - pos
    local ass_start = mp.get_property("osd-ass-cc/0") or ""
    local ass_end = mp.get_property("osd-ass-cc/1") or ""

    if time_left <= 0.05 then
        clear_timer()
        local signature = get_range_signature(pending)
        session_ignored[signature] = true
        
        mp.set_property_number("time-pos", pending.end_)
        mp.osd_message(ass_start .. "{\\an7\\pos(3,3)\\fs8\\b1\\c&HFFFFFF&}✓ SKIPPED " .. pending.type:upper() .. ass_end, 2)
        pending = nil
        return
    end

    -- Flawless Dynamic Color System based on your math:
    -- If we crossed the Chapter Start line, start flashing. If we haven't, stay calm Green.
    local color = pos >= pending.start and (math.floor((mp.get_time() * 5) % 2) == 0 and "0000FF" or "FFFFFF") or "00FF00"
    
    mp.osd_message(ass_start .. "{\\an7\\pos(3,3)\\fs8\\b1\\c&HFFFFFF&}Skipping in {\\c&H" .. color .. "&}" .. math.ceil(time_left) .. ass_end, 0.25)
end

------------------------------------------------------------
-- LIVE TIMELINE MONITOR
------------------------------------------------------------
local function check(_, pos)
    if not pos then return end

    -- Smart Re-skip feature: Only re-arms if you explicitly rewind BEFORE the trigger start line.
    if allow_reskip then
        for _, r in ipairs(ranges) do
            local sig = get_range_signature(r)
            if session_ignored[sig] then
                local timer = (r.type == "op") and op_timer or ed_timer
                local leadin = (r.type == "op") and op_leadin or ed_leadin
                local pre_chapter = timer - leadin
                local trigger_start = math.max(0, r.start - pre_chapter)
                
                if pos < trigger_start - 0.5 then
                    session_ignored[sig] = nil
                end
            end
        end
    end

    if pending then
        -- Failsafe: if we naturally bypass it without skipping, clear it.
        if pos >= pending.end_ then
            clear_timer(); pending = nil
        end
        return
    end

    for _, r in ipairs(ranges) do
        local leadin = (r.type == "op") and op_leadin or ed_leadin
        local timer = (r.type == "op") and op_timer or ed_timer

        -- Pre-chapter evaluates how many seconds BEFORE chapter to show the timer
        local pre_chapter = timer - leadin
        local trigger_start = math.max(0, r.start - pre_chapter)
        local skip_point = r.start + leadin

        if pos >= trigger_start and pos < skip_point then
            local enabled = (r.type == "op" and skip_op) or (r.type == "ed" and skip_ed)
            
            if enabled and not session_ignored[get_range_signature(r)] then
                pending = r
                pending.trigger_start = trigger_start
                pending.skip_point = skip_point
                
                tick()
                active_timer = mp.add_periodic_timer(0.1, tick)
                return
            end
        end
    end
end

------------------------------------------------------------
-- ACTIONS & INTERRUPTS
------------------------------------------------------------
local function on_seek()
    if not pending or not active_timer then return end
    
    -- Native Seek cancellation
    clear_timer()
    local signature = get_range_signature(pending)
    session_ignored[signature] = true

    local ass_start = mp.get_property("osd-ass-cc/0") or ""
    local ass_end = mp.get_property("osd-ass-cc/1") or ""
    mp.osd_message(ass_start .. "{\\an7\\pos(3,3)\\fs8\\b1\\c&H888888&}[SKIP CANCELED BY SEEK]" .. ass_end, 2)
    pending = nil
end

local function on_pause(_, paused)
    if not paused or not pending or not active_timer then return end
    clear_timer()

    local signature = get_range_signature(pending)
    session_ignored[signature] = true

    local ass_start = mp.get_property("osd-ass-cc/0") or ""
    local ass_end = mp.get_property("osd-ass-cc/1") or ""
    mp.osd_message(ass_start .. "{\\an7\\pos(3,3)\\fs8\\b1\\c&H888888&}[SKIP CANCELED]" .. ass_end, 2)
    pending = nil
    
    if cancel_auto_resume then
        mp.set_property_bool("pause", false)
    end
end

local function status(name, val)
    local ass_start = mp.get_property("osd-ass-cc/0") or ""
    local ass_end = mp.get_property("osd-ass-cc/1") or ""
    if val then
        mp.osd_message(ass_start .. "{\\an7\\pos(3,3)\\fs8\\b1\\c&HFFFFFF&}Skip " .. name .. ": {\\c&HFFFF00&}ON" .. ass_end, 4)
    else
        mp.osd_message(ass_start .. "{\\an7\\pos(3,3)\\fs8\\b1\\c&H888888&}Skip " .. name .. ": OFF" .. ass_end, 4)
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
mp.register_event("seek", on_seek)

mp.add_key_binding("alt+a", "toggle-op", toggle_op)
mp.add_key_binding("alt+s", "toggle-ed", toggle_ed)
