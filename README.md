# mpv Auto Skip OP/ED

A smart and lightweight Lua script for [mpv](https://mpv.io/) that automatically detects and skips anime Openings (OP) and Endings (ED).

It primarily uses embedded chapter names, with a heuristic fallback for files where the chapters are unnamed or generic. Normally, detected OP/ED sections are skipped with an OSD countdown, while unusually long named sections require manual confirmation instead.

---

## ✨ Features

* **Smart Chapter Detection** — Recognizes common names such as `OP`, `Opening`, `ED`, `Ending`, `NCOP`, `NCED`, etc.
* **Protected Chapters** — Avoids likely narrative sections such as `Prologue`, `Scene`, `Preview`, `Recap`, and others.
* **Heuristic Fallback** — For files without useful OP/ED names, estimates likely sections using chapter duration and position in the video.
* **Countdown Before Skipping** — Shows an OSD countdown before automatically skipping an OP or ED.
* **Instant Skip Mode** — Set an OP/ED timer to `0.0` to skip the section immediately when playback enters it.
* **Long Chapter Protection** — Named OP/ED chapters longer than `max_auto_duration` are not automatically skipped. Instead, the script shows `Skip? Press Space` and waits for manual confirmation.
* **Easy Cancel** — Press `Space` during an automatic countdown to cancel the skip. By default, playback resumes immediately.
* **Seek to Cancel** — Seeking during an automatic countdown cancels the pending skip.
* **Smart Re-Arm** — Rewinding far enough can make a previously handled OP/ED eligible again.
* **Independent OP/ED Toggles** — Enable or disable OP and ED skipping separately.
* **Single-File Configuration** — All normal settings are kept in one clearly marked `config` section at the top of the script.

---

## 📥 Installation

Place `auto_skip.lua` in your mpv `scripts` directory.

* **Windows:** `%APPDATA%\mpv\scripts\`
* **Linux / macOS:** `~/.config/mpv/scripts/`

Then start or restart mpv.

---

## 🎮 Keybindings

| Key                             | Action                                |
| :------------------------------ | :------------------------------------ |
| `Alt + A`                       | Toggle OP skipping                    |
| `Alt + S`                       | Toggle ED skipping                    |
| `Space`                         | Cancel an automatic skip countdown    |
| `Space` *(long chapter prompt)* | Manually skip the detected long OP/ED |
| Seek                            | Cancel an automatic skip countdown    |

The `Alt + A` and `Alt + S` toggles apply only to the current mpv session.

---

## ⚙️ Configuration

Open `auto_skip.lua` in a text editor.

**You only need to edit the `config` section at the very top of the file.**
Everything below it is part of the script and normally should not be changed.

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

    -- Duration Limits
    max_auto_duration = 91.0,
    heuristic_min = 75.0,
    heuristic_max = 91.0
}
```

### Master Toggles

```lua
skip_op = true
skip_ed = true
```

Control whether OP and ED skipping are **enabled by default when mpv starts**.

* `true` = enabled
* `false` = disabled

You can also toggle them during playback with `Alt + A` and `Alt + S`.

---

### `cancel_auto_resume`

```lua
cancel_auto_resume = true
```

Controls what happens when you press `Space` during an automatic countdown.

* `true` — cancel the skip and immediately resume playback
* `false` — cancel the skip and remain paused

With `true`, Space effectively acts as a **"don't skip this"** button.

This setting does not affect the manual prompt used for long chapters.

---

### `allow_reskip`

```lua
allow_reskip = true
```

Controls whether a previously handled section can become eligible again after rewinding.

* `true` — rewinding far enough before the relevant trigger point can re-arm it
* `false` — handled sections remain ignored for the session

For long chapters, rewinding before the chapter starts can re-arm the manual prompt.

---

## ⏱️ Countdown Settings

### `op_timer` / `ed_timer`

```lua
op_timer = 5.0
ed_timer = 4.0
```

Control the total countdown duration for automatically skipped OPs and EDs.

For example:

```lua
op_timer = 8.0
```

gives you a longer warning before an OP is skipped.

### Instant Teleport Mode

Setting either timer to `0.0` or a negative value disables the countdown for that type:

```lua
op_timer = 0.0
```

The script will then skip the OP **immediately when playback enters the detected OP chapter**.

`op_leadin` is ignored in this mode.

This can be useful if you want one type to be skipped instantly while keeping a countdown for the other:

```lua
op_timer = 0.0
ed_timer = 4.0
```

---

### `op_leadin` / `ed_leadin`

```lua
op_leadin = 2.0
ed_leadin = 2.0
```

Control how much of the countdown happens **after the OP/ED chapter has started**.

For example:

```lua
op_timer = 5.0
op_leadin = 2.0
```

means the countdown starts about **3 seconds before the OP**, continues for about **2 seconds into it**, and then skips.

Think of it as:

```text
Timer  = total warning time
Leadin = portion of the warning that occurs inside the OP/ED
```

These settings only apply when the timer is greater than `0`.

---

## 📏 Duration Limits

### `max_auto_duration`

```lua
max_auto_duration = 91.0
```

Sets the **maximum chapter duration allowed for automatic skipping**.

When a chapter is explicitly recognized as an OP or ED but is longer than this value, the script does not automatically skip it.

Instead, when the chapter begins, it displays:

```text
Skip? Press Space
```

Press `Space` within the prompt's 3-second window to manually skip the chapter.

This provides extra protection against unusually long or potentially misidentified OP/ED chapters.

---

### `heuristic_min` / `heuristic_max`

```lua
heuristic_min = 75.0
heuristic_max = 91.0
```

Define the chapter-duration range used by the **heuristic fallback** when no suitable explicit OP/ED match is found.

The default range is **75–91 seconds**, covering the typical length of an anime OP/ED.

You normally should leave these at their defaults unless you regularly use files with unusually short or long OP/ED sections.

---

## 💡 How It Works

The script checks the video's embedded chapter information and looks for likely OP and ED sections.

* Clearly identified OP/ED chapters within the allowed duration are normally **automatically skipped** with a countdown.
* Named OP/ED chapters longer than `max_auto_duration` receive a **manual skip prompt** instead.
* When chapter names are missing or generic, the script uses **duration and timeline position** to estimate where the OP/ED is likely to be.
* Narrative-related chapter names are protected from automatic detection.
* Handled sections are remembered during the current session and can be re-armed by rewinding when `allow_reskip` is enabled.

---

## 🤝 Contributions

Contributions are appreciated!

Bug reports, suggestions, improvements, and pull requests are welcome. If you find a false detection or have an idea for making the script smarter or more reliable, feel free to share it.
