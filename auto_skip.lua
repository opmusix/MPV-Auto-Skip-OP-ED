local mp = require('mp')

-- USER CONFIGURATION
local config = {
    -- Master Toggles
    skip_op = true,
    skip_ed = true,

    -- Behavioral Features
    instant_skip = "off",   -- "off", "op", "ed", "both". Alt+d cycles off -> op -> ed -> both -> off.
    long_skip = false,          -- Ctrl+d toggles auto-skipping recognized long OP/ED chapters up to max_duration.
    cancel_auto_resume = true,  -- Pressing Space cancels auto-skip & resumes playback
    allow_reskip = true,        -- Rewinding before trigger re-arms skip

    -- Timing Configurations (in seconds)
    op_timer = 5.0,             -- Set to 0.0 for Instant Teleport mode
    ed_timer = 4.0,
    op_leadin = 2.0,
    ed_leadin = 2.0,
    manual_prompt_timer = 5.0,  -- Duration for the "Skip? Press Space" prompt

    -- Long Skip threshold, session-adjustable with Ctrl+Right / Ctrl+Left.
    -- This is used only for Long Skip eligibility, not for the fixed standard OP/ED limit.
    max_duration = 100.0,

    -- Duration Limits (in seconds)
    heuristic_min = 75.0        -- Minimum duration for fallback keyword-less detection
}

-- Fixed internal limit for normal OP/ED auto-skip.
-- OP/ED chapters at or below this are treated as standard automatic ranges.
-- This is intentionally fixed and is not controlled by max_duration.
local STANDARD_MAX_DURATION = 90.0

-- Fractional chapter durations are common.
-- This tolerance makes "97" include chapters like 97.35s.
-- If you want stricter behavior, set this to 0.001.
local DURATION_TOLERANCE = 1.0

local function clamp_max_duration(v)
    v = tonumber(v) or 97.0
    v = math.floor(v * 2 + 0.5) / 2
    if v < 1.0 then v = 1.0 end
    if v > 600.0 then v = 600.0 end
    return v
end

if type(config.instant_skip) ~= "string" then
    config.instant_skip = "off"
end
config.instant_skip = config.instant_skip:lower()

local valid_instant_modes = {
    off = true,
    op = true,
    ed = true,
    both = true
}
if not valid_instant_modes[config.instant_skip] then
    config.instant_skip = "off"
end

if type(config.long_skip) ~= "boolean" then
    config.long_skip = (config.long_skip == "on"
        or config.long_skip == "true"
        or config.long_skip == 1)
end

config.max_duration = clamp_max_duration(config.max_duration)

-- RUNTIME STATE
local ranges = {}
local session_ignored = {}
local active_timer = nil
local pending = nil
local current_file_path = nil
local manual_pending = nil
local manual_timer = nil

-- KEYWORD PATTERNS
-- Patterns are intentionally without trailing spaces.
-- title_matches() uses word-boundary matching for ASCII patterns.
local strict_op_patterns = {
    "op",
    "opening",
    "open",
    "オープニング",
    "ncop",
    "creditless op",
    "opening a",
    "opening 1"
}

local strict_ed_patterns = {
    "ed",
    "ending",
    "end",
    "エンディング",
    "nced",
    "creditless ed",
    "ending a",
    "ending 1",
    "credits",
    "credits start"
}

local ambiguous_op_patterns = {
    "intro"
}

local ambiguous_ed_patterns = {}

local protected_patterns = {
    "prologue",
    "part",
    "scene",
    "pv",
    "preview",
    "next episode",
    "recap",
    "ending end",
    "credits end",
    "post-credits",
    "post credits"
}

local function merge_patterns(t1, t2)
    local res = {}
    for _, v in ipairs(t1) do
        table.insert(res, v)
    end
    if t2 then
        for _, v in ipairs(t2) do
            table.insert(res, v)
        end
    end
    return res
end

-- UTILITIES
local function clear_timer()
    if active_timer then
        active_timer:kill()
        active_timer = nil
    end
end

local function get_range_signature(r)
    return string.format("%s_%.3f_%.3f", r.type, r.start, r.end_)
end

local function trim(s)
    return (s:match("^%s*(.-)%s*$"))
end

local function title_matches(title, patterns)
    local t = (title or ""):lower()

    for _, p in ipairs(patterns) do
        local pat = trim((p or ""):lower())

        if pat ~= "" then
            -- ASCII-ish patterns: use word-boundary matching.
            if pat:match("^[a-z0-9 %-]+$") then
                local escaped = pat:gsub("%-", "%%-")
                if t:find("%f[%w]" .. escaped .. "%f[%W]") then
                    return true
                end
            else
                -- Non-ASCII patterns, e.g. Japanese: use plain substring match.
                if t:find(pat, 1, true) then
                    return true
                end
            end
        end
    end

    return false
end

local function range_duration(r)
    return r.end_ - r.start
end

local function base_type_of(t)
    if t == "op" or t == "long_op" or t == "manual_op" then
        return "op"
    end
    if t == "ed" or t == "long_ed" or t == "manual_ed" then
        return "ed"
    end
    return nil
end

local function is_long_type(t)
    return t == "long_op" or t == "long_ed"
end

local function get_display_type(t)
    local base = base_type_of(t)
    if base then
        return base:upper()
    end
    return tostring(t):upper()
end

local function is_auto_eligible_range(r)
    if r.type == "manual_op" or r.type == "manual_ed" then
        return false
    end

    local base = base_type_of(r.type)
    if not base then
        return false
    end

    if not ((base == "op" and config.skip_op) or (base == "ed" and config.skip_ed)) then
        return false
    end

    if is_long_type(r.type) then
        return config.long_skip and range_duration(r) <= config.max_duration + DURATION_TOLERANCE
    end

    return true
end

local function instant_skip_applies(range_type)
    local base = base_type_of(range_type)
    if base ~= "op" and base ~= "ed" then
        return false
    end

    local s = type(config.instant_skip) == "string" and config.instant_skip:lower() or "off"
    return s == "both" or s == base
end

-- OSD HELPERS
local ASS_WHITE = "&HFFFFFF&"
local ASS_GRAY = "&H888888&"
local ASS_AQUA = "&HFFFF00&"
local ASS_LIME = "&H00FF00&"
local ASS_GREEN = "&H00C000&"

local OSD_PREFIX = "{\\an7\\pos(3,3)\\fs8\\b1}"

local function ass_wrap(text)
    local ass_start = mp.get_property("osd-ass-cc/0") or ""
    local ass_end = mp.get_property("osd-ass-cc/1") or ""
    return ass_start .. text .. ass_end
end

local function show_osd(text, duration)
    mp.osd_message(ass_wrap(text), duration)
end

local function ass_color(text, color)
    return "{\\c" .. color .. "}" .. text
end

local function format_seconds(v)
    if type(v) ~= "number" then
        return "?"
    end

    local rounded = math.floor(v * 10 + 0.5) / 10
    if math.abs(rounded - math.floor(rounded)) < 0.001 then
        return string.format("%d", math.floor(rounded))
    else
        return string.format("%.1f", rounded)
    end
end

local function get_current_chapter_duration()
    local pos = mp.get_property_number("time-pos", 0)

    -- Prefer detected script ranges.
    for _, r in ipairs(ranges) do
        if pos >= r.start and pos < r.end_ then
            return range_duration(r)
        end
    end

    -- Fallback to native mpv chapters.
    local chapters_native = mp.get_property_native("chapter-list")
    local duration = mp.get_property_number("duration")

    if chapters_native and duration then
        for i, c in ipairs(chapters_native) do
            local next_start = (i == #chapters_native) and duration or chapters_native[i + 1].time
            if pos >= c.time and pos < next_start then
                return next_start - c.time
            end
        end
    end

    return nil
end

local function show_max_duration_osd()
    local max_str = format_seconds(config.max_duration)
    local cur = get_current_chapter_duration()

    local lines =
        ass_color("Max duration: ", ASS_WHITE) ..
        ass_color(max_str, ASS_AQUA) ..
        ass_color("s", ASS_WHITE) ..
        "\\N" ..
        ass_color("Current chapter: ", ASS_WHITE)

    if cur then
        lines = lines .. ass_color(format_seconds(cur), ASS_AQUA) .. ass_color("s", ASS_WHITE)
    else
        lines = lines .. ass_color("?", ASS_AQUA)
    end

    show_osd(OSD_PREFIX .. lines, 2)
end

local function show_long_skip_osd()
    local max_str = format_seconds(config.max_duration)
    local cur = get_current_chapter_duration()

    local lines = ass_color("Long Skip: ", ASS_WHITE)

    if config.long_skip then
        lines = lines .. ass_color("ON", ASS_AQUA)
    else
        lines = lines .. ass_color("OFF", ASS_GRAY)
    end

    lines = lines ..
        "\\N" ..
        ass_color("Max duration: ", ASS_WHITE) ..
        ass_color(max_str, ASS_AQUA) ..
        ass_color("s", ASS_WHITE) ..
        "\\N" ..
        ass_color("Current chapter: ", ASS_WHITE)

    if cur then
        lines = lines .. ass_color(format_seconds(cur), ASS_AQUA) .. ass_color("s", ASS_WHITE)
    else
        lines = lines .. ass_color("?", ASS_AQUA)
    end

    show_osd(OSD_PREFIX .. lines, 4)
end

local function status(name, val)
    local text = OSD_PREFIX .. ass_color("Skip " .. name .. ": ", ASS_WHITE)

    if val then
        text = text .. ass_color("ON", ASS_AQUA)
    else
        text = text .. ass_color("OFF", ASS_GRAY)
    end

    show_osd(text, 4)
end

-- MANUAL PROMPT ENGINE
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
    if not manual_pending then
        return
    end

    local r = manual_pending
    clear_manual_prompt()

    local type_name = get_display_type(r.type)

    mp.set_property_number("time-pos", r.end_)
    show_osd(OSD_PREFIX .. ass_color("✓ SKIPPED LONG " .. type_name, ASS_WHITE), 2)
end

local function trigger_manual_prompt(r)
    manual_pending = r

    show_osd(OSD_PREFIX .. "{\\alpha&HA0&}Skip? Press Space", config.manual_prompt_timer)

    mp.add_forced_key_binding("SPACE", "manual-skip-space", execute_manual_skip)
    manual_timer = mp.add_timeout(config.manual_prompt_timer, clear_manual_prompt)
end

-- HEURISTIC CHAPTER CLUSTERING ENGINE
local function scan_chapters()
    local filepath = mp.get_property("path")
    if filepath and filepath == current_file_path then
        return
    end

    current_file_path = filepath
    ranges = {}
    session_ignored = {}
    clear_timer()
    clear_manual_prompt()
    pending = nil

    local chapters_native = mp.get_property_native("chapter-list")
    local duration = mp.get_property_number("duration")
    if not chapters_native or #chapters_native == 0 or not duration then
        return
    end

    local has_strict_op, has_strict_ed = false, false
    for _, c in ipairs(chapters_native) do
        local title = (c.title or ""):lower()
        if title_matches(title, strict_op_patterns) then has_strict_op = true end
        if title_matches(title, strict_ed_patterns) then has_strict_ed = true end
    end

    local op_patterns = has_strict_op and strict_op_patterns or merge_patterns(strict_op_patterns, ambiguous_op_patterns)
    local ed_patterns = has_strict_ed and strict_ed_patterns or merge_patterns(strict_ed_patterns, ambiguous_ed_patterns)

    local current_protected = merge_patterns(protected_patterns)
    if has_strict_op then
        current_protected = merge_patterns(current_protected, ambiguous_op_patterns)
    end
    if has_strict_ed then
        current_protected = merge_patterns(current_protected, ambiguous_ed_patterns)
    end

    local raw_chapters = {}
    for i, c in ipairs(chapters_native) do
        local start = c.time
        local title = (c.title or ""):lower()
        local next_start = (i == #chapters_native) and duration or chapters_native[i + 1].time

        table.insert(raw_chapters, {
            start = start,
            end_ = next_start,
            title = title,
            duration = next_start - start
        })
    end

    local chapters = {}
    local idx = 1
    while idx <= #raw_chapters do
        local cur = raw_chapters[idx]

        local is_op = title_matches(cur.title, op_patterns)
            and not title_matches(cur.title, ed_patterns)
            and not title_matches(cur.title, current_protected)

        local is_ed = title_matches(cur.title, ed_patterns)
            and not title_matches(cur.title, op_patterns)
            and not title_matches(cur.title, current_protected)

        if is_op or is_ed then
            local end_time = cur.end_
            local lookahead = idx + 1
            local current_target_patterns = is_op and op_patterns or ed_patterns

            while lookahead <= #raw_chapters do
                local next_title = raw_chapters[lookahead].title
                if title_matches(next_title, current_target_patterns)
                    and not title_matches(next_title, current_protected) then
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

    local best_op, best_ed = { score = math.huge }, { score = math.huge }
    local found_op, found_ed = false, false

    for _, c in ipairs(chapters) do
        local t, d = c.title, c.duration
        local is_op = title_matches(t, op_patterns)
        local is_ed = title_matches(t, ed_patterns)
        local protected = title_matches(t, current_protected)

        if is_op and not protected then
            found_op = true

            if d <= STANDARD_MAX_DURATION + DURATION_TOLERANCE then
                table.insert(ranges, { start = c.start, end_ = c.end_, type = "op" })
            else
                table.insert(ranges, { start = c.start, end_ = c.end_, type = "long_op" })
            end
        elseif is_ed and not protected then
            found_ed = true

            if d <= STANDARD_MAX_DURATION + DURATION_TOLERANCE then
                table.insert(ranges, { start = c.start, end_ = c.end_, type = "ed" })
            else
                table.insert(ranges, { start = c.start, end_ = c.end_, type = "long_ed" })
            end
        elseif not protected then
            -- Heuristic fallback remains limited to the fixed standard OP/ED length.
            if d >= config.heuristic_min and d <= STANDARD_MAX_DURATION + DURATION_TOLERANCE then
                local dur_penalty = math.exp(math.abs(d - 90) / 10) - 1
                local pos_pct = c.start / duration

                if pos_pct < 0.35 then
                    local score = dur_penalty + ((pos_pct - 0.18) ^ 2 / (2 * 0.08 ^ 2))
                    if score < best_op.score then
                        best_op = { score = score, chapter = c }
                    end
                end

                if pos_pct > 0.65 then
                    local score = dur_penalty + ((pos_pct - 0.92) ^ 2 / (2 * 0.06 ^ 2))
                    if score < best_ed.score then
                        best_ed = { score = score, chapter = c }
                    end
                end
            end
        end
    end

    if not found_op and best_op.chapter then
        local d = best_op.chapter.duration
        local typ = d <= STANDARD_MAX_DURATION + DURATION_TOLERANCE and "op" or "long_op"

        table.insert(ranges, {
            start = best_op.chapter.start,
            end_ = best_op.chapter.end_,
            type = typ
        })
    end

    if not found_ed and best_ed.chapter then
        local d = best_ed.chapter.duration
        local typ = d <= STANDARD_MAX_DURATION + DURATION_TOLERANCE and "ed" or "long_ed"

        table.insert(ranges, {
            start = best_ed.chapter.start,
            end_ = best_ed.chapter.end_,
            type = typ
        })
    end
end

-- TICK ENGINE
local function tick()
    if not pending then
        return
    end

    local base = base_type_of(pending.type)
    local is_enabled = base and ((base == "op" and config.skip_op) or (base == "ed" and config.skip_ed))

    if not is_enabled then
        clear_timer()
        pending = nil
        return
    end

    if is_long_type(pending.type) then
        if not (config.long_skip and range_duration(pending) <= config.max_duration + DURATION_TOLERANCE) then
            clear_timer()
            pending = nil
            return
        end
    end

    local pos = mp.get_property_number("time-pos", 0)
    local time_left = pending.skip_point - pos

    if time_left <= 0.05 then
        clear_timer()

        local signature = get_range_signature(pending)
        session_ignored[signature] = true

        mp.set_property_number("time-pos", pending.end_)

        local label = pending.display_type or get_display_type(pending.type)
        show_osd(OSD_PREFIX .. ass_color("✓ SKIPPED " .. label, ASS_WHITE), 2)

        pending = nil
        return
    end

    local color
    if instant_skip_applies(pending.type) or pending.late then
        color = "00FF00" -- steady green, no blinking for instant skip / late long activation
    else
        color = pos >= pending.start
            and (math.floor((mp.get_time() * 5) % 2) == 0 and "0000FF" or "FFFFFF")
            or "00FF00"
    end

    show_osd(
        OSD_PREFIX ..
        "{\\c&HFFFFFF&}Skipping in {\\c&H" .. color .. "&}" .. math.ceil(time_left),
        0.25
    )
end

-- AUTO SKIP HELPER
local function try_auto_skip(r, base, pos)
    local sig = get_range_signature(r)
    local timer = (base == "op") and config.op_timer or config.ed_timer

    if timer <= 0 then
        if pos >= r.start and pos < r.end_ then
            session_ignored[sig] = true
            mp.set_property_number("time-pos", r.end_)
            show_osd(OSD_PREFIX .. ass_color("✓ SKIPPED " .. base:upper(), ASS_WHITE), 2)
            return true
        end

        return false
    end

    local leadin = (base == "op") and config.op_leadin or config.ed_leadin
    local pre_chapter = math.max(0, timer - leadin)
    local trigger_start = math.max(0, r.start - pre_chapter)

    local skip_point
    if instant_skip_applies(base) then
        skip_point = r.start
    else
        skip_point = r.start + leadin
    end

    if pos >= trigger_start and pos < skip_point then
        pending = r
        pending.trigger_start = trigger_start
        pending.skip_point = skip_point
        pending.display_type = base:upper()
        pending.late = nil

        clear_timer()
        tick()
        active_timer = mp.add_periodic_timer(0.1, tick)
        return true
    elseif instant_skip_applies(base) and pos >= r.start and pos < r.end_ then
        session_ignored[sig] = true
        mp.set_property_number("time-pos", r.end_)
        show_osd(OSD_PREFIX .. ass_color("✓ SKIPPED " .. base:upper(), ASS_WHITE), 2)
        return true
    end

    return false
end

-- LIVE TIMELINE MONITOR
local function check(_, pos)
    if not pos then
        return
    end

    if config.allow_reskip then
        for _, r in ipairs(ranges) do
            local sig = get_range_signature(r)
            if session_ignored[sig] then
                if r.type == "manual_op" or r.type == "manual_ed" then
                    if pos < r.start - 0.5 then
                        session_ignored[sig] = nil
                    end
                elseif is_long_type(r.type) and not is_auto_eligible_range(r) then
                    if pos < r.start - 0.5 then
                        session_ignored[sig] = nil
                    end
                else
                    local base = base_type_of(r.type)
                    if base then
                        local timer = (base == "op") and config.op_timer or config.ed_timer
                        local leadin = (base == "op") and config.op_leadin or config.ed_leadin
                        local pre_chapter = math.max(0, timer - leadin)
                        local trigger_start = math.max(0, r.start - pre_chapter)

                        if pos < trigger_start - 0.5 then
                            session_ignored[sig] = nil
                        end
                    end
                end
            end
        end
    end

    if pending then
        if pos >= pending.end_ then
            clear_timer()
            pending = nil
            return
        end

        if is_long_type(pending.type) then
            if not (config.long_skip and range_duration(pending) <= config.max_duration + DURATION_TOLERANCE) then
                clear_timer()
                pending = nil
            end
        end

        return
    end

    for _, r in ipairs(ranges) do
        if r.type == "manual_op" or r.type == "manual_ed" then
            if pos >= r.start and pos < r.end_ then
                local enabled = (r.type == "manual_op" and config.skip_op)
                    or (r.type == "manual_ed" and config.skip_ed)
                local sig = get_range_signature(r)

                if enabled and not session_ignored[sig] and not manual_pending then
                    session_ignored[sig] = true
                    trigger_manual_prompt(r)
                    return
                end
            end
        else
            local base = base_type_of(r.type)
            if base then
                local enabled = (base == "op" and config.skip_op) or (base == "ed" and config.skip_ed)
                local sig = get_range_signature(r)

                if enabled and not session_ignored[sig] then
                    if is_long_type(r.type) then
                        if is_auto_eligible_range(r) then
                            if try_auto_skip(r, base, pos) then
                                return
                            end
                        else
                            if pos >= r.start and pos < r.end_ and not manual_pending then
                                session_ignored[sig] = true
                                trigger_manual_prompt(r)
                                return
                            end
                        end
                    else
                        if try_auto_skip(r, base, pos) then
                            return
                        end
                    end
                end
            end
        end
    end
end

-- ACTIONS & INTERRUPTS
local function on_seek()
    if manual_pending then
        clear_manual_prompt()
    end

    if not pending or not active_timer then
        return
    end

    clear_timer()

    local signature = get_range_signature(pending)
    session_ignored[signature] = true

    show_osd(OSD_PREFIX .. ass_color("[SKIP CANCELED BY SEEK]", ASS_GRAY), 2)

    pending = nil
end

local function on_pause(_, paused)
    if paused and manual_pending then
        clear_manual_prompt()
    end

    if not paused or not pending or not active_timer then
        return
    end

    clear_timer()

    local signature = get_range_signature(pending)
    session_ignored[signature] = true

    show_osd(OSD_PREFIX .. ass_color("[SKIP CANCELED]", ASS_GRAY), 2)

    pending = nil

    if config.cancel_auto_resume then
        mp.set_property_bool("pause", false)
    end
end

local function toggle_op()
    config.skip_op = not config.skip_op
    status("OP", config.skip_op)
end

local function toggle_ed()
    config.skip_ed = not config.skip_ed
    status("ED", config.skip_ed)
end

local function cycle_instant_skip()
    local states = { "off", "both", "op", "ed" }
    local current = type(config.instant_skip) == "string" and config.instant_skip:lower() or "off"
    local next_idx = 1

    for i, v in ipairs(states) do
        if v == current then
            next_idx = (i % #states) + 1
            break
        end
    end

    config.instant_skip = states[next_idx]

    -- Dynamically update pending countdown if one is actively running.
    if pending then
        local base = base_type_of(pending.type)
        if base == "op" or base == "ed" then
            local leadin = (base == "op") and config.op_leadin or config.ed_leadin
            local pos = mp.get_property_number("time-pos", 0)

            if instant_skip_applies(base) then
                pending.skip_point = pending.start
            else
                if pending.late then
                    pending.skip_point = math.min(pos + leadin, pending.end_)
                else
                    pending.skip_point = pending.start + leadin
                end
            end
        end
    end

    local val_upper = config.instant_skip:upper()
    local value_color = config.instant_skip == "off" and ASS_GRAY or ASS_AQUA

    local text = OSD_PREFIX
        .. ass_color("Instant Skip: ", ASS_WHITE)
        .. ass_color(val_upper, value_color)

    show_osd(text, 3)
end

-- LONG SKIP HELPERS / TOGGLE
local function maybe_activate_current_long_range(allow_clear_current_ignored)
    if pending then
        return
    end

    if not config.long_skip then
        return
    end

    local pos = mp.get_property_number("time-pos", 0)
    local r = nil

    for _, candidate in ipairs(ranges) do
        if is_long_type(candidate.type) and pos >= candidate.start and pos < candidate.end_ then
            r = candidate
            break
        end
    end

    if not r then
        return
    end

    local base = base_type_of(r.type)
    if not base then
        return
    end

    if not ((base == "op" and config.skip_op) or (base == "ed" and config.skip_ed)) then
        return
    end

    if range_duration(r) > config.max_duration + DURATION_TOLERANCE then
        return
    end

    local sig = get_range_signature(r)

    if session_ignored[sig] then
        if allow_clear_current_ignored then
            session_ignored[sig] = nil
        else
            return
        end
    end

    if manual_pending and manual_pending.start == r.start and manual_pending.end_ == r.end_ then
        clear_manual_prompt()
    end

    local leadin = (base == "op") and config.op_leadin or config.ed_leadin

    if instant_skip_applies(base) then
        session_ignored[sig] = true
        mp.set_property_number("time-pos", r.end_)
        show_osd(OSD_PREFIX .. ass_color("✓ SKIPPED " .. base:upper(), ASS_WHITE), 2)
        return
    end

    pending = r
    pending.trigger_start = pos
    pending.skip_point = math.min(pos + leadin, r.end_)
    pending.display_type = base:upper()
    pending.late = true

    clear_timer()
    tick()
    active_timer = mp.add_periodic_timer(0.1, tick)
end

local function toggle_long_skip()
    config.long_skip = not config.long_skip

    if not config.long_skip then
        if pending and is_long_type(pending.type) then
            clear_timer()
            pending = nil
        end
    end

    show_long_skip_osd()

    if config.long_skip then
        maybe_activate_current_long_range(true)
    end
end

local function adjust_max_duration(delta)
    config.max_duration = clamp_max_duration(config.max_duration + delta)
    show_max_duration_osd()

    if delta > 0 and config.long_skip then
        maybe_activate_current_long_range(false)
    end
end

-- RUNTIME INITIALIZATION
mp.register_event("playback-restart", scan_chapters)
mp.observe_property("time-pos", "number", check)
mp.observe_property("pause", "bool", on_pause)
mp.register_event("seek", on_seek)

mp.add_key_binding("alt+a", "toggle-op", toggle_op)
mp.add_key_binding("alt+s", "toggle-ed", toggle_ed)
mp.add_key_binding("alt+d", "cycle-instant", cycle_instant_skip)
mp.add_key_binding("ctrl+d", "toggle-long-skip", toggle_long_skip)

mp.add_key_binding("ctrl+right", "max-duration-increase", function()
    adjust_max_duration(0.5)
end, { repeatable = true })

mp.add_key_binding("ctrl+left", "max-duration-decrease", function()
    adjust_max_duration(-0.5)
end, { repeatable = true })
