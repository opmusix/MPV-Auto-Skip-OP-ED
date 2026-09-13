***

# 🎬 mpv Auto Skip OP/ED

A smart, lightweight, and highly customizable Lua script for [mpv](https://mpv.io/) that automatically detects and skips anime Openings (OP) and Endings (ED).

Unlike basic chapter-skipping scripts, **Auto Skip OP/ED** features intelligent chapter clustering, context-aware keyword protection, a heuristic fallback engine for unnamed chapters, and live-adjustable thresholds.

---

## ✨ Key Features

*   **🧠 Smart Chapter Clustering:** Automatically merges consecutive or split chapters (e.g., `Opening 1` and `Opening 2`) into a single continuous skip range.
*   **🛡️ Context-Aware Protection:** Recognizes standard OP/ED tags while actively ignoring narrative sections like `Prologue`, `Recap`, `Preview`, `Scene`, and `Post-Credits`.
*   **🔮 Heuristic Fallback:** No chapter names? No problem. The script uses timeline positioning and duration scoring to accurately guess where the OP/ED is located.
*   **⚡ Instant Teleport Mode:** Skip the millisecond the OP/ED starts, or keep a smooth countdown—configurable independently for OP and ED.
*   **📏 Dynamic Long Skip:** Handle unusually long openings/endings on the fly. Adjust your maximum skip threshold in real-time without restarting mpv.
*   **🔄 Smart Re-Arming:** Rewind past a skipped section, and the script will intelligently "re-arm" it so you can watch it again.
*   **🎛️ Live OSD Controls:** Toggle modes and adjust timers via keyboard shortcuts with beautiful on-screen feedback.

---

## 📥 Installation

1. Download `auto_skip.lua`.
2. Place it in your mpv `scripts` directory:
   * **Windows:** `%APPDATA%\mpv\scripts\`
   * **Linux / macOS:** `~/.config/mpv/scripts/`
3. Start or restart mpv. The script will load automatically.

---

## 🎮 Controls & Keybindings

The script includes several hotkeys to manage behavior on the fly without editing the config file.

| Keybinding | Action |
| :--- | :--- |
| **`Alt` + `A`** | Toggle OP skipping ON/OFF |
| **`Alt` + `S`** | Toggle ED skipping ON/OFF |
| **`Alt` + `D`** | Cycle **Instant Skip** modes (`Off` ➔ `OP` ➔ `ED` ➔ `Both`) |
| **`Ctrl` + `D`** | Toggle **Long Skip** (Auto-skip recognized long chapters) |
| **`Ctrl` + `Right`** | Increase `max_duration` threshold by 0.5s |
| **`Ctrl` + `Left`** | Decrease `max_duration` threshold by 0.5s |
| **`Space`** | Cancel an automatic countdown **OR** confirm a manual long-skip prompt |
| **`Seek`** | Automatically cancels any pending skip countdown |

---

## ⚙️ Configuration

All user settings are located in the `config` table at the very top of `auto_skip.lua`. Open the file in any text editor to customize your experience.

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
    op_timer = 5.0,               -- Countdown for OP (Set to 0.0 for Instant Teleport)
    ed_timer = 4.0,               -- Countdown for ED
    op_leadin = 2.0,              -- Countdown time occurring *inside* the OP
    ed_leadin = 2.0,              -- Countdown time occurring *inside* the ED
    manual_prompt_timer = 5.0,    -- Duration for the "Skip? Press Space" prompt

    -- Thresholds
    max_duration = 100.0,         -- Max duration for "Long Skip" (Adjustable via Ctrl+Arrows)
    heuristic_min = 75.0          -- Minimum duration for fallback keyword-less detection
}
```

### 🧠 Understanding Standard vs. Long Skips
To prevent accidental skips of long narrative scenes that happen to be named "Opening", the script uses a two-tier system:

1.  **Standard Auto-Skip (≤ ~91s):** Any recognized OP/ED under the internal standard limit is automatically skipped using your `op_timer`/`ed_timer` countdowns.
2.  **Long Chapters (> ~91s):** If a recognized OP/ED is unusually long, it is flagged as a "Long" chapter.
    *   By default (`long_skip = false`), the script will **pause and prompt you**: `Skip? Press Space`.
    *   If you enable **Long Skip** (`Ctrl+D`), the script will auto-skip these longer chapters, *provided* they are under your dynamic `max_duration` (default `100.0`s).

### ⚡ Instant Skip Mode
Instead of setting timers to `0.0`, you can use the `instant_skip` variable.
*   `"off"`: Normal countdown behavior.
*   `"op"` / `"ed"` / `"both"`: The script will instantly teleport to the end of the chapter the exact millisecond it begins.

### ⏱️ Timers & Lead-in
*   **`op_timer` / `ed_timer`**: The total warning time before a skip occurs.
*   **`leadin`**: How much of that countdown happens *after* the OP/ED has already started.
    *   *Example:* `op_timer = 5.0` and `op_leadin = 2.0` means the countdown starts **3 seconds before** the OP begins, and finishes **2 seconds into** the OP.

---

## 🔬 Under the Hood: How It Works

### 1. Keyword Matching & Protection
The script scans embedded chapter titles. It looks for strict patterns (`OP`, `NCOP`, `Ending`, `エンディング`, etc.). Crucially, it checks against a **Protected List**. If a chapter is named `Prologue` or `Recap`, it is completely ignored, even if it contains the word "Opening".

### 2. Heuristic Scoring Engine
If a video lacks chapter names, the script falls back to math. It analyzes all unnamed chapters and assigns a "score" based on:
*   **Duration:** Penalizes chapters that are too short or too long (Target: ~90s).
*   **Timeline Position:** OPs are heavily favored if they occur around the **18%** mark of the video. EDs are favored around the **92%** mark.
The highest-scoring chapters are selected as the OP/ED.

---

## ❓ FAQ / Troubleshooting

**Q: An OP was detected, but it didn't auto-skip. Instead, it asked me to press Space. Why?**
**A:** The OP is likely longer than the internal standard limit (~91 seconds). The script is protecting you from skipping a massive chunk of the episode. You can either press `Space` to skip it manually, or press `Ctrl+D` to enable "Long Skip" mode for the rest of your session.

**Q: I want to watch the OP this time, but it keeps skipping!**
**A:** Press `Alt+A` (for OP) or `Alt+S` (for ED) to toggle skipping off for the current session. Alternatively, press `Space` during the countdown to cancel it.

**Q: The script skipped a recap or preview by mistake.**
**A:** The heuristic engine might have misidentified it. You can increase `heuristic_min` in the config to force the script to only look for longer chapters, or rely on properly named chapters if your media library supports them.

---

## 🤝 Contributing

Contributions, issue reports, and feature requests are highly appreciated!
If you find a false positive, have a keyword that should be added to the protected list, or want to improve the heuristic scoring algorithm, please open an Issue or Pull Request.

*Enjoy your uninterrupted anime marathons! 🍿*
