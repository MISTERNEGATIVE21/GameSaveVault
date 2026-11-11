# Linux GameSaveVault (`gamevault.sh`) Design Specification

## 1. Overview & Goals

GameSaveVault is currently a Windows-first PowerShell application that discovers, backs up, and restores game saves across Windows installations. The goal of this project is to implement a Linux-native counterpart, `gamevault.sh`, providing:
1. **Linux Save Scanner**: Automated detection of game saves across Steam Proton prefixes (Native and Flatpak), native Linux games (`~/.local/share`, `~/.config`), Wine prefixes, Lutris, Heroic Games Launcher, Bottles, and console emulators.
2. **Selective Folder Scanning**: Interactive or CLI-specified custom folder selection, deep scanning for save signatures, and persistence in `config/scan-database.json`.
3. **Backup & Snapshot Engine**: Timestamped snapshots with JSON metadata, atomic file copying, and cross-platform interoperability with Windows GameSaveVault.
4. **Selective Restore with Rollback Protection**: Ability to choose specific games or folders to restore, with collision-prevention rollbacks and dry-run previews.
5. **Hybrid UI/TUI**: Auto-detecting interface that uses Zenity for graphical desktop dialogs, Whiptail for terminal ncurses menus, and an ANSI CLI fallback, alongside standard non-interactive CLI flags.
6. **Clean Repository Organization**: Reorganizing platform-specific scripts into `windows/` and `linux/` directories while maintaining convenient root launchers and backwards compatibility.

---

## 2. Directory Structure & Layout

To maintain clear separation between Windows and Linux implementations:

```
GameSaveVault/
├── gamevault.sh                 # Root executable shim calling linux/gamevault.sh
├── GameSaveVault.ps1            # Root shim calling windows/GameSaveVault.ps1 (backwards compat)
├── GameSaveVault-GUI.ps1        # Root shim calling windows/GameSaveVault-GUI.ps1
├── linux/                       # Linux implementation root
│   ├── gamevault.sh             # Main Linux CLI & GUI dispatcher
│   └── modules/
│       ├── common.sh            # Configuration loader, JSON utilities (jq / python3), path tools
│       ├── scanner.sh           # Save scanner (Proton, Flatpak, Wine, Native, Emulators, Custom)
│       ├── vault.sh             # Snapshots, restore, rollback, token translator
│       └── ui.sh                # Hybrid UI abstraction (Zenity, Whiptail, ANSI CLI)
├── windows/                     # Existing Windows PowerShell implementation
│   ├── GameSaveVault.ps1
│   ├── GameSaveVault-GUI.ps1
│   ├── Install-GameSaveVault.ps1
│   ├── Install.ps1
│   └── Register-ScheduledBackup.ps1
├── modules/                     # Windows PowerShell modules
│   ├── GSV.Core.psm1
│   └── GSV.Vault.psm1
├── config/                      # Shared configuration & databases
│   ├── settings.json
│   ├── settings.example.json
│   ├── scan-database.json
│   └── save-rules.example.json
├── data/                        # Shared catalog definitions & schemas
│   ├── catalog.psd1
│   ├── title-names.json
│   ├── scan-database.schema.json
│   └── save-rules.schema.json
└── tests/
    ├── test_linux_gamevault.sh  # Automated verification tests for Linux implementation
    └── ...                      # Existing PowerShell Pester tests
```

---

## 3. Linux Game Scanner & Folder Selection

### 3.1 Auto-Discovery Targets
The scanner checks standard Linux locations:
- **Steam Proton (Native)**:
  - Root: `~/.steam/steam/steamapps/compatdata/*/pfx/drive_c/` and `~/.local/share/Steam/steamapps/compatdata/*/pfx/drive_c/`
  - Subpaths:
    - `users/steamuser/AppData/Local/`
    - `users/steamuser/AppData/LocalLow/`
    - `users/steamuser/AppData/Roaming/`
    - `users/steamuser/Documents/My Games/`
    - `users/steamuser/Saved Games/`
  - Steam Userdata (Cloud sync): `~/.steam/steam/userdata/<account_id>/<app_id>/`
- **Steam Proton (Flatpak)**:
  - Root: `~/.var/app/com.valvesoftware.Steam/.steam/steam/steamapps/compatdata/*/pfx/drive_c/`
- **Native Linux Games**:
  - `~/.local/share/<GameName>/`
  - `~/.config/<GameName>/`
- **Lutris & Heroic**:
  - `~/Games/` (default Lutris prefix root)
  - `~/.config/heroic/Prefixes/`
  - `~/.var/app/com.heroicgameslauncher.hgl/...`
- **Bottles**:
  - `~/.var/app/com.usebottles.bottles/data/bottles/bottles/*/drive_c/users/*`
- **Wine Default Prefix**:
  - `~/.wine/drive_c/users/$USER/` or `$WINEPREFIX/drive_c/users/*`
- **Emulators**:
  - Ryujinx / Eden: `~/.config/Ryujinx/bis/user/save/`
  - RPCS3: `~/.config/rpcs3/dev_hdd0/home/00000001/savedata/`
  - PCSX2: `~/.config/PCSX2/memcards/`
  - Dolphin: `~/.local/share/dolphin-emu/GC/` and `~/.local/share/dolphin-emu/Wii/`
  - DuckStation: `~/.local/share/duckstation/memcards/`

### 3.2 Selective Folder Scanning & Deep Scanner
- Users can specify custom folders via:
  - GUI: Zenity directory chooser (supporting multi-selection or folder browsing).
  - TUI: Whiptail interactive path input / checklist of mounted locations.
  - CLI: `--dirs "/path/one:/path/two"` or `--target "/path"`.
- Deep scan searches recursively up to `MaxDepth` (default: 8) for save extensions (`.sav`, `.save`, `.dat`, `.bin`, `.sl2`, `savedata/`, `savegames/`).
- Discovered locations and custom roots are saved to `config/scan-database.json` matching the existing schema.

---

## 4. Vault, Snapshots, and Restore Engine

### 4.1 Vault Storage Location
- Detection order:
  1. CLI parameter `--vault <path>`
  2. Mounted external/secondary drive containing `GameSaveVault/` (`/run/media/$USER/*`, `/media/$USER/*`, `/mnt/*`)
  3. Path defined in `config/settings.json` (`BackupRoot`)
  4. Default: `~/GameSaveVault`

### 4.2 Snapshot Format & Metadata
- Snapshot folder: `<vault>/snapshots/<YYYY-MM-DD_HHMMSS>/`
- `manifest.json`:
  ```json
  {
    "CreatedAt": "2026-11-11T13:00:00Z",
    "Platform": "Linux",
    "Label": "manual-backup",
    "TotalGames": 5,
    "TotalFiles": 42,
    "TotalBytes": 104857600,
    "Entries": [
      {
        "Game": "Elden Ring",
        "Source": "SteamProton",
        "OriginalPath": "/home/user/.steam/steam/steamapps/compatdata/1245620/pfx/drive_c/users/steamuser/AppData/Roaming/EldenRing",
        "TokenPath": "%APPDATA%/EldenRing",
        "FileCount": 4,
        "Bytes": 15728640,
        "Files": ["data/Elden Ring/..."]
      }
    ]
  }
  ```
- File storage: Mirror copies saved under `<snapshot>/data/<Game>/...` preserving permissions.

### 4.3 Selective Restore & Rollback Protection
- **Selective Restore**:
  - Interactive checklist allows checking/unchecking individual games or folders.
  - CLI `--game "Game A,Game B"` or `--all`.
- **Collision Protection (Rollback)**:
  - Before writing into any existing destination directory, existing contents are moved to `<vault>/rollback/<timestamp>/<Game>/`.
  - Ensures no local data is destroyed if a restore is reverted.
- **Path Token Resolution**:
  - Resolves tokens like `%APPDATA%`, `%LOCALAPPDATA%`, `%DOCUMENTS%`, `%XDG_DATA_HOME%` to either matching Proton prefixes, local user directories, or a user-selected target root (`--restore-root <dir>`).
- **Dry Run**:
  - `--dry-run` displays complete source-to-destination copy plans without modifying filesystem state.

---

## 5. Hybrid UI / TUI Abstraction (`modules/linux/ui.sh`)

### 5.1 Environment Detection
- **Zenity GUI**: Triggered if `[ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]` and `command -v zenity >/dev/null`.
- **Whiptail TUI**: Triggered if running in an interactive terminal and `command -v whiptail >/dev/null` (or `dialog`).
- **ANSI CLI**: Fallback when no dialog tool is available.
- Overrides:
  - `--gui`: Forces Zenity GUI.
  - `--tui`: Forces Whiptail TUI.
  - `--cli` or subcommands: Direct CLI mode.

### 5.2 Interactive Screens
1. **Main Dashboard**:
   - Status: Active Vault path, detected games count, last snapshot date.
   - Menu actions:
     - 1. Scan Installed Games & Prefixes
     - 2. Scan Custom Folders (Add/Manage folders)
     - 3. Backup Saves (Interactive game checklist)
     - 4. Restore Saves (Snapshot picker -> Game checklist -> Dry-run / Restore)
     - 5. Browse Snapshots
     - 6. Configure Vault Location
     - 7. Run Health Check (Doctor)
     - 8. Exit

---

## 6. CLI Command Reference

`./gamevault.sh <command> [options]`

- `scan` - List detected games and their save folders.
- `scan-folders` - Interactively or via `--dirs` scan specific folders and update `scan-database.json`.
- `scan-db` - Display current scan database.
- `backup` - Create snapshot (`--all`, `--game "Names"`, `--dry-run`, `--vault <path>`).
- `restore` - Restore snapshot (`--snapshot latest|<id>`, `--game "Names"`, `--dry-run`, `--restore-root <path>`).
- `snapshots` - List existing snapshots and summary details.
- `gui` - Launch interactive GUI/TUI.
- `doctor` - Validate dependencies (`jq`, `rsync`, `zenity`, `whiptail`, write permissions).
- `help` - Show help and usage examples.

---

## 7. Error Handling & Validation
- **Dependencies**: Uses `jq` for robust JSON manipulation. If `jq` is absent, falls back to standard Python 3 `python3 -c "import json..."`.
- **Atomic File Handling**: Uses `rsync -a` or `cp -a` to preserve timestamps and file modes.
- **Logging**: All operations log to `<vault>/logs/gamevault.log` with timestamps and log levels (`INFO`, `WARN`, `ERROR`).
- **Disk Space**: Pre-flight check verifies available vault disk space before copying.

---

## 8. Verification & Testing Plan
- Test script: `tests/test_linux_gamevault.sh`
- Test suites:
  1. **CLI Argument Parser**: Validates help, invalid commands, flag parsing.
  2. **JSON Helper & Path Tokens**: Tests JSON read/write and token resolution (`%APPDATA%`, `%XDG_DATA_HOME%`).
  3. **Mock Scanner**: Creates mock Steam Proton prefix and mock native game folder; verifies scanner detects both.
  4. **Backup Snapshot**: Runs backup, asserts snapshot folder created, `manifest.json` matches schema, and files copied.
  5. **Rollback Protection**: Places conflicting file at restore destination, runs restore, verifies old file moved to `rollback/` and snapshot file restored.
  6. **Dry-Run Validation**: Confirms no files altered when `--dry-run` is active.
