# Loading Progress Indicator & Console Emulator Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an animated loading progress indicator with elapsed time measurement to the Linux UI/TUI scanner, and implement dedicated save detection for Nintendo Switch (Eden, Eglantine, Litchi/Litchii) and PlayStation 5/4 (Kyty/KytyPS5, shadPS4, Spine, RPCSX) emulators.

**Architecture:**
- `linux/modules/ui.sh`: Upgrade `_gsv_ui_action_scan_all` and `_gsv_ui_action_scan_custom` to run the scan asynchronously with an active pulsating progress dialog in Zenity, elapsed time tracking with sub-second precision, and a completion summary displaying elapsed scan time.
- `linux/modules/scanner.sh`: Expand `gsv_scan_emulators` with dedicated scanning functions for Eden, Eglantine, Litchi/Litchii, Kyty PS5/PS4, shadPS4, Spine, and RPCSX, handling both standard and nested profile layouts, portable/Flatpak/Wine paths, and title ID lookups.
- `tests/test_linux_gamevault.sh`: Add unit tests covering Eden, Eglantine, Litchi, Kyty, shadPS4 detection, and scan timing verification.
- `README.md`: Document newly supported emulators and scan timing behavior.

**Tech Stack:** Bash 4+, Zenity, Whiptail/Dialog, jq / Python 3 JSON parser, Linux XDG Base Directory specification.

**Spec:** User request: "loading time scanning should also be threre ; especiallly eden nintendo switch or ps5 emulator save litchii or eglantine game save manager asl o add them"

## Global Constraints
- Must remain 100% non-destructive and backward-compatible with existing scan database and vault formats.
- No new external runtime dependencies; use standard Linux utilities (`zenity`, `whiptail`, `bash`, `python3` / `jq`).
- Support both native Linux paths (`~/.config`, `~/.local/share`, `~/.var/app`), Wine/Proton prefixes, and custom `$emu_base` for portable roots.

## Review Focus
1. Eden / Eglantine nested save directories (`nand/user/save/<profile>/<32-hex-save-id>/<16-hex-title-id>`) must be recognized properly without false positives on profile IDs.
2. PS5 title IDs (`PPSA\d{4,6}`) and PS4 title IDs (`CUSA\d{4,6}`) in Kyty `_SaveData` and shadPS4 `savedata` must be mapped to distinct location entries with accurate file counts and byte sizes.
3. Zenity progress dialog must close cleanly when the scan terminates without hanging the process or leaving orphaned child processes.
4. Elapsed scan time calculation must work cleanly across systems with or without `bc` (using Python 3 float arithmetic or bash integer arithmetic fallback).
5. All 55 existing unit tests plus new tests must pass with 0 regressions.

---

### Task 1: Extend Switch Emulators & Save Managers Scanning in scanner.sh
**Files:**
- Modify: `linux/modules/scanner.sh`
- Test: `tests/test_linux_gamevault.sh`

- [ ] Step 1.1: Write failing test in `tests/test_linux_gamevault.sh` for Eden (`test_scan_eden`), Eglantine (`test_scan_eglantine`), and Litchi/Litchii (`test_scan_litchi`).
- [ ] Step 1.2: Run test suite to verify tests fail as expected.
- [ ] Step 1.3: In `linux/modules/scanner.sh`, implement `_scan_switch_nand_bis_root` helper to handle both direct `<profile>/<title_id>` and nested `<profile>/<save_id>/<title_id>` structures.
- [ ] Step 1.4: In `linux/modules/scanner.sh`, implement `_scan_eden`, `_scan_eglantine`, and `_scan_litchi` with config/local/Flatpak/Wine search paths.
- [ ] Step 1.5: Wire them into `gsv_scan_emulators`.
- [ ] Step 1.6: Run `bash tests/test_linux_gamevault.sh` to confirm tests pass.

### Task 2: Implement PS5 and PS4 Emulators Scanning in scanner.sh
**Files:**
- Modify: `linux/modules/scanner.sh`
- Test: `tests/test_linux_gamevault.sh`

- [ ] Step 2.1: Write failing test in `tests/test_linux_gamevault.sh` for Kyty / KytyPS5 (`test_scan_kyty_ps5`) and shadPS4 (`test_scan_shadps4`).
- [ ] Step 2.2: Run test suite to verify tests fail as expected.
- [ ] Step 2.3: In `linux/modules/scanner.sh`, implement `_scan_kyty` searching `_SaveData` and `savedata` for `^(PPSA|CUSA)\d{4,6}$`.
- [ ] Step 2.4: In `linux/modules/scanner.sh`, implement `_scan_shadps4` searching `user/*/savedata/` and `savedata/` for `^(CUSA|PPSA)\d{4,6}$`.
- [ ] Step 2.5: In `linux/modules/scanner.sh`, implement `_scan_spine_rpcsx` for Spine and RPCSX PS4 emulators.
- [ ] Step 2.6: Wire them into `gsv_scan_emulators`.
- [ ] Step 2.7: Run `bash tests/test_linux_gamevault.sh` to confirm tests pass.

### Task 3: Implement Visual Loading Progress & Elapsed Time Tracking in ui.sh
**Files:**
- Modify: `linux/modules/ui.sh`
- Test: `tests/test_linux_gamevault.sh`

- [ ] Step 3.1: In `linux/modules/ui.sh`, introduce high-resolution timing helper `_gsv_ui_timer_now` and `_gsv_ui_timer_elapsed`.
- [ ] Step 3.2: Refactor `_gsv_ui_action_scan_all` to show animated pulsating progress bar in Zenity without blocking, track elapsed time, and report duration in completion dialog.
- [ ] Step 3.3: Refactor `_gsv_ui_action_scan_custom` with identical pulsating progress bar and elapsed time reporting.
- [ ] Step 3.4: Add spinner / progress message with timing in Whiptail TUI / CLI mode.
- [ ] Step 3.5: Write test in `tests/test_linux_gamevault.sh` validating timing output and scanner progress invocation.
- [ ] Step 3.6: Run `bash tests/test_linux_gamevault.sh` to verify all tests pass.

### Task 4: Documentation & Final Verification
**Files:**
- Modify: `README.md`
- Test: `tests/test_linux_gamevault.sh`, `tests/selftest-structure.ps1`

- [ ] Step 4.1: Update `README.md` with Nintendo Switch (Eden, Eglantine, Litchi) and PS5/PS4 (Kyty, shadPS4, Spine) emulator support documentation and GUI scan timing notes.
- [ ] Step 4.2: Run complete Linux test suite `bash tests/test_linux_gamevault.sh`.
- [ ] Step 4.3: Run structure test suite `pwsh tests/selftest-structure.ps1`.
- [ ] Step 4.4: Verify working tree clean and ready for commit.
