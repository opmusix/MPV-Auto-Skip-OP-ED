local mp = require('mp')

------------------------------------------------------------
-- USER CONFIGURATION
-- Edit these variables to customize the script's behavior.
------------------------------------------------------------
local config = {
    -- Master Toggles (Default state on startup)
    skip_op = true,
    skip_ed = true,

    -- Behavioral Features
    cancel_auto_resume = true,  -- Pressing Space (Pause) cancels auto-skip AND instantly resumes playback.
    allow_reskip = true,        -- Rewinding to BEFORE the OP/ED trigger point re-arms the skip.

    -- Timing Configurations (in seconds)
    -- NOTE: Set timer to 0.0 for Instant Teleport mode!
    op_timer = 5.0,             -- Total countdown duration for OP
    ed_timer = 4.0,             -- Total countdown duration for ED

    -- 'leadin' defines how many seconds INSIDE the chapter the timer runs before skipping.
    -- Example: OP starts at 00:37. Timer=5, Leadin=2. 
    -- Timer appears at 00:34 (Green). Turns Red at 00:37. Skips at 00:39.
    op_leadin = 2.0,   
    ed_leadin = 2.0,   

    -- Duration Limits
    max_auto_duration = 91.0,   -- MAXIMUM duration for auto-skip. Longer keyword chapters trigger manual prompt.
    heuristic_min = 75.0,
    heuristic_max = 91.0        -- Synced with max_auto_duration
}

------------------------------------------------------------
-- RUNTIME STATE (Do not edit below this line)
------------------------------------------------------------
local ranges = {}
local session_ignored = {} 
local active_timer = nil
local pending = nil
local current_file_path = nil

-- Manual Prompt State
local manual_pending = nil
local manual_timer = nil

------------------------------------------------------------
-- KEYWORD PATTERNS
------------------------------------------------------------
local strict_op_patterns = {"op", "opening", "open", "オープニング", "ncop", "creditless op", "opening a", "opening 1"}
local strict_ed_patterns = {"ed", "ending", "end", "エンディング", "nced", "creditless ed", "ending a", "ending 1", "credits", "credits start"}
local ambiguous_op_patterns = {"intro"}
local ambiguous_ed_patterns = {}
local protected_patterns = {"prologue", "part", "scene", "pv", "preview", "next episode", "recap", "ending end", "credits end"}

local function merge_patterns(t1, t2)
    local res = {}
    for _, v in ipairs(t1) do table.insert(res, v) end
    if t2 then for _, v in ipairs(t2) do table.insert(res, v) end end
    return res
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
-- MANUAL PROMPT ENGINE
------------------------------------------------------------
local function clear_manual_prompt()
    if manual_timer then 
        manual_timer:kill()
        manual_timer = nil 
    end
    if manual_pending then
        mp.remove_key_binding("manual-skip-space")
        manual_pending = nil
        mp.osd_message("") 
    end
end

local function execute_manual_skip()
    if not manual_pending then return end
    local r = manual_pending
    clear_manual_prompt()
    
    local type_name = r.type:gsub("manual_", ""):upper()
    local ass_start = mp.get_property("osd-ass-cc/0") or ""
    local ass_end = mp.get_property("osd-ass-cc/1") or ""
    
    mp.set_property_number("time-pos", r.end_)
    mp.osd_message(ass_start .. "{\\an7\\pos(3,3)\\fs8\\b1\\c&HFFFFFF&}✓ SKIPPED LONG " .. type_name .. ass_end, 2)
end

local function trigger_manual_prompt(r)
    manual_pending = r
    local ass_start = mp.get_property("osd-ass-cc/0") or ""
    local ass_end = mp.get_property("osd-ass-cc/1") or ""
    
    -- \alpha&HA0& creates low opacity (transparent) text
    mp.osd_message(ass_start .. "{\\an7\\pos(3,3)\\fs8\\b1\\alpha&HA0&}Skip? Press Space" .. ass_end, 3.0)
    
    -- Temporarily hijack the spacebar for manual confirmation
    mp.add_forced_key_binding("SPACE", "manual-skip-space", execute_manual_skip)
    manual_timer = mp.add_timeout(3.0, clear_manual_prompt)
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
    clear_manual_prompt()
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
        
        local is_op = is_strict_op or (title_matches(t, op_patterns) and d >= config.heuristic_min and d <= config.max_auto_duration)
        local is_ed = is_strict_ed or (title_matches(t, ed_patterns) and d >= config.heuristic_min and d <= config.max_auto_duration)
        local protected = title_matches(t, current_protected)

        if is_op and not protected then
            if d > config.max_auto_duration then
                table.insert(ranges, {start=c.start, end_=c.end_, type="manual_op"})
            else
                table.insert(ranges, {start=c.start, end_=c.end_, type="op"}); found_op = true
            end
        elseif is_ed and not protected then
            if d > config.max_auto_duration then
                table.insert(ranges, {start=c.start, end_=c.end_, type="manual_ed"})
            else
                table.insert(ranges, {start=c.start, end_=c.end_, type="ed"}); found_ed = true
            end
        elseif not protected then
            if d >= config.heuristic_min and d <= config.max_auto_duration then
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

    local is_enabled = (pending.type == "op" and config.skip_op) or (pending.type == "ed" and config.skip_ed)
    if not is_enabled then
        clear_timer(); pending = nil; return
    end

    local pos = mp.get_property_number("time-pos", 0)
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

    local color = pos >= pending.start and (math.floor((mp.get_time() * 5) % 2) == 0 and "0000FF" or "FFFFFF") or "00FF00"
    
    mp.osd_message(ass_start .. "{\\an7\\pos(3,3)\\fs8\\b1\\c&HFFFFFF&}Skipping in {\\c&H" .. color .. "&}" .. math.ceil(time_left) .. ass_end, 0.25)
end

------------------------------------------------------------
-- LIVE TIMELINE MONITOR
------------------------------------------------------------
local function check(_, pos)
    if not pos then return end

    if config.allow_reskip then
        for _, r in ipairs(ranges) do
            local sig = get_range_signature(r)
            if session_ignored[sig] then
                if r.type == "manual_op" or r.type == "manual_ed" then
                    if pos < r.start - 0.5 then session_ignored[sig] = nil end
                else
                    local timer = (r.type == "op") and config.op_timer or config.ed_timer
                    local leadin = (r.type == "op") and config.op_leadin or config.ed_leadin
                    local pre_chapter = timer - leadin
                    local trigger_start = math.max(0, r.start - pre_chapter)
                    
                    if pos < trigger_start - 0.5 then
                        session_ignored[sig] = nil
                    end
                end
            end
        end
    end

    if pending then
        if pos >= pending.end_ then
            clear_timer(); pending = nil
        end
        return
    end

    for _, r in ipairs(ranges) do
        if r.type == "manual_op" or r.type == "manual_ed" then
            -- Trigger manual prompt exactly as the chapter starts
            if pos >= r.start and pos < r.start + 0.5 then
                local enabled = (r.type == "manual_op" and config.skip_op) or (r.type == "manual_ed" and config.skip_ed)
                local sig = get_range_signature(r)
                
                if enabled and not session_ignored[sig] and not manual_pending then
                    session_ignored[sig] = true
                    trigger_manual_prompt(r)
                end
            end
        else
            local enabled = (r.type == "op" and config.skip_op) or (r.type == "ed" and config.skip_ed)
            local sig = get_range_signature(r)

            if enabled and not session_ignored[sig] then
                local timer = (r.type == "op") and config.op_timer or config.ed_timer

                -- ⚡ INSTANT TELEPORT MODE (If timer is set to 0 or less)
                if timer <= 0 then
                    if pos >= r.start and pos < r.end_ then
                        session_ignored[sig] = true
                        mp.set_property_number("time-pos", r.end_)
                        
                        local ass_start = mp.get_property("osd-ass-cc/0") or ""
                        local ass_end = mp.get_property("osd-ass-cc/1") or ""
                        mp.osd_message(ass_start .. "{\\an7\\pos(3,3)\\fs8\\b1\\c&HFFFFFF&}✓ SKIPPED " .. r.type:upper() .. ass_end, 2)
                        return
                    end
                else
                    -- ⏱️ OSD COUNTDOWN MODE
                    local leadin = (r.type == "op") and config.op_leadin or config.ed_leadin
                    local pre_chapter = timer - leadin
                    local trigger_start = math.max(0, r.start - pre_chapter)
                    local skip_point = r.start + leadin

                    if pos >= trigger_start and pos < skip_point then
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
    end
end

------------------------------------------------------------
-- ACTIONS & INTERRUPTS
------------------------------------------------------------
local function on_seek()
    if manual_pending then clear_manual_prompt() end

    if not pending or not active_timer then return end
    
    clear_timer()
    local signature = get_range_signature(pending)
    session_ignored[signature] = true

    local ass_start = mp.get_property("osd-ass-cc/0") or ""
    local ass_end = mp.get_property("osd-ass-cc/1") or ""
    mp.osd_message(ass_start .. "{\\an7\\pos(3,3)\\fs8\\b1\\c&H888888&}[SKIP CANCELED BY SEEK]" .. ass_end, 2)
    pending = nil
end

local function on_pause(_, paused)
    if paused and manual_pending then clear_manual_prompt() end

    if not paused or not pending or not active_timer then return end
    clear_timer()

    local signature = get_range_signature(pending)
    session_ignored[signature] = true

    local ass_start = mp.get_property("osd-ass-cc/0") or ""
    local ass_end = mp.get_property("osd-ass-cc/1") or ""
    mp.osd_message(ass_start .. "{\\an7\\pos(3,3)\\fs8\\b1\\c&H888888&}[SKIP CANCELED]" .. ass_end, 2)
    pending = nil
    
    if config.cancel_auto_resume then
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

local function toggle_op() config.skip_op = not config.skip_op; status("OP", config.skip_op) end
local function toggle_ed() config.skip_ed = not config.skip_ed; status("ED", config.skip_ed) end

------------------------------------------------------------
-- RUNTIME INITIALIZATION
------------------------------------------------------------
mp.register_event("playback-restart", scan_chapters)
mp.observe_property("time-pos", "number", check)
mp.observe_property("pause", "bool", on_pause)
mp.register_event("seek", on_seek)

mp.add_key_binding("alt+a", "toggle-op", toggle_op)
mp.add_key_binding("alt+s", "toggle-ed", toggle_ed)
