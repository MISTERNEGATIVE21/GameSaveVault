# Linux GameSaveVault (`gamevault.sh`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a Linux-native `gamevault.sh` shell script and GUI/TUI application that scans save folders (Proton, Flatpak, Wine, native Linux, emulators, custom paths), creates snapshots into a vault, and selectively restores saves with collision rollback protection.

**Architecture:** A modular Bash 5 engine split into `modules/common.sh`, `modules/scanner.sh`, `modules/vault.sh`, and `modules/ui.sh` under `linux/`, orchestrated by `linux/gamevault.sh` (with a root `gamevault.sh` executable wrapper). Auto-detects Zenity GUI in desktop environments, Whiptail TUI in terminal sessions, and ANSI fallback, sharing metadata schemas with the Windows implementation.

**Tech Stack:** GNU Bash 5+, `jq` / Python 3 JSON parser, `rsync` / `cp`, `zenity`, `whiptail`.

**Spec:** `docs/superpowers/specs/2026-11-11-linux-gamevault-design.md`

## Global Constraints

- Linux implementation files live in `linux/` and `linux/modules/`.
- Windows PowerShell files move to `windows/` with root wrapper shims for backwards compatibility.
- Root executable `gamevault.sh` dispatches to `linux/gamevault.sh`.
- Fully interoperable with GameSaveVault's existing JSON metadata schemas (`config/settings.json`, `config/scan-database.json`, `manifest.json`).
- Uses `jq` where available, with a fallback to `python3` for systems without `jq`.
- No destructive file overwrites: restore must preserve existing conflicting saves in `<vault>/rollback/<timestamp>/`.

## Review Focus

1. **Missing or unmounted external vault drive**: If secondary drive is missing or not writable, fallback to `~/GameSaveVault` and report clear warning.
2. **Proton prefix without wine user directory**: Ignore broken/incomplete prefixes without crashing or throwing unhandled errors.
3. **Empty or unselected checklist during restore**: Handle user cancelling dialogs or selecting 0 games gracefully with no partial operations.
4. **Symlinked save paths**: Use `cp -a` or `rsync -a` correctly without creating recursive symlink loops or traversing out-of-bounds files.
5. **JSON special characters in game titles or paths**: Quote and escape path strings properly in `jq` / Python JSON builders so games with quotes or ampersands don't break JSON manifests.

---

### Task 1: Repository Restructure & Platform Separation

**Files:**
- Create: `windows/GameSaveVault.ps1`, `windows/GameSaveVault-GUI.ps1`, `windows/Install-GameSaveVault.ps1`, `windows/Install.ps1`, `windows/Register-ScheduledBackup.ps1`
- Modify: `GameSaveVault.ps1`, `GameSaveVault-GUI.ps1` (turned into root wrappers forwarding to `windows/`)
- Test: Verify PowerShell root wrappers forward properly via syntax check or dry invocation

**Interfaces:**
- Produces: `windows/` containing all Windows scripts and root shims directing to `windows/`.

- [ ] **Step 1: Write test for root shims and directory structure**
Verify `windows/` contains the PowerShell scripts and root shims exist.
- [ ] **Step 2: Move existing Windows scripts to `windows/`**
Move `GameSaveVault.ps1`, `GameSaveVault-GUI.ps1`, `Install-GameSaveVault.ps1`, `Install.ps1`, `Register-ScheduledBackup.ps1` into `windows/`.
- [ ] **Step 3: Create root shims for `GameSaveVault.ps1` and `GameSaveVault-GUI.ps1`**
Root shims invoke the scripts in `windows/` passing through all parameters and exit codes.
- [ ] **Step 4: Verify git status and execute wrapper syntax check**
- [ ] **Step 5: Commit**
`git commit -m "refactor: organize Windows scripts into windows/ directory with root shims"`

---

### Task 2: Linux Common & JSON Engine (`linux/modules/common.sh`)

**Files:**
- Create: `linux/modules/common.sh`
- Test: `tests/test_linux_gamevault.sh`

**Interfaces:**
- Produces:
  - `gsv_init_env()`: Sets up directories, detects `jq` or `python3`.
  - `gsv_json_get(json_file, query)`: Queries JSON via `jq` or Python fallback.
  - `gsv_json_set(json_file, key, value)`: Updates JSON key.
  - `gsv_resolve_vault_path()`: Detects mounted drives (`/run/media`, `/mnt`) or `~/GameSaveVault`.
  - `gsv_path_to_token(path)`: Converts absolute path to portable token (`%APPDATA%`, `%XDG_DATA_HOME%`, etc.).
  - `gsv_token_to_path(token_path, [prefix_root])`: Converts portable token back to local path.

- [ ] **Step 1: Write test in `tests/test_linux_gamevault.sh` testing `common.sh` functions**
- [ ] **Step 2: Run test to verify failure**
- [ ] **Step 3: Implement `linux/modules/common.sh`**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**
`git commit -m "feat(linux): implement common environment and JSON utilities"`

---

### Task 3: Linux Game & Folder Scanner (`linux/modules/scanner.sh`)

**Files:**
- Create: `linux/modules/scanner.sh`
- Test: `tests/test_linux_gamevault.sh`

**Interfaces:**
- Consumes: `linux/modules/common.sh`
- Produces:
  - `gsv_scan_steam_proton()`: Scans Steam Native & Flatpak Proton prefixes (`compatdata/*/pfx/drive_c/users/steamuser/...`).
  - `gsv_scan_native_games()`: Scans `~/.local/share` and `~/.config` for game save signatures.
  - `gsv_scan_wine_lutris_heroic()`: Scans `~/.wine`, `~/Games`, `~/.config/heroic`.
  - `gsv_scan_emulators()`: Scans Ryujinx, RPCS3, PCSX2, Dolphin, RetroArch save paths.
  - `gsv_deep_scan_folder(folder_path, max_depth)`: Recursively scans a custom directory for save files (`.sav`, `.dat`, `.sl2`, etc.).
  - `gsv_update_scan_database(locations_json)`: Updates `config/scan-database.json`.

- [ ] **Step 1: Write scanner unit tests in `tests/test_linux_gamevault.sh` with mock directory tree**
- [ ] **Step 2: Run test to verify failure**
- [ ] **Step 3: Implement `linux/modules/scanner.sh`**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**
`git commit -m "feat(linux): implement game and custom folder scanner"`

---

### Task 4: Vault, Snapshots, Restore & Rollback Engine (`linux/modules/vault.sh`)

**Files:**
- Create: `linux/modules/vault.sh`
- Test: `tests/test_linux_gamevault.sh`

**Interfaces:**
- Consumes: `linux/modules/common.sh`, `linux/modules/scanner.sh`
- Produces:
  - `gsv_create_snapshot(selected_games_json, is_dry_run)`: Copies saves to `<vault>/snapshots/<timestamp>/data/` and generates `manifest.json`.
  - `gsv_list_snapshots()`: Reads and displays snapshots in vault.
  - `gsv_restore_snapshot(snapshot_id, selected_games, is_dry_run, restore_root)`: Restores saves, backing up overwritten targets to `<vault>/rollback/<timestamp>/`.

- [ ] **Step 1: Write snapshot creation, rollback, and restore tests in `tests/test_linux_gamevault.sh`**
- [ ] **Step 2: Run test to verify failure**
- [ ] **Step 3: Implement `linux/modules/vault.sh`**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**
`git commit -m "feat(linux): implement snapshot backup, selective restore, and rollback engine"`

---

### Task 5: Hybrid UI/TUI Layer (`linux/modules/ui.sh`)

**Files:**
- Create: `linux/modules/ui.sh`
- Test: Interactive smoke test & headless checks

**Interfaces:**
- Consumes: `linux/modules/common.sh`, `linux/modules/scanner.sh`, `linux/modules/vault.sh`
- Produces:
  - `gsv_ui_detect()`: Determines `zenity`, `whiptail`, or `cli` mode.
  - `gsv_ui_menu(title, prompt, items_array)`: Shows radio/selection menu.
  - `gsv_ui_checklist(title, prompt, items_array)`: Multi-select checklist for games/folders.
  - `gsv_ui_dir_picker(title)`: Folder browser.
  - `gsv_ui_message(title, msg)`: Info dialog or box.
  - `gsv_ui_confirm(title, question)`: Yes/No dialog.
  - `gsv_launch_dashboard()`: Interactive dashboard loop.

- [ ] **Step 1: Write headless tests for UI abstraction wrappers**
- [ ] **Step 2: Run test to verify failure**
- [ ] **Step 3: Implement `linux/modules/ui.sh` (Zenity GUI + Whiptail TUI + ANSI CLI)**
- [ ] **Step 4: Run test to verify passes**
- [ ] **Step 5: Commit**
`git commit -m "feat(linux): implement auto-detecting hybrid UI/TUI abstraction"`

---

### Task 6: Main CLI Dispatcher & Root Executable

**Files:**
- Create: `linux/gamevault.sh`, `gamevault.sh` (root symlink or launcher)
- Test: `tests/test_linux_gamevault.sh` CLI tests

**Interfaces:**
- Consumes: all `linux/modules/*.sh`
- Produces: CLI commands: `scan`, `scan-folders`, `scan-db`, `backup`, `restore`, `snapshots`, `doctor`, `gui`, `help`.

- [ ] **Step 1: Write CLI dispatch tests (help, scan, doctor, backup flags) in `tests/test_linux_gamevault.sh`**
- [ ] **Step 2: Run test to verify failure**
- [ ] **Step 3: Implement `linux/gamevault.sh` and root wrapper `gamevault.sh`**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**
`git commit -m "feat(linux): implement main gamevault.sh CLI dispatcher and root launcher"`

---

### Task 7: Full Integration Verification & Documentation

**Files:**
- Modify: `README.md` (Add Linux usage and quick start instructions)
- Test: `tests/test_linux_gamevault.sh`

- [ ] **Step 1: Run complete `tests/test_linux_gamevault.sh` test suite**
- [ ] **Step 2: Document Linux commands and usage in `README.md`**
- [ ] **Step 3: Verify all test cases pass without regression**
- [ ] **Step 4: Commit**
`git commit -m "docs: add Linux gamevault.sh usage instructions to README"`
