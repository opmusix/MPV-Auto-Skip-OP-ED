# mpv Auto Skip OP/ED

A smart and lightweight Lua script for [mpv](https://mpv.io/) that automatically detects and skips anime Openings (OP) and Endings (ED).

It primarily uses embedded chapter names, with a heuristic fallback for files where the chapters are unnamed or generic. Shorter detected OP/ED sections are automatically skipped with a countdown, while unusually long ones get a manual skip prompt instead.

---

## ✨ Features

* **Smart Chapter Detection** — Recognizes common names such as `OP`, `Opening`, `ED`, `Ending`, `NCOP`, `NCED`, etc.
* **Protected Chapters** — Avoids likely narrative sections such as `Prologue`, `Scene`, `Preview`, `Recap`, and others.
* **Heuristic Fallback** — For files without useful OP/ED names, the script estimates likely sections using chapter duration and position in the video.
* **Countdown Before Skipping** — Automatically detected OP/ED sections show an OSD countdown before being skipped.
* **Long Chapter Protection** — Named OP/ED chapters longer than the configured `max_auto_duration` are **not automatically skipped**. Instead, the script asks you:
  `Skip? Press Space`
* **Easy Cancel** — Press `Space` during the automatic countdown to cancel the skip. By default, playback resumes immediately.
* **Seek to Cancel** — Seeking during an automatic countdown cancels the pending skip.
* **Smart Re-Arm** — Rewinding far enough can make a previously handled OP/ED eligible for skipping again.
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

The `Alt + A` and `Alt + S` settings only apply to the current mpv session.

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

This setting does **not** affect the manual prompt used for long chapters.

---

### `allow_reskip`

```lua
allow_reskip = true
```

Controls whether a previously handled section can become eligible again after rewinding.

* `true` — rewinding far enough before the trigger can re-arm the skip
* `false` — handled sections remain ignored for the session

For long chapters using the manual prompt, rewinding before the chapter itself re-arms the prompt.

---

## ⏱️ Countdown Settings

### `op_timer` / `ed_timer`

```lua
op_timer = 5.0
ed_timer = 4.0
```

The total countdown duration for automatically skipped OPs and EDs.

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

Controls how much of the countdown happens **after the OP/ED chapter has started**.

For example:

```lua
op_timer = 5.0
op_leadin = 2.0
```

means the countdown begins about **3 seconds before the OP**, continues for about **2 seconds into it**, and then skips.

Think of it as:

```text
Timer  = total warning time
Leadin = portion of the warning that occurs inside the OP/ED
```

---

## 📏 Duration Limits

### `max_auto_duration`

```lua
max_auto_duration = 91.0
```

This is the **maximum duration allowed for automatic skipping**.

If a chapter is explicitly recognized as an OP or ED but is **longer than this value**, the script will not automatically skip it.

Instead, when the chapter starts, you get:

```text
Skip? Press Space
```

Pressing `Space` during this prompt manually skips the chapter.

This is useful for avoiding dangerous automatic skips when a release group has labeled an unusually long section as an OP/ED.

---

### `heuristic_min` / `heuristic_max`

```lua
heuristic_min = 75.0
heuristic_max = 91.0
```

These define the duration range considered by the **heuristic fallback** when the script is trying to identify an OP/ED without a suitable explicit match.

The default range is **75–91 seconds**.

`heuristic_max` is intentionally kept in sync with `max_auto_duration`.

You normally should leave these at their defaults unless you regularly use files with unusually short or long OP/ED sections.

---

## 💡 How It Works

The script checks the video's embedded chapter information and looks for likely OP and ED sections.

* Clearly identified and reasonably short OP/ED chapters can be **automatically skipped** after a countdown.
* Suspiciously long named OP/ED chapters are **not auto-skipped** and instead require a manual `Space` press.
* If chapter names are missing or generic, the script uses **duration and timeline position** to estimate where the OP/ED is likely to be.
* Narrative-related chapter names are protected from automatic detection.
* Once a section has been handled, it is remembered for the current session and can be re-armed by rewinding far enough when `allow_reskip` is enabled.

The goal is to make automatic skipping useful **without making it blindly destructive when chapter data looks suspicious**.


## 🤝 Contributions

Contributions are appreciated!

Bug reports, suggestions, improvements, and pull requests are welcome. If you find a false detection or have an idea for making the script smarter or more reliable, feel free to share it.
