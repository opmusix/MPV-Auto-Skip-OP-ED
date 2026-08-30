# mpv Auto Skip OP/ED

A smart and lightweight Lua script for [mpv](https://mpv.io/) that automatically detects and skips anime Openings (OP) and Endings (ED).

It primarily uses embedded chapter names, with a heuristic fallback for files where the chapters are unnamed or generic. Instead of instantly skipping, it gives you a short OSD countdown so you can cancel the skip if necessary.

---

## ✨ Features

* **Smart Chapter Detection** — Recognizes common names such as `OP`, `Opening`, `ED`, `Ending`, `NCOP`, `NCED`, etc.
* **Protected Chapters** — Avoids likely narrative sections such as `Prologue`, `Scene`, `Preview`, `Recap`, and others.
* **Heuristic Fallback** — Can estimate likely OP/ED chapters from their duration and position in the video when useful chapter names are unavailable.
* **Countdown Before Skipping** — Shows an OSD countdown before actually skipping.
* **Easy Cancel** — Press `Space` during the countdown to cancel the skip. By default, playback resumes automatically.
* **Seek to Cancel** — Seeking during the countdown also cancels the pending skip.
* **Smart Re-Arm** — Rewinding far enough can make a previously handled OP/ED eligible for skipping again.
* **Independent OP/ED Toggles** — Enable or disable OP and ED skipping separately.
* **Single-File Configuration** — Everything you normally need to configure is in one clearly marked section at the top of the script.

---

## 📥 Installation

Place `auto_skip.lua` in your mpv `scripts` directory.

* **Windows:** `%APPDATA%\mpv\scripts\`
* **Linux / macOS:** `~/.config/mpv/scripts/`

Then start or restart mpv.

---

## 🎮 Keybindings

| Key       | Action                            |
| :-------- | :-------------------------------- |
| `Alt + A` | Toggle OP skipping                |
| `Alt + S` | Toggle ED skipping                |
| `Space`   | Cancel the current skip countdown |
| Seek      | Cancel the current skip countdown |

`Alt + A` and `Alt + S` only change the setting for the current mpv session. They do not modify the configuration in the Lua file.

---

## ⚙️ Configuration

Open `auto_skip.lua` in a text editor.

**You only need to edit the `config` section at the very top of the file.**
Everything below it is part of the script itself and normally should not be changed.

```lua
local config = {
    -- Master Toggles
    skip_op = true,
    skip_ed = true,

    -- Behavioral Features
    cancel_auto_resume = true,
    allow_reskip = true,

    -- Timing Configurations (in seconds)
    op_timer = 5.0,
    ed_timer = 4.0,

    op_leadin = 2.0,
    ed_leadin = 2.0,

    -- Heuristic Fallback Bounds (in seconds)
    heuristic_min = 75.0,
    heuristic_max = 110.0
}
```

### Master Toggles

```lua
skip_op = true
skip_ed = true
```

These control whether OP and ED skipping is **enabled by default when mpv starts**.

* `true` = enabled
* `false` = disabled

You can still change them temporarily with `Alt+A` and `Alt+S`.

---

### `cancel_auto_resume`

```lua
cancel_auto_resume = true
```

Controls what happens when you press `Space` during a countdown.

* `true` — cancel the skip **and immediately resume playback**
* `false` — cancel the skip and remain paused

`true` is recommended if you want Space to act as a simple **"don't skip this"** button.

---

### `allow_reskip`

```lua
allow_reskip = true
```

Controls whether a previously handled OP/ED can be triggered again after rewinding.

* `true` — rewinding before the trigger point can re-arm the skip
* `false` — once handled, that section stays ignored for the session

---

## ⏱️ Countdown Settings

### `op_timer` / `ed_timer`

```lua
op_timer = 5.0
ed_timer = 4.0
```

These control the **total countdown duration** before an OP or ED is skipped.

For example:

```lua
op_timer = 8.0
```

gives you a longer warning before an OP is skipped.

---

### `op_leadin` / `ed_leadin`

```lua
op_leadin = 2.0
ed_leadin = 2.0
```

These control how much of the countdown continues **after the OP/ED chapter has actually started**.

For example, with:

```lua
op_timer = 5.0
op_leadin = 2.0
```

the countdown starts about **3 seconds before the OP**, continues for about **2 seconds into it**, and then skips.

### Easy way to think about it

```text
Timer = how long the whole warning lasts
Leadin = how much of that warning happens inside the OP/ED
```

So you generally only need to change these if you want the skip to happen earlier or later.

---

## 🔎 Heuristic Settings

### `heuristic_min` / `heuristic_max`

```lua
heuristic_min = 75.0
heuristic_max = 110.0
```

These define the chapter-duration range used when the script has to **guess** where an OP/ED is.

The default range of **75–110 seconds** is intended to cover the typical ~90-second anime OP/ED.

You normally should **leave these alone** unless you regularly use videos with unusually short or long OP/ED segments.

A wider range may find more candidates, but can also increase the chance of a false detection.

---

## 💡 Recommended Configuration

For most users, the defaults are a good starting point:

```lua
skip_op = true
skip_ed = true

cancel_auto_resume = true
allow_reskip = true

op_timer = 5.0
ed_timer = 4.0

op_leadin = 2.0
ed_leadin = 2.0

heuristic_min = 75.0
heuristic_max = 110.0
```

**In most cases, you only need to change `skip_op`, `skip_ed`, or the countdown settings.** The heuristic values are best left at their defaults unless you have a specific reason to adjust them.
