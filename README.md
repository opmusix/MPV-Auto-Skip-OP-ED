# mpv Auto Skip OP/ED

A smart, feature-rich, and lightweight Lua script for [mpv](https://mpv.io/) that automatically detects and skips anime Openings (OP) and Endings (ED) using embedded chapter metadata and duration-based heuristic scoring.

---

## ✨ Key Features

- **Chapter Title Recognition:** Automatically matches standard anime chapter names (OP, ED, Opening, Ending, NCOP, NCED, etc.) while protecting narrative sections like *Prologue*, *Scene*, *Preview*, or *Recap*.
- **Heuristic Fallback Engine:** For files with unnamed or generic chapters, the script uses timeline positioning and duration-penalty scoring centered around the standard 90-second anime opening/ending mark (75s–110s) to detect OP/ED sections.
- **Visual OSD Countdown:** Shows a sleek On-Screen Display (OSD) countdown timer before skipping, featuring dynamic color switching and visual indicators.
- **Interrupt & Cancel Actions:**
  - **Pause to Cancel:** Pressing `Space` (Pause) during the countdown cancels the skip and automatically resumes playback immediately.
  - **Seek to Cancel:** Seeking forward or backward during the countdown safely cancels the pending skip for that section.
- **Smart Re-Arm (Re-skip):** If you cancel or complete a skip and rewind past the trigger threshold, the script re-arms itself so you can skip again if desired.
- **Persistent Toggle Settings:** Master toggles (`OP` and `ED`) are saved to `~~/auto_skip_settings.json` so your preferences persist across mpv restarts.

---

## 📥 Installation

1. Place `auto_skip.lua` into your mpv `scripts` directory:
   - **Windows:** `%APPDATA%\mpv\scripts\`
   - **Linux / macOS:** `~/.config/mpv/scripts/`
2. Launch mpv with any media file. The script will initialize automatically and create its configuration file on first launch.

---

## 🎮 Keybindings & Controls

| Keybinding | Action | Description |
| :--- | :--- | :--- |
| `Alt + a` | **Toggle OP Skip** | Enable or disable Opening skipping globally. |
| `Alt + s` | **Toggle ED Skip** | Enable or disable Ending skipping globally. |
| `Space` *(Pause)* | **Cancel & Resume** | Press during countdown to cancel skipping and resume video. |
| *(Any Seek)* | **Cancel Skip** | Seeking during the countdown aborts the current skip. |

---

## ⚙️ Configuration & Customization

### Settings JSON File
The script automatically generates a lightweight JSON configuration file at `~~/auto_skip_settings.json` to store your toggle states:

```json
{
  "skip_op": true,
  "skip_ed": true
}
```

### Script Internal Timings
Timing variables are maintained directly inside the `auto_skip.lua` file to prevent configuration overwrites. Open `auto_skip.lua` in any text editor to adjust the following variables at the top of the file:

```lua
-- Master behavioral settings
local cancel_auto_resume = true  -- Pressing Space cancels skip & resumes playback
local allow_reskip = true        -- Rewinding re-arms the skip trigger

-- Timing parameters (in seconds)
local op_timer  = 5.0            -- Total countdown duration for OP
local ed_timer  = 4.0            -- Total countdown duration for ED
local op_leadin = 2.0            -- Seconds inside chapter before skipping OP
local ed_leadin = 2.0            -- Seconds inside chapter before skipping ED
```

---

## 💡 How It Works

1. **Trigger Phase:** Before an OP/ED starts (calculated as `timer - leadin` seconds prior to chapter start), the script initiates a live countdown overlay.
2. **Execution Phase:** At `chapter_start + leadin`, if uninterrupted, the player jumps directly to the chapter end point and confirms with a `✓ SKIPPED` OSD message.
3. **Session Memory:** Each skipped segment is tracked during playback so it won't repeatedly trigger unless you rewind past the start line.
