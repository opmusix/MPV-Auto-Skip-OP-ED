# 🎬 mpv Auto Skip OP/ED

A smart, lightweight, and highly customizable Lua script for [mpv](https://mpv.io/) that automatically detects and skips anime Openings (OP) and Endings (ED).

Unlike basic chapter-skipping scripts, **Auto Skip OP/ED** features intelligent chapter clustering, context-aware keyword protection, a heuristic fallback engine for unnamed chapters, and live-adjustable thresholds.

---

## ✨ Key Features

* 🧠 **Smart Chapter Clustering:** Automatically merges consecutive or split chapters (e.g. `Opening 1` and `Opening 2`) into a single continuous skip range.
* 🛡️ **Context-Aware Protection:** Recognizes standard OP/ED tags while actively ignoring narrative sections such as `Prologue`, `Recap`, `Preview`, `Scene`, and `Post-Credits`.
* 🔮 **Heuristic Fallback:** No chapter names? No problem. The script analyzes chapter duration and timeline position to estimate where the OP/ED is located.
* ⚡ **Instant Teleport Mode:** Skip the millisecond the OP/ED starts, or use a smooth countdown. OP and ED behavior can be configured independently.
* 📏 **Dynamic Long Skip:** Handle unusually long openings/endings on the fly. Adjust the maximum allowed duration without restarting mpv.
* 🔄 **Smart Re-Arming:** Rewind before a skipped section and the script can intelligently re-arm it so you can watch it again.
* 🎛️ **Live OSD Controls:** Toggle features and adjust thresholds directly from mpv using keyboard shortcuts.

---

# 📥 Installation

### 1. Install the script

Download `auto_skip.lua` and place it in your mpv `scripts` directory.

**Windows:**

```text
%APPDATA%\mpv\scripts\
```

**Linux / macOS:**

```text
~/.config/mpv/scripts/
```

Your resulting structure should look something like:

```text
mpv/
└── scripts/
    └── auto_skip.lua
```

Restart mpv after installing the script.

---

# ⌨️ Keybindings

> **Important:** The keybindings are not automatically registered by the Lua script.
>
> To use the session-wide controls, you must add the corresponding `script-binding` entries to your mpv `input.conf`.

## Add to `input.conf`

**Windows:**

```text
%APPDATA%\mpv\input.conf
```

**Linux / macOS:**

```text
~/.config/mpv/input.conf
```

Add:

```text
# AUTO SKIP KEYBINDS
ALT+a        script-binding auto_skip/toggle-op
ALT+s        script-binding auto_skip/toggle-ed
ALT+d        script-binding auto_skip/cycle-instant
CTRL+d       script-binding auto_skip/toggle-long-skip
CTRL+RIGHT   repeatable script-binding auto_skip/max-duration-increase
CTRL+LEFT    repeatable script-binding auto_skip/max-duration-decrease
```

Restart mpv after changing `input.conf`.

## Available Controls

| Keybinding       | Action                                                              |
| ---------------- | ------------------------------------------------------------------- |
| **Alt + A**      | Toggle OP skipping ON/OFF                                           |
| **Alt + S**      | Toggle ED skipping ON/OFF                                           |
| **Alt + D**      | Cycle Instant Skip mode: `Off → OP → ED → Both`                     |
| **Ctrl + D**     | Toggle Long Skip                                                    |
| **Ctrl + Right** | Increase `max_duration` by 0.5 seconds                              |
| **Ctrl + Left**  | Decrease `max_duration` by 0.5 seconds                              |
| **Space**        | Cancel an automatic countdown, or confirm a manual long-skip prompt |
| **Seek**         | Automatically cancel any pending skip countdown                     |

### Why is `input.conf` required?

`auto_skip.lua` exposes its controls as mpv **script bindings**. The Lua script can define what those bindings do, but mpv still needs to know which keys should trigger them.

For example:

```text
ALT+a script-binding auto_skip/toggle-op
```

means:

> When `Alt+A` is pressed, call the `toggle-op` function from `auto_skip.lua`.

Without these `input.conf` entries, the script can still perform its automatic OP/ED detection and skipping, but the **keyboard controls will not be available**.

---

# ⚙️ Configuration

All user-configurable settings are located in the `config` table near the top of `auto_skip.lua`.

```lua
local config = {
    -- Master Toggles
    skip_op = true,               -- Enable OP skipping by default
    skip_ed = true,               -- Enable ED skipping by default

    -- Behavioral Features
    instant_skip = "off",         -- "off", "op", "ed", "both"
    long_skip = false,            -- Auto-skip recognized long chapters up to max_duration
    cancel_auto_resume = true,    -- Pressing Space cancels auto-skip & resumes playback
    allow_reskip = true,          -- Rewinding before trigger re-arms skip

    -- Timing Configurations (in seconds)
    op_timer = 5.0,               -- Countdown for OP
    ed_timer = 4.0,               -- Countdown for ED
    op_leadin = 2.0,              -- Countdown time occurring inside the OP
    ed_leadin = 2.0,              -- Countdown time occurring inside the ED
    manual_prompt_timer = 5.0,    -- Duration for the "Skip? Press Space" prompt

    -- Thresholds
    max_duration = 100.0,          -- Max duration for "Long Skip"
    heuristic_min = 75.0           -- Minimum duration for heuristic detection
}
```

---

# 🧠 Standard vs. Long Skips

To prevent accidental skipping of unusually long narrative sections, the script uses a two-tier system.

### 1. Standard Auto-Skip

Recognized OP/ED chapters within the internal standard duration limit are automatically skipped using the configured OP/ED countdown.

For example:

```text
Opening — 89 seconds
```

is treated as a normal OP and can be automatically skipped.

### 2. Long Chapters

Recognized OP/ED chapters exceeding the internal standard limit are classified as **Long**.

By default:

```lua
long_skip = false
```

the script will pause and display a prompt such as:

```text
Skip? Press Space
```

You can then press **Space** to skip the chapter manually.

Alternatively, enable Long Skip with:

```text
Ctrl + D
```

When enabled, recognized long OP/ED chapters will be automatically skipped as long as they are within:

```lua
max_duration
```

---

# ⚡ Instant Skip Mode

You can instantly teleport to the end of a detected OP or ED instead of using the countdown.

The configuration option is:

```lua
instant_skip = "off"
```

Available values:

| Value    | Behavior                        |
| -------- | ------------------------------- |
| `"off"`  | Normal countdown behavior       |
| `"op"`   | Instantly skip OPs              |
| `"ed"`   | Instantly skip EDs              |
| `"both"` | Instantly skip both OPs and EDs |

You can also cycle through these modes during playback with:

```text
Alt + D
```

This allows you to change the behavior without editing the configuration file or restarting mpv.

---

# ⏱️ Timers & Lead-in

The OP and ED timers determine how long the warning countdown lasts.

```lua
op_timer = 5.0
ed_timer = 4.0
```

The `leadin` values determine how much of that countdown occurs **after the OP/ED has actually started**.

For example:

```lua
op_timer = 5.0
op_leadin = 2.0
```

means:

* Countdown begins **3 seconds before** the OP.
* The OP starts.
* Countdown continues for another **2 seconds**.
* The script skips to the end of the OP.

This allows the warning to appear slightly before the actual OP while still giving you a brief glimpse of the opening.

---

# 🧠 How Detection Works

The script uses multiple detection layers rather than relying on a single keyword.

## 1. Keyword Matching & Protection

The script scans embedded chapter titles for recognized OP/ED patterns, including names such as:

```text
OP
Opening
Opening 1
NCOP
OP1
ED
Ending
Ending 1
NCED
```

and relevant Japanese terminology.

At the same time, the script maintains a **protected context list**.

Chapters containing narrative-oriented names such as:

```text
Prologue
Recap
Preview
Scene
Post-Credits
```

are protected from being incorrectly classified as an OP/ED.

This helps prevent situations where a chapter happens to contain a keyword such as `Opening` but is actually part of the episode's story.

---

# 🧩 Smart Chapter Clustering

Some releases split an OP or ED across multiple consecutive chapters.

For example:

```text
00:00 - 00:03  Opening
00:03 - 01:28  Opening 1
01:28 - 01:30  Opening 2
```

Rather than treating these as separate skips, the script can combine adjacent matching sections into one continuous range.

This allows split or oddly structured chapter metadata to be handled as a single OP/ED.

---

# 🔮 Heuristic Fallback

Not every video has useful chapter names.

When chapter metadata is present but unnamed or otherwise insufficient, the script can fall back to heuristic detection.

The heuristic considers factors such as:

### Duration

OPs and EDs commonly fall within a particular duration range.

Very short or excessively long chapters receive lower scores.

The minimum duration considered by the fallback engine can be adjusted with:

```lua
heuristic_min = 75.0
```

### Timeline Position

The script also considers where a chapter occurs within the episode.

For example:

* OP candidates are favored around the **early portion** of the episode, roughly around the 18% mark.
* ED candidates are favored near the **end**, roughly around the 92% mark.

These are scoring preferences rather than fixed positions, allowing the script to adapt to episodes with different structures.

---

# 🔄 Smart Re-Arming

When an OP/ED is skipped, the script remembers that it has already handled that section.

If you rewind far enough before the trigger point, the section can be **re-armed**:

```lua
allow_reskip = true
```

This means you can rewind and watch the OP/ED again without having to restart the episode.

Set:

```lua
allow_reskip = false
```

if you do not want previously skipped sections to become eligible again.

---

# 🎛️ Live Controls

Several settings can be modified while mpv is playing.

### OP Skipping

```text
Alt + A
```

Toggles OP skipping.

### ED Skipping

```text
Alt + S
```

Toggles ED skipping.

### Instant Skip

```text
Alt + D
```

Cycles through:

```text
Off → OP → ED → Both → Off
```

### Long Skip

```text
Ctrl + D
```

Toggles automatic skipping of recognized long chapters.

### Maximum Duration

```text
Ctrl + Right
```

Increases:

```text
max_duration
```

by 0.5 seconds.

```text
Ctrl + Left
```

decreases it by 0.5 seconds.

These adjustments apply immediately and do not require restarting mpv.

---

# ❓ FAQ / Troubleshooting

### Q: The script loads, but Alt+A / Alt+S / Ctrl+D etc. do nothing.

**A:** Make sure you added the required `script-binding` entries to `input.conf`.

The Lua script does **not** automatically assign these keys.

Your `input.conf` should contain:

```text
ALT+a        script-binding auto_skip/toggle-op
ALT+s        script-binding auto_skip/toggle-ed
ALT+d        script-binding auto_skip/cycle-instant
CTRL+d       script-binding auto_skip/toggle-long-skip
CTRL+RIGHT   repeatable script-binding auto_skip/max-duration-increase
CTRL+LEFT    repeatable script-binding auto_skip/max-duration-decrease
```

After modifying `input.conf`, restart mpv.

---

### Q: Automatic OP/ED skipping works, but the keyboard controls don't.

**A:** This is expected if the `input.conf` bindings have not been added.

Automatic detection and keyboard control are separate:

```text
auto_skip.lua
      │
      ├── Automatic detection
      ├── Automatic skipping
      └── Script bindings
              │
              ▼
         input.conf
              │
              ▼
          Keyboard
```

The Lua script provides the functionality; `input.conf` assigns keys to it.

---

### Q: An OP was detected, but the script asked me to press Space instead of automatically skipping it.

**A:** The OP is probably longer than the internal standard limit and was therefore classified as a **Long Skip**.

By default:

```lua
long_skip = false
```

This is intentional protection against accidentally skipping a large section of an episode.

You can:

* Press **Space** to confirm the skip.
* Enable Long Skip with **Ctrl+D**.
* Increase `max_duration` if necessary.

---

### Q: I want to watch the OP this time, but it keeps skipping.

**A:** Press:

```text
Alt + A
```

to temporarily disable OP skipping.

For ED:

```text
Alt + S
```

You can also press **Space** during an active countdown to cancel the pending automatic skip.

---

### Q: The script skipped a recap or preview by mistake.

**A:** Heuristic detection is inherently less reliable than properly named chapter metadata.

Try increasing:

```lua
heuristic_min
```

so that the fallback engine considers only longer chapters.

If possible, releases with accurate chapter names are preferable because the keyword-based detector has more information to work with.

---

### Q: I changed `input.conf`, but the keybindings still don't work.

**A:** Make sure:

1. `auto_skip.lua` is actually loaded.
2. The binding names exactly match the functions exposed by the script.
3. The entries are in mpv's actual `input.conf`.
4. You restarted mpv after modifying the file.
5. Another mpv binding or application is not intercepting the key combination.

---

# 📁 File Locations

### Windows

```text
%APPDATA%\mpv\scripts\auto_skip.lua
%APPDATA%\mpv\input.conf
```

### Linux / macOS

```text
~/.config/mpv/scripts/auto_skip.lua
~/.config/mpv/input.conf
```

---

# 💬 Feedback & Contact

This project started as a personal tool, but reasonable suggestions, bug reports, and feature requests are welcome.

* **GitHub:** Open an Issue or Pull Request for bugs, improvements, or feature requests.
* **Discord:** `op.boyz`

Enjoy your uninterrupted anime marathons! 🍿
