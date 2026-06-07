I copy/pasted to Gemini and said to write ReadMe. :)

# MPV Auto Skip OP/ED

A smart, heuristic-based Lua script for the [mpv media player](https://mpv.io/) that automatically detects and skips anime Openings (OP) and Endings (ED) with a visual on-screen countdown.

## ✨ Features

* **Smart Chapter Detection:** Uses advanced keyword pattern matching (English and Japanese) to identify strict OP/ED chapters, while ignoring protected chapters like "prologue", "preview", or "post-credits".
* **Heuristic Engine:** If chapters are unnamed or ambiguously named (e.g., "Intro"), the script uses a mathematical fallback based on the anime industry's ~90-second rule (75s to 110s) and timeline positioning to guess where the OP/ED is.
* **Visual OSD Countdown:** Displays a dynamic, color-changing, and blinking on-screen display (OSD) countdown before skipping.
* **On-the-Fly Skip Cancellation:** Want to watch the opening this time? Simply **pause** the video during the countdown. The script will cancel the skip for that specific OP/ED for the remainder of the viewing session.
* **Persistent Configuration:** Toggling settings via keybinds automatically saves your preferences to a JSON file, so your settings persist across mpv restarts.

## 📥 Installation

1. Download the `auto_skip.lua` (or whatever you named your main script file).
2. Place the script into your mpv `scripts` directory:
   * **Windows:** `%APPDATA%\mpv\scripts\`
   * **Linux:** `~/.config/mpv/scripts/`
   * **macOS:** `~/.config/mpv/scripts/`
3. Launch mpv. The script will automatically run and generate a default configuration file.

## 🎮 Keybindings & Usage

By default, the script automatically activates when playing a file with chapters. You can control its behavior live with the following actions:

| Keybind | Action | Description |
| :--- | :--- | :--- |
| `Alt + a` | Toggle OP Skip | Turns Opening skipping ON or OFF globally. |
| `Alt + s` | Toggle ED Skip | Turns Ending skipping ON or OFF globally. |
| `Space` *(Pause)* | Cancel Skip | Pausing during an active countdown will cancel the skip for that specific segment. |

*(Note: Toggling features with Alt+a/Alt+s will display an OSD confirmation and automatically save your choice to the config file).*

## ⚙️ Configuration

Upon first run, the script creates a configuration file at `~~/auto_skip_settings.json` (inside your main mpv folder). You can manually edit this file to fine-tune timers and behavior.

**Default `auto_skip_settings.json`:**
```json
{
  "skip_op": true,
  "skip_ed": true,
  "op_timer": 5.0,
  "ed_timer": 4.0,
  "op_leadin": 2.0,
  "ed_leadin": 1.0
}
```

### Parameter Breakdown:
* `skip_op` / `skip_ed`: Boolean (`true`/`false`). Master switches for skipping.
* `op_timer` / `ed_timer`: The total duration (in seconds) of the visual countdown before the skip executes. *(Clamped between 3.0 and 30.0 seconds).*
* `op_leadin` / `ed_leadin`: How many seconds *before* the actual chapter starts that the countdown should trigger.

## 🧠 How the Heuristic Engine Works

This script doesn't just blindly look for the word "OP". It uses a multi-layered approach:
1. **Strict Matching:** Looks for definitive terms (`op`, `ncop`, `オープニング`, etc.).
2. **Ambiguous Matching:** Looks for loose terms (`intro`, `credits`) but enforces a strict 75-110 second duration rule.
3. **Protected Words:** Ignores chapters that contain words like `preview`, `recap`, or `part` to prevent accidental skipping of actual episode content.
4. **Position & Duration Fallback:** If chapters exist but have zero useful names, it calculates a penalty score based on how close the chapter duration is to 90 seconds and where it sits in the video timeline (< 35% mark for OP, > 65% mark for ED).

---
*[Written by Gemini]*
