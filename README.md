# GameSaveVault

A local Windows app that finds your game save folders, copies them into a vault on another drive, and puts them back after you reinstall Windows.

It handles normal Steam/Epic/GOG games **and** repack / Steam-emulator setups (FitGirl, DODI, ElAmigos, Goldberg, SmartSteamEmu, CODEX/RUNE/EMPRESS saves). It does not download games, patch DRM, or touch game install files — it only copies save data, profiles and settings.

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
cd "H:\Documents\Default Project\GameSaveVault"
powershell -ExecutionPolicy Bypass -File .\GameSaveVault.ps1 backup -All
```

The vault defaults to the first non-system drive (here: `G:\GameSaveVault`). Keep it on `D:`, `E:`, `G:` or an external USB drive — **not on C:**.

After the new Windows is installed and the games are reinstalled:

```powershell
powershell -ExecutionPolicy Bypass -File .\GameSaveVault.ps1 restore -Snapshot latest -DryRun
powershell -ExecutionPolicy Bypass -File .\GameSaveVault.ps1 restore -Snapshot latest
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
2. Scans the catalog + safe game roots + Steam userdata + emulator/scene folders.
3. Copies everything into a normal vault snapshot.
4. Restores that snapshot into the current profile.

Use `-WindowsOldRoot "D:\Windows.old"` if the old install is on another drive.

---

## Quick start

Requirements: Windows 10/11, Windows PowerShell 5.1 (built in). No admin rights for normal use.

```powershell
cd "H:\Documents\Default Project\GameSaveVault"

# 1. see what it finds
powershell -ExecutionPolicy Bypass -File .\GameSaveVault.ps1 scan

# 2. see every path for every game
powershell -ExecutionPolicy Bypass -File .\GameSaveVault.ps1 scan -Detailed

# 3. back everything up
powershell -ExecutionPolicy Bypass -File .\GameSaveVault.ps1 backup -All

# 4. list snapshots
powershell -ExecutionPolicy Bypass -File .\GameSaveVault.ps1 snapshots
```

### GUI

```powershell
powershell -ExecutionPolicy Bypass -File .\GameSaveVault-GUI.ps1
```

Or run `Install.ps1` once to create a desktop / Start-menu shortcut:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install.ps1
```

The GUI shows every detected game with a checkbox, the save folders it found, and buttons for **Backup selected**, **Backup all**, **Restore…**, **Windows.old…**, **Deep scan…**, **Add game…**, **Open vault**, **Backup location…** and **Doctor**. Double-click a row to open its save folder.

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

## Commands

| Command | What it does |
|---|---|
| `scan` | Detect installed games and the save folders found (default). `-Detailed` prints every path. |
| `deep-scan` | Search a whole drive for save folders the normal scan may miss (aliases: `deepscan`, `deep`, `search`). `-Drive C:`, `-AllDrives`, `-MaxDepth 12`, `-MaxResults 500`, `-NoSize`, `-Backup`. |
| `migrate` | Copy console-emulator saves between emulators: `-From eden -To ryujinx`, `-From kyty`, `-Title <id>`, `-DryRun`. |
| `backup` | Snapshot saves into the vault. `-All` includes launcher-wide/emulator folders. `-Game Skyrim,Palworld` limits it. |
| `restore` | Restore the latest or a named snapshot. `-DryRun`, `-Game`, `-KeepExisting`, `-SkipRegistry`. |
| `from-old` | Import + restore saves from `C:\Windows.old`. `-DryRun`, `-NoRestore`, `-WindowsOldRoot`. |
| `snapshots` | List snapshots with date, size, file count and errors. |
| `stats` | Vault size and free space. |
| `add` | Register a custom game and save path(s). |
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
-NoGlobal                        # skip Ubisoft/Goldberg/scene-wide folders
-Keep 8                          # how many snapshots to keep
-Drive C: -AllDrives             # deep-scan only: which drive(s) to search
-MaxDepth 12 -MaxResults 500     # deep-scan only: folder depth and hit limit
-NoSize                         # deep-scan only: skip file counting (much faster)
-Backup                         # deep-scan only: snapshot everything found
-From / -To <emu>               # migrate only: eden, eglantine, ryujinx, kyty, shadps4
-Title <id>                     # migrate only: one title id (0100… or PPSA…)
```

Examples:

```powershell
# search the whole C: drive for save folders (CPY / GSE / Goldberg / scene remote / UWP / LocalLow)
.\GameSaveVault.ps1 deep-scan -Drive C: -NoSize

# same, then back everything up into G:\GameSaveVault
.\GameSaveVault.ps1 deep-scan -AllDrives -MaxDepth 12 -Backup

# copy Switch saves from Eden to Ryujinx (matches by title id, remaps the
# profile id, and moves any overwritten save to the vault rollback folder)
.\GameSaveVault.ps1 migrate -From eden -To ryujinx
.\GameSaveVault.ps1 migrate -From eden -To eglantine -Title 0100000000010000 -DryRun
.\GameSaveVault.ps1 migrate -From kyty -To shadps4 -DryRun

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
```

---

## Where PC games actually keep saves

This is the map the scanner uses. Repacks do **not** move saves — a FitGirl/DODI/ElAmigos repack is just a compressed installer of the original game files, so the game still writes to its normal folders.

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

### FitGirl / DODI / ElAmigos / crack games specifically

- The repack name (`[FitGirl Repack]`, `[DODI Repack]`, `ElAmigos`) is ignored when matching, so `Expeditions A MudRunner Game [DODI Repack]` still matches the real game.
- Saves stay in the original game's paths — `Documents\My Games\...`, `AppData\...`, etc.
- If the repack ships a Steam emulator, saves can instead be in:
  - `%APPDATA%\Goldberg SteamEmu Saves\<appid>\remote`
  - `%APPDATA%\GSE Saves\<appid>\remote`  (GSE = Goldberg SteamEmu / EmulGBE saves)
  - `%LOCALAPPDATA%\GSE Saves\...`, `%PROGRAMDATA%\GSE Saves\...`
  - `%APPDATA%\SmartSteamEmu\<appid>`
  - `<game folder>\steam_settings` (config)
- Scene groups (CODEX, RUNE, PLAZA, ALI213, EMPRESS, SKIDROW, RELOADED, 3DM, HOODLUM, FLT, RAZOR1911, TENOKE, PROPHET):
  - `C:\Users\Public\Documents\Steam\CODEX\<appid>\remote`
  - `C:\Users\Public\Documents\Steam\RUNE\<appid>`, `\PLAZA\<appid>`, `\ALI213\<appid>`
  - `C:\Users\Public\Documents\EMPRESS\<appid>`
  - `C:\ProgramData\Steam\CODEX\<appid>`
  - `Documents\CPY_SAVES\<appid>`, `%APPDATA%\SKIDROW\...`, `%APPDATA%\RELOADED\...`, `%APPDATA%\3DMGAME\...`
- Not every game on this list has a catalog entry — that is exactly what `deep-scan` is for. It walks the drive and reports every folder that looks like a save location, including `eden` (Switch emulator) Nintendo save trees, UWP/Xbox `Packages\...\SystemAppData\wgs` containers, and Unity `LocalLow\<company>\<product>` folders.

#### Jump Force example

Jump Force stores its story save in the scene release folder:

```
C:\Users\Public\Documents\Steam\CODEX\816020\remote\jfsavedata.dat
```

The `deep-scan` found it and backed it up (AppId `816020`). The game also has a catalog entry with `%LOCALAPPDATA%\JUMP FORCE\Saved\SaveGames`, `%STEAMUSERDATA%\816020\remote`, `CPY_SAVES\816020`, `GSE Saves\816020` and Goldberg paths, so normal `scan`/`backup` will find the save as soon as any of those folders exist.

### Console emulator saves (Switch & PlayStation) and migration

Big console emulators keep saves **outside** the game folder, keyed by a *title ID* instead of a game name. The scanner enumerates every title, so `scan` lists them under **Console emulator saves**, and `backup` includes them.

| Emulator(s) | Console | Save roots (relative to the emulator data folder) |
|---|---|---|
| **Eden**, **Eglantine**, Yuzu, Suyu | Nintendo Switch | `nand\user\save\<profile>\<titleID>` and `nand\system\save\<profile>\<titleID>` (title ID = 16 hex digits) |
| **Ryujinx** | Nintendo Switch | `bis\user\save\<profile>\<titleID>` and `bis\system\save\<profile>\<titleID>` |
| **Kyty / KytyPS5** | PlayStation 5 | `_SaveData\PPSA…` **next to the emulator exe** (portable — the install folder can be called anything) |
| **shadPS4** | PlayStation 4 | `user\<profile>\savedata\<CUSA…>` |

Data folders are probed in `%APPDATA%\<emulator>` and `%LOCALAPPDATA%\<emulator>`, plus a shallow walk of every drive for portable installs (any folder named `eden` / `eglantine` / `ryujinx` / `yuzu` / `suyu` / `kyty` / `shadps4`, or any `_SaveData` folder — Recycle Bins, caches and system folders are skipped).

#### Migrating saves between emulators

Switch saves are stored the way the game wrote them, so moving between Eden / Eglantine / Ryujinx is a folder copy matched by title ID. The profile ID is remapped to the destination's own, and any save that would be overwritten is moved to `vault\rollback\<timestamp>\` first.

```powershell
# see what would happen first
.\GameSaveVault.ps1 migrate -From eden -To ryujinx -DryRun

# copy everything, or just one title
.\GameSaveVault.ps1 migrate -From eden -To ryujinx
.\GameSaveVault.ps1 migrate -From eden -To eglantine -Title 0100000000010000

# PS5/PS4: Kyty stores its saves in _SaveData\PPSA… ; move them to shadPS4
.\GameSaveVault.ps1 migrate -From kyty -To shadps4
```

Notes:

- The destination emulator must be installed and must have launched once (its save folder has to exist).
- PS4/PS5 **game files are never copied** — only save data. Kyty's shader caches (`_PipelineCache`) are skipped; you can re-download/recompile them.
- Kyty/Eglantine installs that live on another drive (for example `D:\KytyPS5\_SaveData\PPSA21567`) are restored to the **same drive path**, because there is no per-user token to anchor them to. The AppData-based emulators (Eden, Ryujinx, Eglantine, shadPS4) restore into the *new* Windows profile, like every other save.
- The GUI has a **Migrate…** button with From/To dropdowns and a per-title checkbox list.
- Scene-style releases often use:
  - `%PUBLIC%\Documents\Steam\CODEX\<appid>`
  - `%PUBLIC%\Documents\Steam\RUNE\<appid>`
  - `%PUBLIC%\Documents\Steam\ALI213\<appid>`
  - `%PUBLIC%\Documents\EMPRESS\<appid>`
  - `%PROGRAMDATA%\Steam\CODEX\<appid>`
- Older cracks put saves inside the install folder (`Profile`, `SaveData`, `Saves`, `ALI213`), which the scanner also checks.

The app backs up **all** of the emulator/scene roots above as "Global launcher / emulator saves" even when it cannot identify which game they belong to.

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

For every installed game the tool combines:

1. **Steam** — reads `libraryfolders.vdf` + `appmanifest_*.acf` from every library.
2. **Epic** — reads the Epic manifest `.item` files.
3. **GOG** — reads the GOG registry entries.
4. **Folder scan** — looks in `GameScanRoots` (defaults: `D:\Games`, Epic folder, Steam `steamapps\common`, common GOG/Ubisoft/EA paths) and detects real game folders by `.exe`/engine markers.
5. **Catalog** — 89 curated games with exact save paths, matched by Steam AppID, name and aliases.
6. **Heuristics** — for unknown games it checks:
   - `Documents\My Games\<name>`, `Documents\<name>`, `Saved Games\<name>`, `AppData\<name>`, `LocalAppData\<name>`
   - `LocalLow\<company>\<product>` (Unity)
   - `Save`/`Saves`/`SaveData`/`Profile`/`Profiles` inside the install folder
   - Steam userdata for the game's AppID
   - Goldberg / SmartSteamEmu / CODEX / RUNE / ALI213 / EMPRESS folders
7. **Name matching** strips repack tags, version numbers and edition words, then compares word tokens (so `Skyrim Special Edition` matches `The Elder Scrolls V: Skyrim Special Edition`).

If a game is missing, add its folder to `GameScanRoots` in `config\settings.json`, or register the save path directly with `add`.

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

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `running scripts is disabled` | Use `powershell -ExecutionPolicy Bypass -File .\GameSaveVault.ps1 ...` or run `Install.ps1` once. |
| "No installed games detected" | Add your game folder to `GameScanRoots` or use `add "Game" -Paths "..."`. |
| A game shows 0 save folders | The game may not have been launched yet, or saves are in an unusual place. Run `scan -Detailed`, then `add`. |
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
```

---

## File layout

```
GameSaveVault\
  GameSaveVault.ps1              CLI entry point
  GameSaveVault-GUI.ps1          WinForms app (PowerShell + System.Windows.Forms)
  Install.ps1                    desktop/start-menu shortcut + optional task
  Register-ScheduledBackup.ps1   daily backup task
  modules\
    GSV.Core.psm1                discovery, tokens, catalog, Windows.old scan
    GSV.Vault.psm1               snapshot, restore, rollback, pruning
  data\catalog.psd1              96 curated games and save paths
  config\settings.json           generated on first run (git-ignored)
  config\settings.example.json   sample settings
  config\games.custom.json       generated when you add games
  tests\
    selftest.ps1                 backup + restore round-trip
    selftest-windowsold.ps1      Windows.old import + restore
    selftest-newos.ps1           Steam AppId scan -> save -> restore to a new OS
    selftest-deepscan.ps1        CPY/GSE/Goldberg/scene/UWP deep scan
    selftest-emulators.ps1       Eden / Ryujinx / Eglantine / Kyty (_SaveData) / shadPS4 scan + migrate
  .gitignore
  LICENSE
```

---

## Notes

- Use this with games you own. The tool only copies save data; it does not provide game files, cracks or DRM bypasses.
- The first scan can take a few seconds because it walks `AppData`, `LocalLow` and `Documents`. Later runs are similar; there is no background service.
- Backups are plain files — you can open the vault in Explorer and copy it to another disk or cloud drive yourself.
