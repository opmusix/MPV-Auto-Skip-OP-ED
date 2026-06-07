I copy/pasted to Gemini and said to write ReadMe. :)



# mpv Auto Skip OP/ED

A smart, lightweight Lua script for the [mpv media player](https://mpv.io/) that automatically detects and skips anime Openings (OP) and Endings (ED) utilizing embedded `.mkv` chapter metadata and duration-based heuristics.

## ✨ Features

* **Precise Chapter Detection:** Reads hardcoded media chapter titles to identify Openings and Endings, while strictly ignoring protected story segments (e.g., "Prologue", "Preview", or "Post-Credits").
* **Heuristic Fallback Engine:** If a file contains unnamed or ambiguously named chapters, the script mathematically determines the OP/ED locations based on the anime industry's standard 90-second duration rule and timeline positioning.
* **Visual OSD Countdown:** Displays a dynamic, blinking On-Screen Display countdown before executing any skip.
* **On-the-Fly Cancellation:** Pause the video during an active countdown to instantly cancel the skip for that specific segment, allowing you to watch it uninterrupted.
* **Persistent Configuration:** Toggling master settings via keybinds will automatically save your preferences to a local JSON file for future sessions.

## 📥 Installation

1. Download the `auto_skip.lua` script.
2. Place the file into your mpv `scripts` directory:
   * **Windows:** `%APPDATA%\mpv\scripts\`
   * **Linux/macOS:** `~/.config/mpv/scripts/`
3. Launch mpv. The script will automatically generate a default configuration file upon its first execution.

## 🎮 Keybindings & Usage

The script runs automatically when playing media with chapters. You can control it live using the following default keybinds:

| Keybind | Action | Description |
| :--- | :--- | :--- |
| `Alt + a` | Toggle OP Skip | Turns Opening skipping ON or OFF globally. |
| `Alt + s` | Toggle ED Skip | Turns Ending skipping ON or OFF globally. |
| `Space` *(Pause)* | Cancel Skip | Pausing during an active countdown cancels the skip for that segment. |

*(Note: Toggling features with `Alt+a` or `Alt+s` displays an OSD confirmation and saves your choice to the config file).*

## ⚙️ Configuration

A configuration file is generated at `~~/auto_skip_settings.json` in your main mpv directory. You can edit this file to fine-tune the script's timing behavior:

```json
{
  "skip_op": true,
  "skip_ed": true,
  "op_timer": 5.0,
  "ed_timer": 4.0,
  "op_leadin": 2.0,
  "ed_leadin": 1.0
}
---
*[Written by Gemini]*
