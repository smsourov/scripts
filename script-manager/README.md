# The Code

- [x] Vibe coded

- [ ] Vibe coded and manually modified

- AI model
    
    - [ ] ChatGPT
    - [x] Claude
    - [ ] Gemini
    - [ ] Qwen
    - [ ] Deepseek

- [ ] Hand typed

- [x] Tested and verified

# About

A simple program to manage startup scripts in Windows OS.

# Script Manager (Rust + Iced)

Runs scripts at manager start (with optional delay) or at specific times, lives in the
system tray, and gives every script a Kill button.

## Build

```powershell
cargo run                # debug
cargo build --release    # target\release\script-manager.exe
```

## Usage

| Field | Example |
|---|---|
| Command | `py`, `pwsh`, `cmd`, `node` |
| Arguments | `-u "C:\scripts\job.py" --flag` (typed exactly like a terminal) |
| Start in | `C:\scripts` |

- For `.bat` files use command `cmd`, arguments `/c nothing.bat`.
- For PowerShell use `pwsh` (or `powershell`), arguments `-NoProfile -File "C:\x\a.ps1"`.
- For Python use `py -u script.py`; `-u` makes output appear in the log immediately.
- **Start with Windows** writes `HKCU\...\Run` -> `script-manager.exe --minimized`,
  so the manager starts hidden in the tray.
- Closing the window hides it to the tray. Use the tray menu (or the Quit button) to exit.
  Quitting kills all running scripts.
- Config: `%APPDATA%\ScriptManager\config.json`. Logs: `%APPDATA%\ScriptManager\logs\`.

## v0.2 notes

- Click an entry to view it read-only; **Edit** opens it for editing. Nothing is saved until
  you press **Save** (next to the Name field). Leaving a modified entry asks Save / Discard / Cancel.
- Card colour: green = runs at startup, red = does not. Darker shade = being edited.
- `Command (found / not found)` checks `<name>.exe` / `<name>.com` in every PATH directory.
- Right-click in an editable field -> Cut / Copy / Paste (native Windows popup; the field is
  focused and its text selected first).
- **Export** writes `Script-Manager_YYYY_MM_DD_HH_MM_SS.json`; **Import** appends entries
  (new ids, existing ones are never overwritten).
- Marker icons use *Segoe Fluent Icons* on Windows 11 and *Segoe MDL2 Assets* on Windows 10.

## v0.3 notes

- Only one manager runs at a time. Starting it again brings the running one to the front
  (a second copy started with `--minimized`, i.e. by autostart, just exits silently).
- The *Enabled* checkbox was removed. Scheduled times are active whenever the Times field has
  valid entries; clear the field to pause a schedule.
- **Stop all** kills every running script and cancels delayed starts that haven't fired yet.
- "Saved." now appears on the entry's card; other notices appear in the row beside *+ Add script*.
