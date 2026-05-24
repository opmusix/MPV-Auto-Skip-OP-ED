-- auto_skip_op_ed.lua
local mp = require('mp')
local utils = require('mp.utils')

-- CONFIGURATION
local config_file = mp.command_native({"expand-path", "~~/auto_skip_settings.json"})
local skip_op = true
local skip_ed = true

-- STATE
local ranges = {}
local ignored = {}
local active_timer = nil
local pending = nil
local time_left = 0

------------------------------------------------------------
-- PERSISTENCE
------------------------------------------------------------

local function load_settings()
    local f = io.open(config_file, "r")
    if f then
        local content = f:read("*all")
        f:close()
        local data = utils.parse_json(content)
        if data then
            if data.skip_op ~= nil then skip_op = data.skip_op end
            if data.skip_ed ~= nil then skip_ed = data.skip_ed end
        end
    end
end

local function save_settings()
    local data = {skip_op = skip_op, skip_ed = skip_ed}
    local f = io.open(config_file, "w")
    if f then
        f:write(utils.format_json(data))
        f:close()
    end
end

------------------------------------------------------------
-- UTIL
------------------------------------------------------------

local function is_op_range(start, duration, total)
    return start < total * 0.45 and duration >= 60 and duration <= 140
end

local function is_ed_range(start, duration, total)
    return start > total * 0.55 and duration >= 60 and duration <= 140
end

local function clear_timer()
    if active_timer then
        active_timer:kill()
        active_timer = nil
    end
end

------------------------------------------------------------
-- CHAPTER ANALYSIS
------------------------------------------------------------

local function scan()
    ranges = {}
    ignored = {}
    clear_timer()
    pending = nil

    local count = mp.get_property_number("chapter-list/count", 0)
    if count == 0 then return end

    local duration = mp.get_property_number("duration")
    if not duration then return end

    local chapters = {}
    local found_explicit_op = false
    local found_explicit_ed = false

    for i = 0, count - 1 do
        local start = mp.get_property_number("chapter-list/" .. i .. "/time")
        local title = (mp.get_property("chapter-list/" .. i .. "/title") or ""):lower()
        local next_start = (i == count - 1) and duration or mp.get_property_number("chapter-list/" .. (i + 1) .. "/time")
        
        table.insert(chapters, {
            start = start, end_ = next_start, title = title, duration = next_start - start
        })

        if title:find("op") or title:find("opening") then found_explicit_op = true end
        if title:find("ed") or title:find("ending") then found_explicit_ed = true end
    end

    for _, c in ipairs(chapters) do
        local t = c.title
        local explicit_op = t:find("op") or t:find("opening")
        local explicit_ed = t:find("ed") or t:find("ending")
        
        local is_protected = t:find("intro") or t:find("prologue") or t:find("part") or t:find("scene") or t:find("pv") or t:find("preview") or t:find("continued")

        if explicit_op then
            table.insert(ranges, {start=c.start, end_=c.end_, type="op"})
        elseif explicit_ed then
            table.insert(ranges, {start=c.start, end_=c.end_, type="ed"})
        elseif not is_protected then
            if not found_explicit_op and is_op_range(c.start, c.duration, duration) then
                table.insert(ranges, {start=c.start, end_=c.end_, type="op"})
            elseif not found_explicit_ed and is_ed_range(c.start, c.duration, duration) then
                table.insert(ranges, {start=c.start, end_=c.end_, type="ed"})
            end
        end
    end
end

------------------------------------------------------------
-- UI AND TIMER LOGIC
------------------------------------------------------------

local function get_color_transition(time_remaining)
    local r, g = 0, 0
    
    if time_remaining >= 2.0 then
        -- 3s down to 2s: Green to Yellow (Red ramps up, Green stays max)
        r = math.floor((3.0 - time_remaining) * 255)
        g = 255
    elseif time_remaining >= 1.0 then
        -- 2s down to 1s: Yellow to Red (Red stays max, Green ramps down)
        r = 255
        g = math.floor((time_remaining - 1.0) * 255)
    else
        -- 1s down to 0s: Locked on pure Red
        r = 255
        g = 0
    end
    
    -- ASS color format is BGR (Blue, Green, Red)
    return string.format("%02X%02X%02X", 0, g, r)
end

local function tick()
    time_left = time_left - 0.25
    local ass_start = mp.get_property("osd-ass-cc/0") or ""
    local ass_end = mp.get_property("osd-ass-cc/1") or ""

    if time_left > 0 then
        local hex_color = get_color_transition(time_left)
        local display_sec = math.ceil(time_left)

        mp.osd_message(
            ass_start .. "{\\an7\\fs12\\b1\\c&HFFFFFF&}Skipping in {\\c&H" .. hex_color .. "&}" .. display_sec .. ass_end,
            0.3
        )
        return
    end

    clear_timer()
    mp.set_property_number("time-pos", pending.end_)
    
    mp.osd_message(ass_start .. "{\\an7\\fs12\\b1\\c&HFFFFFF&}✓ SKIPPED " .. pending.type:upper() .. ass_end, 2)
    pending = nil
end

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
        if pos >= r.start and pos < r.end_ - 1.0 then
            local enabled = (r.type == "op" and skip_op) or (r.type == "ed" and skip_ed)

            if enabled and not ignored[tostring(r.start)] then
                pending = r
                time_left = 3.0
                
                local ass_start = mp.get_property("osd-ass-cc/0") or ""
                local ass_end = mp.get_property("osd-ass-cc/1") or ""
                
                mp.osd_message(ass_start .. "{\\an7\\fs12\\b1\\c&HFFFFFF&}Skipping in {\\c&H00FF00&}3" .. ass_end, 0.3)
                active_timer = mp.add_periodic_timer(0.25, tick)
                return
            end
        end
    end
end

------------------------------------------------------------
-- PAUSE CANCEL
------------------------------------------------------------

local function on_pause(_, paused)
    if paused and pending and active_timer then
        clear_timer()

        ignored[tostring(pending.start)] = true
        
        local ass_start = mp.get_property("osd-ass-cc/0") or ""
        local ass_end = mp.get_property("osd-ass-cc/1") or ""
        mp.osd_message(ass_start .. "{\\an7\\fs12\\b1\\c&H888888&}[SKIP CANCELLED]" .. ass_end, 2)

        pending = nil

        mp.add_timeout(0.5, function()
            mp.set_property_bool("pause", false)
        end)
    end
end

------------------------------------------------------------
-- TOGGLES
------------------------------------------------------------

local function status(name, val)
    local ass_start = mp.get_property("osd-ass-cc/0") or ""
    local ass_end = mp.get_property("osd-ass-cc/1") or ""
    
    if val then
        mp.osd_message(ass_start .. "{\\an7\\fs12\\b1\\c&HFFFFFF&}Skip " .. name .. ": {\\c&HFFFF00&}ON" .. ass_end, 4)
    else
        mp.osd_message(ass_start .. "{\\an7\\fs12\\b1\\c&H888888&}Skip " .. name .. ": OFF" .. ass_end, 4)
    end
end

local function toggle_op()
    skip_op = not skip_op
    save_settings()
    status("OP", skip_op)
end

local function toggle_ed()
    skip_ed = not skip_ed
    save_settings()
    status("ED", skip_ed)
end

------------------------------------------------------------
-- INITIALIZATION & EVENTS
------------------------------------------------------------

load_settings()

mp.register_event("file-loaded", scan)
mp.observe_property("time-pos", "number", check)
mp.observe_property("pause", "bool", on_pause)

mp.add_key_binding("alt+a", "toggle-op", toggle_op)
mp.add_key_binding("alt+s", "toggle-ed", toggle_ed)
