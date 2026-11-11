# GameSaveVault

[**GitHub repository**](https://github.com/MISTERNEGATIVE21/GameSaveVault) · [Windows Install](#install-from-github) · [Linux Quick Start](#linux-quick-start--usage) · [Download ZIP](https://github.com/MISTERNEGATIVE21/GameSaveVault/archive/refs/heads/main.zip)

A cross-platform Windows & Linux app that finds your game save folders, copies them into a vault on another drive, and puts them back after you reinstall the OS or switch systems.

It works with **any games**, including normal Steam/Epic/GOG games, repack and crack games, and emulators. It does not download games, patch DRM, or touch game install files — it only copies save data, profiles and settings.

---

## Install from GitHub

**Repository:** https://github.com/MISTERNEGATIVE21/GameSaveVault

Click **[Code → Download ZIP](https://github.com/MISTERNEGATIVE21/GameSaveVault/archive/refs/heads/main.zip)**, or run this one-line PowerShell installer:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/MISTERNEGATIVE21/GameSaveVault/main/Install-GameSaveVault.ps1 | iex"
```

It downloads the latest `main` into `%LOCALAPPDATA%\GameSaveVault`, then creates the desktop and Start-menu shortcuts.

To include the optional daily backup task, run:

```powershell
$s = irm 'https://raw.githubusercontent.com/MISTERNEGATIVE21/GameSaveVault/main/Install-GameSaveVault.ps1'
& ([scriptblock]::Create($s)) -ScheduledTask -Time 21:30
```

Requirements: Windows 10/11 and Windows PowerShell 5.1 (built in). No admin rights are needed.

---

## The exact scenario you described

You reinstall Windows **on top of C:**. Windows moves the old install to `C:\Windows.old`, and you log into a fresh profile. Your saves were in:

```
C:\Users\<you>\Documents\My Games\...
C:\Users\<you>\AppData\Local\...
C:\Users\<you>\AppData\LocalLow\...
C:\Users\<you>\Saved Games\...
```

After the reinstall those paths belong to the new profile, so the games look empty.

There are two ways to get them back:

### Plan A (recommended): back up to another drive **before** reinstalling

```powershell
cd "$env:LOCALAPPDATA\GameSaveVault"
powershell -ExecutionPolicy Bypass -File .\GameSaveVault.ps1 roots
powershell -ExecutionPolicy Bypass -File .\GameSaveVault.ps1 scan-folders -Directory "D:\Games;C:\PS5GAMES"
powershell -ExecutionPolicy Bypass -File .\GameSaveVault.ps1 backup -All
```

The vault defaults to the first non-system drive (here: `G:\GameSaveVault`). Keep it on `D:`, `E:`, `G:` or an external USB drive — **not on C:**.

After the new Windows is installed and the games are reinstalled:

```powershell
powershell -ExecutionPolicy Bypass -File .\GameSaveVault.ps1 restore -Snapshot latest -DryRun
powershell -ExecutionPolicy Bypass -File .\GameSaveVault.ps1 restore -Snapshot latest
```

If you moved the saves as one portable database file instead, use:

```powershell
powershell -ExecutionPolicy Bypass -File .\GameSaveVault.ps1 restore-db -File D:\GameSaveVault.gsvdb
```

`-DryRun` only prints what would happen. The real restore copies the saves back into the current profile. If a save already exists, it is moved to `G:\GameSaveVault\rollback\<timestamp>\` first, so nothing is lost.

### Plan B: recover from `C:\Windows.old`

If you forgot to back up, the old profile is still inside `C:\Windows.old` — but Windows deletes that folder automatically after about **10 days**.

```powershell
powershell -ExecutionPolicy Bypass -File .\GameSaveVault.ps1 from-old -DryRun
powershell -ExecutionPolicy Bypass -File .\GameSaveVault.ps1 from-old
```

What it does:

1. Finds every `Windows.old\Users\*` profile (and its `Documents`, `AppData`, `Saved Games`, `OneDrive\Documents`).
2. Scans the catalog + safe game roots + Steam userdata + emulator and crack folders.
3. Copies everything into a normal vault snapshot.
4. Restores that snapshot into the current profile.

Use `-WindowsOldRoot "D:\Windows.old"` if the old install is on another drive.

---

<a id="quick-start-windows"></a>
## Quick start (Windows)

Requirements: Windows 10/11, Windows PowerShell 5.1 (built in). No admin rights for normal use.

```powershell
cd "$env:LOCALAPPDATA\GameSaveVault"

# 1. list the drives / folders you can choose from (nothing is scanned yet)
powershell -ExecutionPolicy Bypass -File .\GameSaveVault.ps1 roots

# 2. scan ONLY the folders you choose, and store the results in the database
powershell -ExecutionPolicy Bypass -File .\GameSaveVault.ps1 scan-folders -Directory "D:\Games;C:\PS5GAMES"

# 3. see what was stored (loads the database, does not scan again)
powershell -ExecutionPolicy Bypass -File .\GameSaveVault.ps1 scan-db

# 4. back everything up
powershell -ExecutionPolicy Bypass -File .\GameSaveVault.ps1 backup -All

# 5. list snapshots
powershell -ExecutionPolicy Bypass -File .\GameSaveVault.ps1 snapshots
```

`scan` (the old catalog scan) is still available, but the normal flow is now
**choose folders → scan them → store the results**. The GUI does the same thing
with checkboxes.

### GUI

```powershell
powershell -ExecutionPolicy Bypass -File .\GameSaveVault-GUI.ps1
```

Or run `Install.ps1` once to create a desktop / Start-menu shortcut:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install.ps1
```

The first time you open the GUI it does **not** scan. It lists the drives and common game/save folders it can see, and you tick the ones you want. GameSaveVault then scans only those folders and their subfolders and stores the results in `config\scan-database.json`. On later starts it loads that database instantly. Use **Scan folders…** to change the selection and **Rescan** to refresh the same folders.

The GUI shows every stored game with a checkbox, the save folders it found, and buttons for **Scan folders…**, **Rescan**, **Backup selected**, **Backup all**, **Restore…**, **Restore file…**, **Export DB…**, **Windows.old…**, **Deep scan…**, **Migrate…**, **Add game…**, **Save rules…**, **Open vault**, **Backup location…** and **Doctor**. Double-click a row to open its save folder.

**Export DB…** writes one portable `.gsvdb` file that contains the save files plus the scan database. Copy that single file to another PC, click **Restore file…** there, and the saves are restored into that PC's profile (or a folder you choose).

#### First run: choose folders, then scan

Nothing is scanned automatically. The first-run window lists:

- every ready drive (`C:\`, `D:\`, …)
- common game folders (`Games`, `SteamLibrary`, `GOG Games`, `PS5GAMES`, …)
- launcher libraries (Steam, Epic, GOG, EA, Ubisoft, …)
- save roots (`Documents`, `Saved Games`, `LocalLow`, `Public Documents`, …)

Tick what you want and click **Scan selected**. The scan walks those folders and
their subfolders, then writes the findings to `config\scan-database.json`:

```json
{
  "Version": 1,
  "Roots": [ { "Path": "D:\\Games", "LocationCount": 42 } ],
  "Locations": [
    {
      "GameName": "Example Game",
      "Token": "DOCUMENTS",
      "RelativePath": "Example Game\\Saves",
      "ResolvedPath": "D:\\Games\\Example Game\\Saves",
      "Kind": "Directory"
    }
  ]
}
```

The database is a normal JSON file. You can copy it to another PC and import it
with **Restore file…** (or `restore-db -File ...`). A plain JSON database only
lists *where* saves belong; the portable `.gsvdb` file below also carries the
save contents.

#### Restore on another PC from one database file

1. On the old PC, click **Export DB…** (or run `export-db`). This creates one
   `GameSaveVault-<date>.gsvdb` file containing the snapshot payload and the scan
   database. It is a zip archive with a friendly extension.
2. Copy that file to the new PC with a USB stick, network share or cloud drive.
3. On the new PC, install GameSaveVault, click **Restore file…**, and select the
   `.gsvdb` file. Choose `profile` (new Windows user), `verbatim` (old absolute
   layout) or `folder` (one folder).
4. The embedded scan database is imported automatically, so the game list is
   ready on the new PC as well.

Existing saves are moved to `vault\rollback\<timestamp>` before anything is
overwritten, exactly like a normal restore.

#### Choosing where backups are stored

Click **Backup location…** to pick the folder that receives new snapshots:

- You can type a path, use **Browse…**, or pick a drive from the list (each is shown with free space, and the system drive `C:` is flagged with a warning).
- Tick **Move existing snapshots** to copy everything from the old folder into the new one.
- The choice is saved to `config\settings.json`, so the GUI **and** the CLI use it from now on.

```powershell
# same thing from the command line
.\GameSaveVault.ps1 backup -All -BackupRoot D:\MyBackups
```

Optional daily backup:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install.ps1 -ScheduledTask -Time 21:30
```

---

<a id="linux-quick-start--usage"></a>
## Linux Quick Start & Usage

GameSaveVault includes native, full-featured Linux support via `./gamevault.sh`. It automatically discovers games running under Steam Proton (Native & Flatpak), Wine, Lutris, Heroic Games Launcher, Bottles, console emulators, and native Linux games.

### Quick Start

Ensure `gamevault.sh` is executable and run:

```bash
chmod +x gamevault.sh

# 1. Launch the interactive dashboard (auto-detects Zenity GUI or Whiptail TUI)
./gamevault.sh
# or explicitly:
./gamevault.sh gui

# 2. Or run CLI workflows directly:
./gamevault.sh scan              # Discover installed game saves & update scan database
./gamevault.sh backup            # Snapshot all discovered saves into the vault
./gamevault.sh snapshots         # List existing snapshots
./gamevault.sh restore --dry-run # Preview restoring latest snapshot
./gamevault.sh restore           # Restore saves with automatic rollback protection
```

**Requirements:**
- Standard Linux `bash` shell (Ubuntu, Debian, Fedora, Arch Linux, SteamOS, openSUSE, etc.).
- Optional GUI/TUI utilities: `zenity` (for desktop dialogs) or `whiptail` / `dialog` (for terminal menus).
- Optional JSON utility: `jq` (falls back to built-in `python3` automatically if `jq` is absent).

---

### Hybrid UI / TUI Architecture

GameSaveVault automatically detects your environment and presents the best user interface available:

1. **Zenity GUI (Desktop)**: When running inside a graphical desktop session (GNOME, KDE Plasma, XFCE, Cinnamon, Hyprland, etc. with `$DISPLAY` or `$WAYLAND_DISPLAY`), GameSaveVault opens native desktop dialogs, folder browsers, and checklists using `zenity`.
2. **Whiptail TUI (Terminal)**: When running in a terminal session without a graphical desktop (such as an SSH connection, text console, or headless server), GameSaveVault automatically uses `whiptail` (or `dialog`) for fast ncurses-based terminal dialogs.
3. **CLI Fallback**: If neither `zenity` nor `whiptail` is installed, GameSaveVault provides a clean, colored ANSI text menu and interactive command-line prompts.

You can explicitly force an interface mode using CLI flags or the `GSV_UI_MODE` environment variable:

```bash
./gamevault.sh --gui    # Force Zenity graphical interface
./gamevault.sh --tui    # Force Whiptail / dialog terminal interface
./gamevault.sh --cli    # Force plain text CLI prompt interface

# Or set via environment variable:
export GSV_UI_MODE=gui  # options: "gui", "tui", "cli"
```

---

### Linux CLI Commands

| Command | Usage | Description |
|---|---|---|
| `scan` | `./gamevault.sh scan` | Automatically discovers game saves across Proton, Wine, Flatpak, Native, and Emulators, displays a formatted table, and records them in `config/scan-database.json`. |
| `scan-folders` | `./gamevault.sh scan-folders --dirs <p1:p2>` | Deep scans custom folders for save files (`.sav`, `.dat`, `.sl2`, `savedata/`, etc.) and stores results in the database. In interactive mode without `--dirs`, opens a folder picker. |
| `scan-db` | `./gamevault.sh scan-db` | Displays the current contents of `config/scan-database.json` without re-scanning disk. |
| `backup` | `./gamevault.sh backup [options]` | Creates a timestamped snapshot of saves in the vault. |
| `restore` | `./gamevault.sh restore [options]` | Restores game saves from a snapshot. Conflicting existing files are preserved in `vault/rollback/<timestamp>/`. |
| `snapshots` | `./gamevault.sh snapshots [--json]` | Lists all snapshots in the vault with timestamp, label, size, file count, and errors. |
| `doctor` | `./gamevault.sh doctor` | Checks required tools (`jq`, `python3`, `tar`), optional UI tools (`zenity`, `whiptail`), vault storage path, and permissions. |
| `gui` | `./gamevault.sh gui` | Launches the interactive graphical or terminal dashboard. |

#### Command Flags & Options

```bash
# Backup examples:
./gamevault.sh backup                                   # Back up all games in scan database
./gamevault.sh backup --game "Skyrim,Palworld"          # Back up only specific games (comma-separated)
./gamevault.sh backup --label "before-modding"          # Custom label in snapshot name
./gamevault.sh backup --dry-run                         # Preview files that would be backed up
./gamevault.sh backup --vault "/mnt/storage/GameVault"  # Override vault destination folder

# Restore examples:
./gamevault.sh restore                                  # Restore all games from the latest snapshot
./gamevault.sh restore --snapshot "20261111-120000"     # Restore from a specific snapshot ID
./gamevault.sh restore --game "Skyrim"                  # Selectively restore only specific games
./gamevault.sh restore --dry-run                        # Preview actions without modifying any files
./gamevault.sh restore --restore-root "/tmp/test"       # Restore files into an alternate directory
./gamevault.sh restore --vault "/mnt/storage/GameVault" # Override vault location

# Snapshots examples:
./gamevault.sh snapshots                                # View table of all snapshots
./gamevault.sh snapshots --json                         # Machine-readable JSON output
./gamevault.sh snapshots --vault "/custom/vault"        # Inspect custom vault location
```

---

### Folder Selection & Selective Restore

#### Custom Folder Selection & Deep Scanning
When games are installed in custom drives or folders (e.g. `/mnt/Games`, `/opt/games`, or portable drives):

- **CLI Directory Specification**: Use `--dirs` with colon, semicolon, or comma-separated paths:
  ```bash
  ./gamevault.sh scan-folders --dirs "/mnt/Games:/home/user/CustomSaves"
  ```
- **GUI / TUI Folder Browser**: Run `./gamevault.sh scan-folders` without arguments, or choose **Scan Custom Folders...** in the interactive dashboard. A directory chooser dialog will open allowing you to select any directory.
- **Deep Scan Heuristics**: The scanner traverses folders recursively up to depth 8 searching for known save markers (`.sav`, `.save`, `.dat`, `.bin`, `.sl2`, `savedata/`, `savegames/`), groups them by parent folder, and adds them to `config/scan-database.json`.

#### Selective Restore with Collision Rollback
- **Select Specific Games**: Restore only the titles you need using `--game "<name>"`:
  ```bash
  ./gamevault.sh restore --game "Cyberpunk 2077,Elden Ring"
  ```
- **Rollback Safety**: If any target save folder or file already exists, GameSaveVault automatically archives the current version to `vault/rollback/<timestamp>/` before restoring. Your existing saves are never deleted or corrupted.
- **Dry-Run Preview**: Add `--dry-run` to inspect every copy and rollback step before applying changes:
  ```bash
  ./gamevault.sh restore --game "Skyrim" --dry-run
  ```

---

### Supported Linux Platforms & Save Locations

GameSaveVault on Linux scans standard paths across gaming runtimes and emulators:

1. **Steam Proton (Native & Flatpak)**:
   - Native Steam: `~/.steam/steam/steamapps/compatdata/<appid>/pfx/drive_c/` and `~/.local/share/Steam/steamapps/compatdata/...`
   - Flatpak Steam: `~/.var/app/com.valvesoftware.Steam/.steam/steam/steamapps/compatdata/<appid>/pfx/drive_c/`
   - Scanned paths inside Proton prefixes:
     - `users/steamuser/AppData/Local/`
     - `users/steamuser/AppData/LocalLow/`
     - `users/steamuser/AppData/Roaming/`
     - `users/steamuser/Documents/My Games/` and `users/steamuser/Documents/`
     - `users/steamuser/Saved Games/`
   - Steam Userdata Cloud Saves: `~/.steam/steam/userdata/<account_id>/<app_id>/`
   - Steam App IDs are mapped to game names using `data/title-names.json` and Steam manifests.

2. **Native Linux Games**:
   - `~/.local/share/<GameName>/`
   - `~/.config/<GameName>/`

3. **Wine, Lutris, Heroic & Bottles**:
   - Wine Default Prefix: `~/.wine/drive_c/users/$USER/`
   - Lutris Prefixes: `~/Games/`
   - Heroic Games Launcher: `~/.config/heroic/Prefixes/` and Flatpak `~/.var/app/com.heroicgameslauncher.hgl/`
   - Bottles: `~/.var/app/com.usebottles.bottles/data/bottles/bottles/*/drive_c/users/*`

4. **Console Emulators**:
   - **Ryujinx / Eden (Nintendo Switch)**: `~/.config/Ryujinx/bis/user/save/`
   - **RPCS3 (PlayStation 3)**: `~/.config/rpcs3/dev_hdd0/home/00000001/savedata/`
   - **PCSX2 (PlayStation 2)**: `~/.config/PCSX2/memcards/`
   - **Dolphin (GameCube & Wii)**: `~/.local/share/dolphin-emu/GC/` and `~/.local/share/dolphin-emu/Wii/`
   - **DuckStation (PlayStation 1)**: `~/.local/share/duckstation/memcards/`

---

### Cross-Platform Compatibility (Windows & Linux)

GameSaveVault provides full interoperability between Windows and Linux systems:

- **Unified Snapshot Format**: Snapshots produced on Windows (`GameSaveVault.ps1`) and Linux (`gamevault.sh`) share the identical `manifest.json` schema and `payload/0001/...` structure. A vault snapshot created on Windows can be restored directly on Linux, and vice-versa.
- **Portable Path Tokens**: Snapshots record locations using platform-independent tokens (`%DOCUMENTS%`, `%APPDATA%`, `%LOCALAPPDATA%`, `%LOCALLOW%`, `%SAVEDGAMES%`, `%USERPROFILE%`, `%STEAMUSERDATA%`). When restoring on Linux, GameSaveVault automatically translates these tokens into the active Proton prefix, Wine prefix, or native Linux directory.
- **Shared Configuration**: Both operating systems read and update `config/settings.json` and `config/scan-database.json`.
- **Safe Migration**: Migrate saves seamlessly from a Windows gaming desktop to a Linux laptop, Steam Deck, or Bazzite/ChimeraOS handheld by copying the vault directory.

---

<a id="commands"></a>
## Windows Commands (PowerShell)

| Command | What it does |
|---|---|
| `scan` | Detect installed games and the save folders found (default). `-Detailed` prints every path. |
| `roots` | List the drives / folders available for selection. Nothing is scanned. |
| `scan-folders` | Scan **only** the chosen folders and store the results in `config\scan-database.json`. `-Directory "D:\Games;C:\PS5GAMES"`, `-Drive D:`, `-AllDrives`, `-MaxDepth`, `-MaxResults`, `-NoSize`. |
| `scan-db` | Show the stored scan database without scanning. |
| `export-db` | Write one portable `.gsvdb` file (snapshot payload + scan database). `-File <path>`, `-Snapshot <name>`. |
| `restore-db` | Restore saves on another PC from a `.gsvdb` file. `-File <path>`, `-RestoreFormat`, `-RestoreRoot`, `-Game`, `-DryRun`. |
| `deep-scan` | Search a whole drive for save folders the normal scan may miss (aliases: `deepscan`, `deep`, `search`). `-Drive C:`, `-AllDrives`, `-MaxDepth 12`, `-MaxResults 500`, `-NoSize`, `-Backup`. |
| `migrate` | Copy console-emulator saves between emulators: `-From <source> -To <target>`, `-Title <id>`, `-DryRun`. |
| `backup` | Snapshot saves into the vault. With no `-Game` filter it uses the stored scan database (and falls back to the catalog when the database is empty). `-All` also includes launcher-wide/emulator folders. `-Game Skyrim,Palworld` limits it. |
| `restore` | Restore the latest or a named snapshot. `-DryRun`, `-Game`, `-KeepExisting`, `-SkipRegistry`. |
| `from-old` | Import + restore saves from `C:\Windows.old`. `-DryRun`, `-NoRestore`, `-WindowsOldRoot`. |
| `snapshots` | List snapshots with date, size, file count and errors. |
| `stats` | Vault size and free space. |
| `add` | Register a custom game and save path(s). |
| `rules` | List the portable save rules in `config\save-rules.json`. |
| `rule-add` | Add / update a save rule: `-Paths`, `-SavePattern`, `-Alias`, `-InstallDir`, `-Mode`. |
| `rule-remove` | Remove a rule by name or id. |
| `rule-import` / `rule-export` | Move rules between machines as JSON (`-File rules.json`). |
| `discover` | Find the games and saves described by the rules on **this** PC (`-Backup` snapshots them). |
| `prune` | Delete old snapshots (`-Keep <n>`). |
| `doctor` | Check vault location, write access, Windows.old, catalog and game detection. |
| `gui` | Launch the graphical app. |

Common switches:

```powershell
-BackupRoot D:\GameSaveVault     # override vault for one run
-Game "Skyrim","Palworld"        # filter by substring or fuzzy name
-DryRun / -WhatIf                # show only, change nothing
-Hash                            # store SHA256 per file (slower)
-SkipRegistry                    # do not import .reg settings
-KeepExisting                    # never overwrite a save that exists
-NoGlobal                        # skip launcher-wide / crack / emulator folders
-Keep 8                          # how many snapshots to keep
-Drive C: -AllDrives             # scan-folders / deep-scan: which drive(s) to search
-Directory "D:\Games;C:\PS5GAMES"  # scan-folders / deep-scan: specific folders
-MaxDepth 12 -MaxResults 500     # scan-folders / deep-scan: folder depth and hit limit
-NoSize                         # scan-folders / deep-scan: skip file counting (much faster)
-Backup                         # deep-scan / discover: snapshot everything found
-From / -To <emu>               # migrate only: source and target emulator
-Title <id>                     # migrate only: one title id
-RestoreFormat profile|verbatim|folder   # restore / restore-db layout (default: profile)
-RestoreRoot <folder>           # folder format: <folder>\<TOKEN>\<relative path>
-SavePattern *.sav,*.dat        # rule-add: which files are saves
-InstallDir "My Game"           # rule-add: install folder name(s) used to find the game
-Mode auto|token|gamedir|absolute        # rule-add: restore strategy
-Alias "Alternative name"       # rule-add: extra name for game matching
-File rules.json                # rule-import / rule-export (JSON rules)
-File D:\GameSaveVault.gsvdb    # export-db / restore-db (portable database)
```

Examples:

```powershell
# list folders you can choose from (nothing is scanned)
.\GameSaveVault.ps1 roots

# scan only two game folders and store the results
.\GameSaveVault.ps1 scan-folders -Directory "D:\Games;C:\PS5GAMES"

# scan every fixed drive and store the results
.\GameSaveVault.ps1 scan-folders -AllDrives -MaxDepth 12

# show the stored database without scanning again
.\GameSaveVault.ps1 scan-db

# export one portable database file, then restore it on another PC
.\GameSaveVault.ps1 export-db -File D:\GameSaveVault.gsvdb
.\GameSaveVault.ps1 restore-db -File D:\GameSaveVault.gsvdb -RestoreFormat profile

# search the whole C: drive for save folders (crack, Steam-emulator, UWP, LocalLow)
.\GameSaveVault.ps1 deep-scan -Drive C: -NoSize

# same, then back everything up into G:\GameSaveVault
.\GameSaveVault.ps1 deep-scan -AllDrives -MaxDepth 12 -Backup

# copy console-emulator saves between emulators (matches by title id, remaps
# the profile id, and moves any overwritten save to the vault rollback folder)
.\GameSaveVault.ps1 migrate -From <source> -To <target>
.\GameSaveVault.ps1 migrate -From <source> -To <target> -Title <title-id> -DryRun

# back up only two games
.\GameSaveVault.ps1 backup -Game "Skyrim","Palworld"

# preview a restore of the newest snapshot
.\GameSaveVault.ps1 restore -Snapshot latest -DryRun

# restore only one game from a specific snapshot
.\GameSaveVault.ps1 restore -Snapshot 20261104-032636_selftest -Game "Expeditions"

# register a save folder the scanner did not find
.\GameSaveVault.ps1 add "My Game" -Paths "%DOCUMENTS%\MyGame\Saves","%LOCALAPPDATA%\MyGame"

# registry-stored settings too
.\GameSaveVault.ps1 add "My Game" -Paths "%DOCUMENTS%\MyGame" -Registry "HKCU\Software\MyGame"

# save rules: portable paths that survive a new drive letter / new Windows user
.\GameSaveVault.ps1 rule-add "My Game" -Paths "D:\Games\My Game\Saves" -SavePattern *.sav -InstallDir "My Game"
.\GameSaveVault.ps1 rule-add "My Game" -Paths "%LOCALAPPDATA%\MyGame\Saved","%APPDATA%\GameEmu\1234" -SavePattern *.sav,*.dat
.\GameSaveVault.ps1 discover -Backup
.\GameSaveVault.ps1 rule-export -File D:\rules.json

# restore layouts: new profile (default), original absolute layout, or one folder
.\GameSaveVault.ps1 restore -Snapshot latest -RestoreFormat verbatim
.\GameSaveVault.ps1 restore -Snapshot latest -RestoreFormat folder -RestoreRoot D:\RestoredSaves
```

---

## Where PC games actually keep saves

This is the map the scanner uses. Repacks do **not** move saves — a repack is just a compressed installer of the original game files, so the game still writes to its normal folders.

| Location | Typical games / engines |
|---|---|
| `%USERPROFILE%\Documents\My Games\<Game>` | Bethesda (Skyrim, Fallout), Far Cry, Company of Heroes, Farming Simulator |
| `%USERPROFILE%\Documents\<Game>` | Rockstar (GTA V, RDR2), CDPR (Witcher 3), Horizon, Spider-Man, Ghost of Tsushima |
| `%USERPROFILE%\Saved Games\<Game>` | Cyberpunk 2077, God of War, Hades, Kingdom Come |
| `%APPDATA%\<Game>` (Roaming) | Elden Ring, Dark Souls III, Sekiro, Stardew Valley, Factorio, Cuphead |
| `%LOCALAPPDATA%\<Game>` | Tekken 8, Palworld, Satisfactory, Hogwarts Legacy, Unreal Engine saves |
| `%LOCALAPPDATA%Low\<Company>\<Game>` | Unity games: Valheim, RimWorld, Hollow Knight, Subnautica, Cities: Skylines II |
| `%PUBLIC%\Documents\<...>` | shared / all-users saves |
| `%PROGRAMDATA%\<...>` | machine-wide saves and some emulators |
| Steam `userdata\<account>\<appid>\remote` | Monster Hunter, Resident Evil, DMC5, many Steam Cloud games |
| Inside the game folder (`Save`, `Saves`, `SaveData`, `Profile`, `Profiles`) | older games and some cracks |
| Registry (`HKCU\Software\<Game>`) | a few games store keybinds/profile there |

### Repack, crack and Steam-emulator games

- Repack names and tags are ignored when matching, so `Expeditions A MudRunner Game [Repack]` still matches the real game.
- Saves stay in the original game's paths — `Documents\My Games\...`, `AppData\...`, etc.
- If the release ships a Steam emulator, saves can instead be in one of the usual emulator save folders under `%APPDATA%`, `%LOCALAPPDATA%` or `%PROGRAMDATA%`, keyed by AppID.
- Crack / scene releases often keep saves in a shared folder such as `%PUBLICDOCS%\Steam\<group>\<appid>`, `%PROGRAMDATA%\Steam\<group>\<appid>`, or `Documents\<group>_SAVES\<appid>`.
- Older cracks put saves inside the install folder (`Profile`, `SaveData`, `Saves`), which the scanner also checks.
- Not every game has a catalog entry — that is exactly what `deep-scan` is for. It walks the drive and reports every folder that looks like a save location, including console-emulator save trees, UWP/Xbox `Packages\...\SystemAppData\wgs` containers, and Unity `LocalLow\<company>\<product>` folders.

#### Jump Force example

Jump Force stores its story save in a shared crack/scene folder:

```
C:\Users\Public\Documents\Steam\<group>\816020\remote\jfsavedata.dat
```

The `deep-scan` found it and backed it up (AppId `816020`). The game also has a catalog entry for its normal per-user, Steam userdata and emulator/crack folders, so normal `scan`/`backup` will find the save as soon as any of those folders exist.

### Console emulator saves and migration

Big console emulators keep saves **outside** the game folder, keyed by a *title ID* instead of a game name. The scanner enumerates every title, so `scan` lists them under **Console emulator saves**, and `backup` includes them.

| Emulator family | Console | Save roots (relative to the emulator data folder) |
|---|---|---|
| Switch emulators | Nintendo Switch | `nand\user\save\<profile>\<titleID>` / `nand\system\save\<profile>\<titleID>` or `bis\user\save\<profile>\<titleID>` / `bis\system\save\<profile>\<titleID>` (title ID = 16 hex digits) |
| 3DS emulators | Nintendo 3DS | `sdmc\Nintendo 3DS\<id0>\<id1>\title\<title-high>\<title-low>` (title ID = 16 hex digits, split into two 8-hex folder names) |
| PSP emulators | PlayStation Portable | `PSP\SAVEDATA\<gameID>` or `memstick\PSP\SAVEDATA\<gameID>` |
| PS3 emulators | PlayStation 3 | `dev_hdd0\home\<user>\savedata\<titleID>` |
| PS Vita emulators | PlayStation Vita | `ux0\user\<user>\savedata\<titleID>` |
| Xbox 360 emulators | Xbox 360 | `content\<profile>\<titleID>` (title ID = 8 hex digits) |
| Wii U emulators | Wii U | `mlc01\usr\save\<titleID>` |
| Wii emulators | Wii | `Wii\titles\<gameID>` |
| PlayStation 5 emulators | PlayStation 5 | `_SaveData\PPSA…` **next to the emulator exe** (portable — the install folder can be called anything) |
| PlayStation 4 emulators | PlayStation 4 | `user\<profile>\savedata\<CUSA…>` |

Emulators that use one shared memory card, battery save or save-state folder (PS1/PS2, DS, GBA and multi-system retro emulators) are backed up as shared save folders instead of per-title folders. They are listed under the emulator's name and restored like any other save.

Data folders are probed in `%APPDATA%\<emulator>`, `%LOCALAPPDATA%\<emulator>` and `%DOCUMENTS%\<emulator>` when that is where the emulator keeps them, plus a shallow walk of every drive for portable installs (a folder that contains `dev_hdd0\home`, `ux0\user`, `mlc01\usr`, `PSP\SAVEDATA`, `memstick\PSP\SAVEDATA`, `Wii\titles`, `content\0000000000000000`, `user\nand\user\save`, `user\sdmc\Nintendo 3DS`, `portable\bis\user\save`, a `User` folder or a `_SaveData` folder — Recycle Bins, caches and system folders are skipped).

#### Migrating saves between emulators

Saves are stored the way the game wrote them, so moving between emulators for the **same console** is a folder copy matched by title ID. The profile ID is remapped to the destination's own, and any save that would be overwritten is moved to `vault\rollback\<timestamp>\` first.

```powershell
# see what would happen first
.\GameSaveVault.ps1 migrate -From <source> -To <target> -DryRun

# copy everything, or just one title
.\GameSaveVault.ps1 migrate -From <source> -To <target>
.\GameSaveVault.ps1 migrate -From <source> -To <target> -Title <title-id>
```

Notes:

- The destination emulator must be installed and must have launched once (its save folder has to exist).
- Console **game files are never copied** — only save data. Shader caches are skipped; you can re-download/recompile them.
- Portable emulators that live on another drive are restored to the **same drive path**, because there is no per-user token to anchor them to. AppData-based emulators restore into the *new* Windows profile, like every other save.
- The GUI has a **Migrate…** button with From/To dropdowns and a per-title checkbox list.

The app backs up **all** of the emulator/crack roots above as "Global launcher / emulator saves" even when it cannot identify which game they belong to.

### Denuvo and other DRM

Denuvo is anti-tamper DRM, **not** a save system. It does not store your progress; the game still writes saves to the normal paths above. Two practical notes:

- Denuvo activation is tied to hardware. After a Windows reinstall or hardware change the game may need to reactivate (publishers limit activations per day). Backing up saves does not back up or bypass that licence.
- A few games keep profile/settings in the registry. The catalog includes known registry keys, and `add -Registry` lets you add your own.

### What is **not** backed up

- Game installation files (only save data, profiles, configs).
- Online-only progress (MMO characters, GTA Online, Diablo IV seasonal data, etc.).
- Steam Cloud-only data that never exists locally.
- Denuvo licences / account entitlements.

---

## How discovery works

The app does not scan the whole PC on startup. On first run it lists the drives
and common game/save folders it can see; you tick the ones to search. Those
folders and their subfolders are walked once, and every save location found is
stored in `config\scan-database.json`. Later starts load that database without
scanning. **Scan folders…** changes the selection, **Rescan** refreshes it, and
**Deep scan…** searches a whole drive without touching the selection.

The database stores the same location objects used by backup/restore, so the
list, checkboxes and backup buttons work exactly as before. It also records the
path tokens (`%DOCUMENTS%`, `%APPDATA%`, `%GAMEDIR%`, …) needed to restore on a
different Windows user or drive letter.

For every installed game the tool combines:

1. **Steam** — reads `libraryfolders.vdf` + `appmanifest_*.acf` from every library.
2. **Epic** — reads the Epic manifest `.item` files.
3. **GOG** — reads the GOG registry entries.
4. **Folder scan** — looks in `GameScanRoots` (defaults: `D:\Games`, Epic folder, Steam `steamapps\common`, common GOG/Ubisoft/EA paths) and detects real game folders by `.exe`/engine markers.
5. **Catalog** — 96 curated games with exact save paths, matched by Steam AppID, name and aliases.
6. **Heuristics** — for unknown games it checks:
   - `Documents\My Games\<name>`, `Documents\<name>`, `Saved Games\<name>`, `AppData\<name>`, `LocalAppData\<name>`
   - `LocalLow\<company>\<product>` (Unity)
   - `Save`/`Saves`/`SaveData`/`Profile`/`Profiles` inside the install folder
   - Steam userdata for the game's AppID
   - common Steam-emulator and crack save folders
7. **Save rules** — your own entries from `config\save-rules.json` (see below). A rule can add paths the catalog does not know, and it carries the restore strategy.
8. **Name matching** strips repack tags, version numbers and edition words, then compares word tokens (so `Skyrim Special Edition` matches `The Elder Scrolls V: Skyrim Special Edition`).

If a game is missing, add its folder to `GameScanRoots` in `config\settings.json`, or register the save path directly with `add`.

---

## Save rules (portable save locations)

The catalog covers popular games, but repacks, obscure titles and cracks often keep saves somewhere else. A **save rule** is a small JSON record that tells the tool:

- **where** the game keeps saves (as `%TOKEN%` patterns, not hard-coded `C:\Users\<old user>\...`),
- **how** to find the game again on a new PC (`installDirNames`),
- **what** save files / folders look like (`filePatterns`, `folderPatterns`) so it can search the install folder when the exact path changed,
- **how** to restore the files (`token`, `gamedir`, `absolute`, `auto`).

Rules live in `config\save-rules.json`. The format is documented by [`data/save-rules.schema.json`](data/save-rules.schema.json), and a couple of ready-made examples are in `config\save-rules.example.json` (they are copied into your DB on first use).

### Path tokens

| Token | Expands to |
|---|---|
| `%USERPROFILE%` | the current Windows profile |
| `%APPDATA%` / `%LOCALAPPDATA%` / `%LOCALLOW%` | Roaming / Local / LocalLow |
| `%DOCUMENTS%` / `%SAVEDGAMES%` | Documents (including OneDrive redirection) / Saved Games |
| `%PUBLIC%` / `%PUBLICDOCS%` / `%PROGRAMDATA%` | shared machine folders |
| `%STEAMUSERDATA%` | the Steam `userdata` folder (account id is remapped on restore) |
| `%GAMEDIR%` | the game install folder discovered on **this** machine |

Wildcards `*` and `?` are allowed, so `%APPDATA%\IO Interactive\Epic\*` matches a per-account subfolder.

### Restore modes

| Mode | What restore does |
|---|---|
| `token` | Expands the token in the **new** profile, so saves follow the new Windows user. |
| `gamedir` | Finds the game install on the new PC (Steam library, `GameScanRoots`, `D:\Games`, repack folders, shallow drive walk) and writes the save **next to the game**. |
| `absolute` | Writes to the original absolute path (useful for portable emulators on another drive). |
| `auto` | `token` when the path sits under a known folder, `gamedir` when it sits inside the install. |

If a `gamedir` rule cannot find the game, restore falls back to the token view instead of failing.

### CLI

```powershell
# add a rule from an absolute path: it is converted to %GAMEDIR% or %TOKEN%
.\GameSaveVault.ps1 rule-add "My Game" -Paths "D:\Games\My Game\Saves" -SavePattern *.sav -InstallDir "My Game"

# token paths and emulator/crack folders are kept as written
.\GameSaveVault.ps1 rule-add "My Game" -Paths "%LOCALAPPDATA%\MyGame\Saved","%APPDATA%\GameEmu\1234" -SavePattern *.sav,*.dat

# see what each rule finds on this PC (and optionally snapshot it)
.\GameSaveVault.ps1 discover
.\GameSaveVault.ps1 discover -Backup

# share rules with another machine
.\GameSaveVault.ps1 rule-export -File D:\rules.json
.\GameSaveVault.ps1 rule-import -File D:\rules.json
.\GameSaveVault.ps1 rules
```

### GUI

**Save rules…** opens the rules manager. From there you can add/edit/remove rules, pick save folders with a folder browser or type a pattern, choose the restore mode, run **Discover now**, and import/export JSON. **Add game…** opens the same editor, so a manually added game is a portable rule rather than a one-off path.

### Example rule

```json
{
  "id": "rule-my-game",
  "name": "My Game",
  "aliases": ["MyGame"],
  "steamAppIds": ["1234567"],
  "installDirNames": ["My Game", "MyGame"],
  "filePatterns": ["*.sav", "*.dat"],
  "folderPatterns": ["*save*", "SaveGames"],
  "discover": true,
  "paths": [
    { "pattern": "%LOCALAPPDATA%\\My Game\\Saved\\SaveGames", "mode": "token" },
    { "pattern": "%GAMEDIR%\\Saves", "mode": "gamedir" }
  ]
}
```

On a fresh Windows install, `%LOCALAPPDATA%` becomes the new user's folder, and `%GAMEDIR%` is resolved by looking for the game again. Snapshots record `RuleId`, `RestoreMode`, `InstallDirNames` and `FilePatterns`, so the restore decision does not depend on the old machine.

---

## Vault layout

```
G:\GameSaveVault\
  snapshots\
    20261104-032636_selftest\
      manifest.json          # games, paths, file list, sizes, errors
      payload\0001\...       # copied save files
      payload\0002\...
  rollback\
    20261105-101500\...      # saves that were overwritten during a restore
  logs\
    gsv-20261104.log
```

`manifest.json` stores each save location as a **token + relative path** (for example `DOCUMENTS\My Games\Skyrim Special Edition`), not as a hard-coded `C:\Users\oldname\...`. That is what lets the same snapshot restore into a different Windows user or a new profile.

### Safety

- Restore never deletes silently: existing targets are moved to `rollback\<timestamp>\`.
- `-DryRun` lists every action without writing.
- `-KeepExisting` skips anything already present.
- Snapshot pruning only removes whole old snapshot folders, never the newest ones.

---

## Configuration

`config\settings.json` is created on first run:

```json
{
  "BackupRoot": "G:\\GameSaveVault",
  "GameScanRoots": ["D:\\Games", "C:\\Program Files\\Epic Games"],
  "ExtraPaths": [],
  "ExcludeNames": ["cache", "ShaderCache", "CrashReports", "logs"],
  "ExcludeFiles": ["*.log", "*.tmp", "*.dmp"],
  "HashFiles": false,
  "KeepSnapshots": 8,
  "RegistryExport": true
}
```

- `BackupRoot` — where snapshots live. **Put it on a non-C: drive.**
- `GameScanRoots` — extra folders that contain game installs.
- `ExtraPaths` — extra save paths always included in every backup (tokens allowed).
- `ExcludeNames` / `ExcludeFiles` — skipped during copy (caches, logs, crash dumps).
- `KeepSnapshots` — automatic pruning count.
- `HashFiles` — set `true` for SHA256 per file (slower, better integrity checks).

Custom games live in `config\games.custom.json` and are created by `add` / **Add game…**.

Portable save rules live in `config\save-rules.json`. The file is validated by `data\save-rules.schema.json`; `config\save-rules.example.json` seeds it on first use. Rules are plain JSON, so you can edit or commit them, and `rule-import` / `rule-export` move them between machines.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `running scripts is disabled` | Use `powershell -ExecutionPolicy Bypass -File .\GameSaveVault.ps1 ...` or run `Install.ps1` once. |
| "No installed games detected" | Add your game folder to `GameScanRoots` or use `add "Game" -Paths "..."`. |
| A game shows 0 save folders | The game may not have been launched yet, or saves are in an unusual place. Run `scan -Detailed`, then `add` or `rule-add`. |
| A repack / crack save is still missing | Add a rule with `rule-add "Game" -Paths "D:\Games\Game\Saves" -SavePattern *.sav -InstallDir "Game"`, then run `discover`. |
| Restore put saves in the wrong place | Use `-RestoreFormat profile` (new user, default), `verbatim` (original absolute path) or `folder -RestoreRoot <dir>`. |
| Vault is on C: | `doctor` warns about this. Move it: `backup -BackupRoot D:\GameSaveVault`, then edit `settings.json`. |
| Windows.old is gone | Windows deletes it after ~10 days. Only a vault backup can help after that. |
| Documents is redirected to OneDrive | The tool resolves the real Documents known-folder and also checks `OneDrive\Documents` in Windows.old. |
| Ubisoft saves do not appear | Ubisoft Connect uses account-ID subfolders under `%LOCALAPPDATA%\Ubisoft Game Launcher\savegames`. After a reinstall the new account ID may differ; the data is restored to the same relative path, so copy it into the new ID folder if needed. |
| Steam userdata restored under the wrong account | The tool keeps the old numeric account folder if it exists, otherwise uses the current most-recent Steam account. |
| Restore skipped a game | That entry was stored as `GAMEDIR\...` and the game is not installed yet. Install the game and restore again, or restore after installing. |
| Antivirus flags `robocopy`/`reg.exe` | These are built-in Windows tools used for copying and registry export; allow them. |

Diagnostics:

```powershell
powershell -ExecutionPolicy Bypass -File .\GameSaveVault.ps1 doctor
```

Self-tests (create and delete their own `%TEMP%` sandboxes and touch nothing real):

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\selftest.ps1
powershell -ExecutionPolicy Bypass -File .\tests\selftest-windowsold.ps1
powershell -ExecutionPolicy Bypass -File .\tests\selftest-deepscan.ps1
powershell -ExecutionPolicy Bypass -File .\tests\selftest-newos.ps1
powershell -ExecutionPolicy Bypass -File .\tests\selftest-emulators.ps1
powershell -ExecutionPolicy Bypass -File .\tests\selftest-formats.ps1
powershell -ExecutionPolicy Bypass -File .\tests\selftest-rules.ps1
```

---

## File layout

```
GameSaveVault\
  gamevault.sh                 Linux root executable launcher shim
  GameSaveVault.ps1            Windows CLI entry point shim (backwards compatible)
  GameSaveVault-GUI.ps1        Windows WinForms app launcher shim
  Install-GameSaveVault.ps1    Windows one-line installer shim
  Install.ps1                  Windows shortcut installer shim
  Register-ScheduledBackup.ps1 Windows scheduled backup task shim
  linux\                       Linux native implementation
    gamevault.sh               Primary CLI dispatcher & dashboard launcher
    modules\
      common.sh                Environment, config, logging, tokens, JSON tools
      scanner.sh               Proton, Flatpak, Wine, Lutris, Native, Emulator scanner
      vault.sh                 Snapshots, restore, rollback, token translator
      ui.sh                    Hybrid UI (Zenity GUI + Whiptail TUI + ANSI CLI)
  windows\                     Windows PowerShell implementation
    GameSaveVault.ps1          Main Windows CLI script
    GameSaveVault-GUI.ps1      WinForms application
    Install-GameSaveVault.ps1  Release installer
    Install.ps1                Desktop & Start-menu shortcut installer
    Register-ScheduledBackup.ps1 Scheduled backup task script
  modules\                     Windows PowerShell modules
    GSV.Core.psm1              Core discovery, catalog, and token utilities
    GSV.Vault.psm1             Snapshot, restore, and rollback engine
  data\catalog.psd1            96 curated games and save paths
  data\title-names.json        Steam AppID and Switch TitleID name mapping database
  data\save-rules.schema.json  JSON Schema for config\save-rules.json
  data\scan-database.schema.json JSON Schema for config\scan-database.json
  config\settings.json         User settings (vault path, scan roots)
  config\settings.example.json sample settings template
  config\scan-database.json    folders you chose + save locations found (git-ignored)
  config\save-rules.json       your save rules (generated / editable)
  config\save-rules.example.json seeded example rules
  config\games.custom.json     custom games database
  tests\
    test_linux_gamevault.sh    Comprehensive automated test suite for Linux
    selftest-structure.ps1     Repository layout and cross-platform shim test
    selftest.ps1               backup + restore round-trip
    selftest-windowsold.ps1    Windows.old import + restore
    selftest-newos.ps1         Steam AppId scan -> save -> restore to a new OS
    selftest-deepscan.ps1      crack / Steam-emulator / UWP deep scan
    selftest-emulators.ps1     console-emulator scan + migrate
    selftest-formats.ps1       profile / verbatim / folder restore formats
    selftest-rules.ps1         tokenize -> save -> discover -> new-PC restore -> import/export
    selftest-scandb.ps1        choose folders -> scan database -> portable .gsvdb restore
  .gitignore
  LICENSE
  README.md
```

---

## Decoded console game names

Console emulator saves are keyed by a *title ID*, not a game name. GameSaveVault ships a bundled title database (`data/title-names.json`, ~2,300 Nintendo Switch titles from the community switchbrew list) so those saves show up as **"The Legend of Zelda: Breath of the Wild"** instead of `01007EF00011E000`.

- The database is loaded automatically; nothing to configure.
- Add your own entries by creating `config/title-names.json` (same `{ "titleid": "Game name" }` format) — it overrides the bundled list. Useful for newer games or DLC.
- About `prod.keys` / `title.keys`: these files only contain encryption keys. They do **not** contain game names, so they cannot be used to decode a title ID. Names come from the title database above (or, on a real console, from the game's NACP metadata).

## Linux, macOS and Wine

GameSaveVault offers native support for both **Linux** (`./gamevault.sh`) and **Windows** (`GameSaveVault.ps1`).

- **Linux**: Native Bash implementation (`./gamevault.sh`) with auto-detecting Hybrid UI (Zenity GUI, Whiptail TUI, and ANSI CLI fallback), automated discovery for Steam Proton prefixes (Native & Flatpak), Wine, Lutris, Heroic Games Launcher, Bottles, console emulators, and native Linux saves. Full details in [Linux Quick Start & Usage](#linux-quick-start--usage).
- **Wine / Proton**: Games running inside Wine and Proton prefixes are automatically discovered and backed up by the Linux scanner. The Windows PowerShell scripts can also run under Wine if desired.
- **macOS**: Experimental. Vault snapshots, `manifest.json`, and `config/scan-database.json` are platform-neutral, so backups can be inspected or extracted manually on macOS.
- **Cross-Platform Compatibility**: Snapshots created on Windows can be restored directly on Linux, and vice-versa. Canonical path tokens (`%DOCUMENTS%`, `%APPDATA%`, etc.) are dynamically translated to destination platform paths during restore with full rollback protection.

---

## Notes

- Works with **any games**, including **crack games and emulators**. Use it with games you own. The tool only copies save data; it does not provide game files, cracks or DRM bypasses.
- Nothing is scanned until you choose folders. The first scan can take a few seconds because it walks the selected folders, `AppData`, `LocalLow` and `Documents` when those are ticked; later starts load `config\scan-database.json` instantly.
- Backups are plain files — you can open the vault in Explorer and copy it to another disk or cloud drive yourself.
- A portable `.gsvdb` file is just a zip containing `manifest.json`, the save payload and `scan-database.json`. You can inspect it with any zip tool.
