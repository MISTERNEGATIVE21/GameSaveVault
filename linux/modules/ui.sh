#!/usr/bin/env bash
# ==============================================================================
# linux/modules/ui.sh
# Hybrid UI/TUI abstraction layer for GameSaveVault (Zenity, Whiptail/Dialog, ANSI CLI)
# ==============================================================================

# Guard against duplicate inclusion
if [ -n "${_GSV_UI_LOADED:-}" ]; then
    return 0
fi
_GSV_UI_LOADED=1

# Ensure common.sh, scanner.sh, and vault.sh are loaded
_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "${_GSV_COMMON_LOADED:-}" ]; then
    if [ -f "$_MODULE_DIR/common.sh" ]; then
        # shellcheck source=common.sh
        source "$_MODULE_DIR/common.sh"
    fi
fi
if [ -z "${_GSV_SCANNER_LOADED:-}" ]; then
    if [ -f "$_MODULE_DIR/scanner.sh" ]; then
        # shellcheck source=scanner.sh
        source "$_MODULE_DIR/scanner.sh"
    fi
fi
if [ -z "${_GSV_VAULT_LOADED:-}" ]; then
    if [ -f "$_MODULE_DIR/vault.sh" ]; then
        # shellcheck source=vault.sh
        source "$_MODULE_DIR/vault.sh"
    fi
fi

# ==============================================================================
# Helper Utilities
# ==============================================================================

# _gsv_ui_get_game_count(db_file)
# Returns the number of locations tracked in the scan database.
# Works safely across both jq and python3 fallbacks.
_gsv_ui_get_game_count() {
    local db_file="${1:-}"
    if [ ! -f "$db_file" ]; then
        echo 0
        return 0
    fi
    local tool="${GSV_JSON_TOOL:-}"
    if [ "$tool" = "jq" ] || { [ -z "$tool" ] && command -v jq >/dev/null 2>&1; }; then
        jq '.Locations | length' "$db_file" 2>/dev/null || echo 0
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c '
import sys, json
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        data = json.load(f)
    print(len(data.get("Locations", [])))
except Exception:
    print(0)
' "$db_file" 2>/dev/null || echo 0
    else
        echo 0
    fi
}

# ==============================================================================
# Mode Detection
# ==============================================================================

# gsv_ui_detect()
# Determines active UI mode: 'zenity', 'whiptail', 'dialog', or 'cli'.
# Supports explicit override via $GSV_UI_MODE (zenity/gui, whiptail/dialog/tui, cli).
gsv_ui_detect() {
    # 1. Explicit override via GSV_UI_MODE
    local override="${GSV_UI_MODE:-}"
    if [ -n "$override" ]; then
        case "${override,,}" in
            zenity|gui)
                echo "zenity"
                return 0
                ;;
            whiptail)
                echo "whiptail"
                return 0
                ;;
            dialog)
                echo "dialog"
                return 0
                ;;
            tui)
                if command -v whiptail >/dev/null 2>&1; then
                    echo "whiptail"
                elif command -v dialog >/dev/null 2>&1; then
                    echo "dialog"
                else
                    echo "cli"
                fi
                return 0
                ;;
            cli)
                echo "cli"
                return 0
                ;;
        esac
    fi

    # 2. Auto-detection:
    # If zenity is available and a graphical display server is active
    if command -v zenity >/dev/null 2>&1 && { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; }; then
        echo "zenity"
        return 0
    fi

    # Else if stdin is a terminal and a TUI tool is available
    if [ -t 0 ]; then
        if command -v whiptail >/dev/null 2>&1; then
            echo "whiptail"
            return 0
        elif command -v dialog >/dev/null 2>&1; then
            echo "dialog"
            return 0
        fi
    fi

    # Fallback to ANSI CLI
    echo "cli"
    return 0
}

# ==============================================================================
# UI Primitives
# ==============================================================================

# gsv_ui_message(title, msg, [type])
# Displays a dialog or message box. Type can be 'info' (default), 'warning', 'error'.
gsv_ui_message() {
    local title="${1:-Message}"
    local msg="${2:-}"
    local type="${3:-info}"
    local mode
    mode="$(gsv_ui_detect)"

    case "$mode" in
        zenity)
            local ztype="--info"
            case "${type,,}" in
                warn|warning) ztype="--warning" ;;
                err|error)   ztype="--error" ;;
            esac
            zenity "$ztype" --title="$title" --text="$msg" --no-wrap 2>/dev/null || true
            return 0
            ;;
        whiptail|dialog)
            local tool="$mode"
            local lines
            lines=$(printf "%s\n" "$msg" | wc -l)
            local h=$(( lines + 8 ))
            [ "$h" -lt 10 ] && h=10
            [ "$h" -gt 24 ] && h=24
            "$tool" --title "$title" --msgbox "$msg" "$h" 72 2>/dev/null || true
            return 0
            ;;
        *)
            # cli
            local color="\033[0;32m" # Green
            case "${type,,}" in
                warn|warning) color="\033[0;33m" ;; # Yellow
                err|error)   color="\033[0;31m" ;; # Red
            esac
            printf "\n%b=== [ %s ] ===%b\n%s\n\n" "$color" "$title" "\033[0m" "$msg"
            return 0
            ;;
    esac
}

# gsv_ui_confirm(title, question)
# Prompts user with Yes/No question. Returns 0 for Yes, 1 for No/Cancel.
gsv_ui_confirm() {
    local title="${1:-Confirm}"
    local question="${2:-Are you sure?}"
    local mode
    mode="$(gsv_ui_detect)"

    case "$mode" in
        zenity)
            zenity --question --title="$title" --text="$question" --no-wrap 2>/dev/null
            return $?
            ;;
        whiptail|dialog)
            local tool="$mode"
            "$tool" --title "$title" --yesno "$question" 10 65 2>/dev/null
            return $?
            ;;
        *)
            # cli
            printf "\n%b[?] %s%b\n" "\033[1;36m" "$title" "\033[0m" >&2
            printf "%s [y/N]: " "$question" >&2
            local resp
            if ! IFS= read -r resp; then
                return 1
            fi
            resp="$(echo "$resp" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
            if [ "$resp" = "y" ] || [ "$resp" = "yes" ]; then
                return 0
            fi
            return 1
            ;;
    esac
}

# gsv_ui_input(title, prompt, [default_val])
# Prompts user for a single line text input. Outputs entered text.
gsv_ui_input() {
    local title="${1:-Input}"
    local prompt="${2:-Enter value:}"
    local default_val="${3:-}"
    local mode
    mode="$(gsv_ui_detect)"

    case "$mode" in
        zenity)
            local res
            if [ -n "$default_val" ]; then
                res=$(zenity --entry --title="$title" --text="$prompt" --entry-text="$default_val" 2>/dev/null)
            else
                res=$(zenity --entry --title="$title" --text="$prompt" 2>/dev/null)
            fi
            if [ $? -ne 0 ]; then
                return 1
            fi
            echo "$res"
            return 0
            ;;
        whiptail|dialog)
            local tool="$mode"
            local res
            res=$("$tool" --title "$title" --inputbox "$prompt" 10 65 "$default_val" 3>&1 1>&2 2>&3)
            local status=$?
            if [ $status -ne 0 ]; then
                return 1
            fi
            echo "$res"
            return 0
            ;;
        *)
            # cli
            if [ -n "$default_val" ]; then
                printf "%s [%s]: " "$prompt" "$default_val" >&2
            else
                printf "%s: " "$prompt" >&2
            fi
            local res
            if ! IFS= read -r res; then
                if [ -n "$default_val" ]; then
                    echo "$default_val"
                    return 0
                fi
                return 1
            fi
            if [ -z "$res" ] && [ -n "$default_val" ]; then
                res="$default_val"
            fi
            echo "$res"
            return 0
            ;;
    esac
}

# gsv_ui_dir_picker(title, [default_dir])
# Prompts user to select a directory path. Outputs selected path.
gsv_ui_dir_picker() {
    local title="${1:-Select Directory}"
    local default_dir="${2:-$HOME}"
    local mode
    mode="$(gsv_ui_detect)"

    case "$mode" in
        zenity)
            local res
            if [ -n "$default_dir" ]; then
                res=$(zenity --file-selection --directory --title="$title" --filename="$default_dir/" 2>/dev/null)
            else
                res=$(zenity --file-selection --directory --title="$title" 2>/dev/null)
            fi
            if [ $? -ne 0 ] || [ -z "$res" ]; then
                return 1
            fi
            echo "$res"
            return 0
            ;;
        whiptail|dialog)
            local tool="$mode"
            local res
            res=$("$tool" --title "$title" --inputbox "Enter full directory path:" 10 70 "$default_dir" 3>&1 1>&2 2>&3)
            local status=$?
            if [ $status -ne 0 ] || [ -z "$res" ]; then
                return 1
            fi
            res="${res/#\~/$HOME}"
            echo "$res"
            return 0
            ;;
        *)
            # cli
            printf "%s [%s]: " "$title" "$default_dir" >&2
            local res
            if ! IFS= read -r res; then
                if [ -n "$default_dir" ]; then
                    echo "$default_dir"
                    return 0
                fi
                return 1
            fi
            if [ -z "$res" ]; then
                res="$default_dir"
            fi
            res="${res/#\~/$HOME}"
            echo "$res"
            return 0
            ;;
    esac
}

# gsv_ui_menu(title, prompt, tag1, desc1, tag2, desc2, ...)
# Displays a selection menu. Outputs selected tag.
gsv_ui_menu() {
    local title="${1:-Menu}"
    local prompt="${2:-Select an option:}"
    [ $# -ge 1 ] && shift
    [ $# -ge 1 ] && shift

    local tags=()
    local descs=()
    while [ $# -ge 2 ]; do
        tags+=("$1")
        descs+=("$2")
        shift 2
    done

    if [ "${#tags[@]}" -eq 0 ]; then
        return 1
    fi

    local mode
    mode="$(gsv_ui_detect)"

    case "$mode" in
        zenity)
            local zargs=(--list --title="$title" --text="$prompt" --column="Key" --column="Description" --hide-header --print-column=1 --height=420 --width=580)
            for ((i=0; i<${#tags[@]}; i++)); do
                zargs+=("${tags[i]}" "${descs[i]}")
            done
            local res
            res=$(zenity "${zargs[@]}" 2>/dev/null)
            if [ $? -ne 0 ] || [ -z "$res" ]; then
                return 1
            fi
            echo "$res"
            return 0
            ;;
        whiptail|dialog)
            local tool="$mode"
            local count=${#tags[@]}
            local menu_h=$(( count + 2 ))
            [ "$menu_h" -gt 15 ] && menu_h=15
            local box_h=$(( menu_h + 8 ))
            local targs=()
            for ((i=0; i<count; i++)); do
                targs+=("${tags[i]}" "${descs[i]}")
            done
            local res
            res=$("$tool" --title "$title" --menu "$prompt" "$box_h" 72 "$menu_h" "${targs[@]}" 3>&1 1>&2 2>&3)
            local status=$?
            if [ $status -ne 0 ] || [ -z "$res" ]; then
                return 1
            fi
            echo "$res"
            return 0
            ;;
        *)
            # cli
            printf "\n%b=== %s ===%b\n" "\033[1;34m" "$title" "\033[0m" >&2
            printf "%s\n\n" "$prompt" >&2
            for ((i=0; i<${#tags[@]}; i++)); do
                printf "  %b%2d)%b [%s] %s\n" "\033[1;32m" "$((i + 1))" "\033[0m" "${tags[i]}" "${descs[i]}" >&2
            done
            printf "\nSelect option [1-%d or tag]: " "${#tags[@]}" >&2

            local choice
            if ! IFS= read -r choice; then
                return 1
            fi
            choice="$(echo "$choice" | tr -d '[:space:]')"
            if [ -z "$choice" ]; then
                return 1
            fi

            # Check if choice is a 1-based number
            if [[ "$choice" =~ ^[0-9]+$ ]]; then
                local idx=$(( choice - 1 ))
                if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#tags[@]}" ]; then
                    echo "${tags[idx]}"
                    return 0
                fi
            fi

            # Check if choice matches a tag directly
            for ((i=0; i<${#tags[@]}; i++)); do
                if [ "${tags[i],,}" = "${choice,,}" ]; then
                    echo "${tags[i]}"
                    return 0
                fi
            done

            return 1
            ;;
    esac
}

# gsv_ui_checklist(title, prompt, tag1, desc1, status1, tag2, desc2, status2, ...)
# Displays a multi-select checklist dialog. Outputs selected tags (newline-separated).
gsv_ui_checklist() {
    local title="${1:-Checklist}"
    local prompt="${2:-Select items:}"
    [ $# -ge 1 ] && shift
    [ $# -ge 1 ] && shift

    local tags=()
    local descs=()
    local statuses=()
    while [ $# -ge 3 ]; do
        tags+=("$1")
        descs+=("$2")
        local st="${3:-OFF}"
        case "${st,,}" in
            on|true|1) st="ON" ;;
            *) st="OFF" ;;
        esac
        statuses+=("$st")
        shift 3
    done

    if [ "${#tags[@]}" -eq 0 ]; then
        return 0
    fi

    local mode
    mode="$(gsv_ui_detect)"

    case "$mode" in
        zenity)
            local zargs=(--list --checklist --title="$title" --text="$prompt" --column="Select" --column="Tag" --column="Description" --print-column=2 --separator=$'\n' --height=450 --width=620)
            for ((i=0; i<${#tags[@]}; i++)); do
                local zstatus="FALSE"
                [ "${statuses[i]}" = "ON" ] && zstatus="TRUE"
                zargs+=("$zstatus" "${tags[i]}" "${descs[i]}")
            done
            local res
            res=$(zenity "${zargs[@]}" 2>/dev/null)
            local status=$?
            if [ $status -ne 0 ]; then
                return 1
            fi
            echo "$res"
            return 0
            ;;
        whiptail|dialog)
            local tool="$mode"
            local count=${#tags[@]}
            local list_h=$(( count + 2 ))
            [ "$list_h" -gt 15 ] && list_h=15
            local box_h=$(( list_h + 8 ))
            local targs=()
            for ((i=0; i<count; i++)); do
                targs+=("${tags[i]}" "${descs[i]}" "${statuses[i]}")
            done
            local res
            res=$("$tool" --title "$title" --separate-output --checklist "$prompt" "$box_h" 74 "$list_h" "${targs[@]}" 3>&1 1>&2 2>&3)
            local status=$?
            if [ $status -ne 0 ]; then
                return 1
            fi
            echo "$res"
            return 0
            ;;
        *)
            # cli
            printf "\n%b=== %s ===%b\n" "\033[1;34m" "$title" "\033[0m" >&2
            printf "%s\n\n" "$prompt" >&2
            for ((i=0; i<${#tags[@]}; i++)); do
                local mark=" "
                [ "${statuses[i]}" = "ON" ] && mark="X"
                printf "  [%s] %b%2d)%b %s (%s)\n" "$mark" "\033[1;32m" "$((i + 1))" "\033[0m" "${tags[i]}" "${descs[i]}" >&2
            done
            printf "\nEnter selection (numbers like 1,2 or 'all', 'none', Enter for defaults) [all/none/1-%d]: " "${#tags[@]}" >&2

            local input
            if ! IFS= read -r input; then
                for ((i=0; i<${#tags[@]}; i++)); do
                    if [ "${statuses[i]}" = "ON" ]; then
                        echo "${tags[i]}"
                    fi
                done
                return 0
            fi

            input="$(echo "$input" | tr -d ' ')"
            if [ -z "$input" ]; then
                for ((i=0; i<${#tags[@]}; i++)); do
                    if [ "${statuses[i]}" = "ON" ]; then
                        echo "${tags[i]}"
                    fi
                done
                return 0
            fi

            if [ "${input,,}" = "all" ]; then
                for ((i=0; i<${#tags[@]}; i++)); do
                    echo "${tags[i]}"
                done
                return 0
            fi

            if [ "${input,,}" = "none" ]; then
                return 0
            fi

            IFS=',' read -ra parts <<< "$input"
            for p in "${parts[@]}"; do
                if [[ "$p" =~ ^[0-9]+$ ]]; then
                    local idx=$(( p - 1 ))
                    if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#tags[@]}" ]; then
                        echo "${tags[idx]}"
                    fi
                else
                    for ((i=0; i<${#tags[@]}; i++)); do
                        if [ "${tags[i],,}" = "${p,,}" ]; then
                            echo "${tags[i]}"
                            break
                        fi
                    done
                fi
            done
            return 0
            ;;
    esac
}

# ==============================================================================
# Doctor & Diagnostics
# ==============================================================================

# gsv_run_doctor([output_file])
# Inspects tools, directories, permissions, scan database and vault health.
# Generates a detailed diagnostic report. Returns 0 if healthy, 1 if critical error.
gsv_run_doctor() {
    local out_file="${1:-}"
    gsv_init_env

    local vault_path
    vault_path="$(gsv_resolve_vault_path)"
    local config_dir="${GSV_CONFIG_DIR:-$GSV_ROOT/config}"

    local buf=""
    _doc_line() {
        buf+="$*\n"
    }

    _doc_line "============================================================"
    _doc_line " GameSaveVault Health Check & Diagnostics"
    _doc_line "============================================================"
    _doc_line "Date: $(date '+%Y-%m-%d %H:%M:%S')"
    _doc_line "OS: $(uname -s -r -m)"
    _doc_line "Shell: ${BASH_VERSION:-unknown}"
    _doc_line "Repo Root: ${GSV_ROOT:-unknown}"
    _doc_line "Config Dir: $config_dir"
    _doc_line ""

    local critical_ok=1

    # Check JSON processing tools
    _doc_line "--- Core Dependencies ---"
    if command -v jq >/dev/null 2>&1; then
        local jq_ver
        jq_ver="$(jq --version 2>/dev/null || echo "installed")"
        _doc_line "  [OK] jq: $jq_ver ($(command -v jq))"
    else
        _doc_line "  [WARN] jq: NOT found (python3 fallback required)"
    fi

    if command -v python3 >/dev/null 2>&1; then
        local py_ver
        py_ver="$(python3 --version 2>/dev/null || echo "installed")"
        _doc_line "  [OK] python3: $py_ver ($(command -v python3))"
    else
        _doc_line "  [WARN] python3: NOT found"
    fi

    if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
        _doc_line "  [ERROR] Neither jq nor python3 is available! JSON processing will fail."
        critical_ok=0
    fi

    # Check rsync file copy engine
    if command -v rsync >/dev/null 2>&1; then
        local rsync_ver
        rsync_ver="$(rsync --version 2>/dev/null | head -n 1)"
        _doc_line "  [OK] rsync: $rsync_ver ($(command -v rsync))"
    else
        _doc_line "  [WARN] rsync: NOT found (fallback to standard cp)"
    fi

    if command -v tar >/dev/null 2>&1; then
        _doc_line "  [OK] tar: $(command -v tar)"
    else
        _doc_line "  [INFO] tar: NOT found"
    fi
    _doc_line ""

    # Check UI Tools
    _doc_line "--- UI / TUI Frontend Tools ---"
    if command -v zenity >/dev/null 2>&1; then
        _doc_line "  [OK] zenity: $(command -v zenity) (GUI supported)"
    else
        _doc_line "  [INFO] zenity: NOT found (GUI mode unavailable)"
    fi

    if command -v whiptail >/dev/null 2>&1; then
        _doc_line "  [OK] whiptail: $(command -v whiptail) (TUI supported)"
    elif command -v dialog >/dev/null 2>&1; then
        _doc_line "  [OK] dialog: $(command -v dialog) (TUI supported)"
    else
        _doc_line "  [INFO] whiptail/dialog: NOT found (TUI mode unavailable)"
    fi

    local current_mode
    current_mode="$(gsv_ui_detect)"
    _doc_line "  Current Active UI Mode: $current_mode"
    _doc_line ""

    # Check Vault and Storage
    _doc_line "--- Storage & Permissions ---"
    _doc_line "  Vault Path: $vault_path"
    if [ -d "$vault_path" ]; then
        if [ -w "$vault_path" ]; then
            _doc_line "  Vault Status: [OK] Directory exists and is writable"
        else
            _doc_line "  Vault Status: [ERROR] Directory exists but is NOT writable"
            critical_ok=0
        fi
    else
        if mkdir -p "$vault_path" 2>/dev/null; then
            _doc_line "  Vault Status: [OK] Directory created and writable"
        else
            _doc_line "  Vault Status: [ERROR] Directory cannot be created"
            critical_ok=0
        fi
    fi

    # Disk space
    if [ -d "$vault_path" ]; then
        local disk_info
        disk_info="$(df -h "$vault_path" 2>/dev/null | awk 'NR==2 { printf "Available: %s / Total: %s (%s used)", $4, $2, $5 }')"
        _doc_line "  Disk Space: $disk_info"
    fi
    _doc_line ""

    # Check Database and Snapshots
    _doc_line "--- Database & Snapshots ---"
    local db_file="$config_dir/scan-database.json"
    if [ -f "$db_file" ]; then
        local loc_count
        loc_count="$(_gsv_ui_get_game_count "$db_file")"
        _doc_line "  Scan Database: [OK] Found ($loc_count games tracked)"
    else
        _doc_line "  Scan Database: [INFO] Not initialized yet (run scan to create)"
    fi

    local snap_dir="$vault_path/snapshots"
    if [ -d "$snap_dir" ]; then
        local snap_count
        snap_count="$(find "$snap_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
        _doc_line "  Snapshots in Vault: $snap_count"
    else
        _doc_line "  Snapshots in Vault: 0"
    fi
    _doc_line ""

    _doc_line "============================================================"
    if [ "$critical_ok" -eq 1 ]; then
        _doc_line " Overall Status: HEALTHY"
    else
        _doc_line " Overall Status: DEGRADED / CONFIGURATION ISSUES FOUND"
    fi
    _doc_line "============================================================"

    # Write output to requested file
    if [ -n "$out_file" ]; then
        mkdir -p "$(dirname "$out_file")" 2>/dev/null || true
        printf "%b" "$buf" > "$out_file"
    fi

    # Log to vault log directory if writable
    if [ -d "$vault_path/logs" ] || mkdir -p "$vault_path/logs" 2>/dev/null; then
        printf "%b" "$buf" > "$vault_path/logs/health-report.txt" 2>/dev/null || true
    fi

    # Output to stdout if not writing to file
    if [ -z "$out_file" ]; then
        printf "%b" "$buf"
    fi

    if [ "$critical_ok" -eq 1 ]; then
        return 0
    else
        return 1
    fi
}

# ==============================================================================
# Interactive Dashboard Actions
# ==============================================================================

_gsv_ui_run_backup_for_games() {
    local locations="$1"
    local selected_games="$2"
    local vault_path
    vault_path="$(gsv_resolve_vault_path)"

    local is_dry=0
    if gsv_ui_confirm "Dry Run" "Perform a dry-run (simulation without copying files)?"; then
        is_dry=1
    fi

    local label
    label="$(gsv_ui_input "Snapshot Label" "Enter a label for this snapshot:" "manual-backup")"
    [ -z "$label" ] && label="manual-backup"

    # Filter locations JSON to selected games
    local filtered_locations="[]"
    local selected_json
    if command -v jq >/dev/null 2>&1; then
        selected_json="$(printf '%s\n' "$selected_games" | jq -R . | jq -s . 2>/dev/null)"
        filtered_locations=$(echo "$locations" | jq --argjson sel "$selected_json" '[.[] | select((.GameName // .Game // .GameId // "") as $g | $sel | index($g))]' 2>/dev/null || echo "[]")
    elif command -v python3 >/dev/null 2>&1; then
        filtered_locations=$(python3 -c '
import sys, json
try:
    locs = json.loads(sys.argv[1])
    sel = set(line.strip() for line in sys.argv[2].splitlines() if line.strip())
    filtered = [loc for loc in locs if (loc.get("GameName") or loc.get("Game") or loc.get("GameId")) in sel]
    print(json.dumps(filtered))
except Exception:
    print("[]")
' "$locations" "$selected_games" 2>/dev/null || echo "[]")
    fi

    gsv_create_snapshot "$filtered_locations" "$is_dry" "$label" "$vault_path"
    local status=$?
    if [ $status -eq 0 ]; then
        if [ "$is_dry" -eq 1 ]; then
            gsv_ui_message "Backup Dry Run Complete" "Dry run simulation completed successfully.\nNo files were copied." "info"
        else
            gsv_ui_message "Backup Complete" "Snapshot created successfully with label '$label'." "info"
        fi
    else
        gsv_ui_message "Backup Failed" "Failed to create snapshot. Check logs for details." "error"
    fi
}

# ==============================================================================
# Timer Helpers for Scan Operations
# ==============================================================================

_gsv_ui_now() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import time; print(f"{time.time():.4f}")' 2>/dev/null || date +%s
    else
        date +%s
    fi
}

_gsv_ui_elapsed() {
    local t_start="${1:-0}"
    local t_end="${2:-0}"
    if command -v python3 >/dev/null 2>&1; then
        python3 -c '
import sys
try:
    s = float(sys.argv[1])
    e = float(sys.argv[2])
    diff = max(0.0, e - s)
    print(f"{diff:.1f}s")
except Exception:
    print("0.0s")
' "$t_start" "$t_end" 2>/dev/null || echo "$(( t_end - t_start ))s"
    else
        local diff=$(( t_end - t_start ))
        [ "$diff" -lt 0 ] && diff=0
        echo "${diff}s"
    fi
}

_gsv_ui_action_scan_all() {
    local mode
    mode="$(gsv_ui_detect)"
    local tmp_scan
    tmp_scan="$(mktemp /tmp/gsv-scan.XXXXXX)"
    local start_time
    start_time="$(_gsv_ui_now)"

    if [ "$mode" = "zenity" ]; then
        (
            gsv_scan_all > "$tmp_scan" 2>/dev/null
        ) &
        local scan_pid=$!
        while kill -0 "$scan_pid" 2>/dev/null; do
            sleep 0.1
            echo "# Scanning Steam Proton, Native games, Wine/Lutris prefixes, and Emulators..."
        done | zenity --progress --pulsate --title="Scanning Game Saves" \
                      --text="Scanning Steam Proton prefixes, native Linux games, Wine prefixes, and emulators...\nPlease wait..." \
                      --auto-close --no-cancel 2>/dev/null || true
        wait "$scan_pid" 2>/dev/null || true
    elif [ "$mode" = "whiptail" ] || [ "$mode" = "dialog" ]; then
        whiptail --infobox "Scanning Steam Proton prefixes, native Linux games, Wine prefixes, and emulators...\nPlease wait..." 8 68 2>/dev/null || true
        gsv_scan_all > "$tmp_scan" 2>/dev/null
    else
        echo -e "\033[0;34m[*] Scanning for game saves (Proton, native games, Wine, emulators)...\033[0m"
        gsv_scan_all > "$tmp_scan" 2>/dev/null
    fi

    local end_time
    end_time="$(_gsv_ui_now)"
    local elapsed
    elapsed="$(_gsv_ui_elapsed "$start_time" "$end_time")"
    local scan_results
    scan_results="$(cat "$tmp_scan" 2>/dev/null || echo "[]")"
    rm -f "$tmp_scan" 2>/dev/null || true

    local count=0
    if command -v jq >/dev/null 2>&1; then
        count="$(echo "$scan_results" | jq '. | length' 2>/dev/null || echo 0)"
    elif command -v python3 >/dev/null 2>&1; then
        count="$(python3 -c 'import sys, json; print(len(json.loads(sys.argv[1])))' "$scan_results" 2>/dev/null || echo 0)"
    fi
    gsv_update_scan_database "$scan_results"

    if [ "$mode" = "cli" ]; then
        echo -e "\033[0;32m[✓] Scan completed in $elapsed! Discovered $count save location(s).\033[0m"
    fi

    if [ "$count" -eq 0 ]; then
        gsv_ui_message "Scan Complete ($elapsed)" "Scan finished in $elapsed.\nNo game saves detected on standard paths.\nUse 'Scan Custom Folders' to scan a specific games directory." "info"
        return 0
    fi

    local checklist_args=()
    local tool="${GSV_JSON_TOOL:-jq}"
    if [ "$tool" = "jq" ] && command -v jq >/dev/null 2>&1; then
        while IFS=$'\t' read -r name src p; do
            if [ -n "$name" ] && [ "$name" != "null" ]; then
                checklist_args+=("$name" "[$src] $p" "ON")
            fi
        done < <(echo "$scan_results" | jq -r '.[] | "\((.GameName // .Game // .GameId // "Unknown"))\t\((.Source // "Local"))\t\((.ResolvedPath // .AbsolutePath // .OriginalPath // ""))"' 2>/dev/null)
    elif command -v python3 >/dev/null 2>&1; then
        while IFS=$'\t' read -r name src p; do
            if [ -n "$name" ] && [ "$name" != "null" ]; then
                checklist_args+=("$name" "[$src] $p" "ON")
            fi
        done < <(python3 -c '
import sys, json
try:
    data = json.loads(sys.argv[1])
    for item in data:
        gn = item.get("GameName") or item.get("Game") or item.get("GameId") or "Unknown"
        src = item.get("Source") or "Local"
        op = item.get("ResolvedPath") or item.get("AbsolutePath") or item.get("OriginalPath") or ""
        print(f"{gn}\t{src}\t{op}")
except Exception:
    pass
' "$scan_results" 2>/dev/null)
    fi

    local chosen_games
    chosen_games="$(gsv_ui_checklist "Discovered Games ($count found in $elapsed)" "Discovered $count save location(s) in $elapsed. Review games and select saves to back up now (or cancel to keep in database):" "${checklist_args[@]}")"
    if [ $? -eq 0 ] && [ -n "$chosen_games" ]; then
        if gsv_ui_confirm "Backup Selected Games" "Would you like to back up the selected games now?"; then
            _gsv_ui_run_backup_for_games "$scan_results" "$chosen_games"
        fi
    fi
}

_gsv_ui_action_scan_custom() {
    local folder
    folder="$(gsv_ui_dir_picker "Select Folder to Deep Scan" "$HOME")"
    if [ $? -ne 0 ] || [ -z "$folder" ]; then
        return 0
    fi
    if [ ! -d "$folder" ]; then
        gsv_ui_message "Error" "Folder '$folder' does not exist." "error"
        return 0
    fi

    local mode
    mode="$(gsv_ui_detect)"
    local tmp_scan
    tmp_scan="$(mktemp /tmp/gsv-scan-custom.XXXXXX)"
    local start_time
    start_time="$(_gsv_ui_now)"

    if [ "$mode" = "zenity" ]; then
        (
            gsv_deep_scan_folder "$folder" > "$tmp_scan" 2>/dev/null
        ) &
        local scan_pid=$!
        while kill -0 "$scan_pid" 2>/dev/null; do
            sleep 0.1
            echo "# Deep scanning '$folder' for game saves..."
        done | zenity --progress --pulsate --title="Deep Scanning Folder" \
                      --text="Deep scanning '$folder' for game saves...\nPlease wait..." \
                      --auto-close --no-cancel 2>/dev/null || true
        wait "$scan_pid" 2>/dev/null || true
    elif [ "$mode" = "whiptail" ] || [ "$mode" = "dialog" ]; then
        whiptail --infobox "Deep scanning '$folder' for game saves...\nPlease wait..." 8 68 2>/dev/null || true
        gsv_deep_scan_folder "$folder" > "$tmp_scan" 2>/dev/null
    else
        echo -e "\033[0;34m[*] Deep scanning '$folder' for game saves...\033[0m"
        gsv_deep_scan_folder "$folder" > "$tmp_scan" 2>/dev/null
    fi

    local end_time
    end_time="$(_gsv_ui_now)"
    local elapsed
    elapsed="$(_gsv_ui_elapsed "$start_time" "$end_time")"
    local results
    results="$(cat "$tmp_scan" 2>/dev/null || echo "[]")"
    rm -f "$tmp_scan" 2>/dev/null || true

    local count=0
    if command -v jq >/dev/null 2>&1; then
        count="$(echo "$results" | jq '. | length' 2>/dev/null || echo 0)"
    elif command -v python3 >/dev/null 2>&1; then
        count="$(python3 -c 'import sys, json; print(len(json.loads(sys.argv[1])))' "$results" 2>/dev/null || echo 0)"
    fi

    if [ "$mode" = "cli" ]; then
        echo -e "\033[0;32m[✓] Deep scan completed in $elapsed! Discovered $count save location(s).\033[0m"
    fi

    if [ "$count" -gt 0 ]; then
        gsv_update_scan_database "$results"
        local checklist_args=()
        if command -v jq >/dev/null 2>&1; then
            while IFS=$'\t' read -r name p; do
                [ -n "$name" ] && [ "$name" != "null" ] && checklist_args+=("$name" "$p" "ON")
            done < <(echo "$results" | jq -r '.[] | "\((.GameName // .Game // .GameId // "Unknown"))\t\((.ResolvedPath // .AbsolutePath // ""))"' 2>/dev/null)
        elif command -v python3 >/dev/null 2>&1; then
            while IFS=$'\t' read -r name p; do
                [ -n "$name" ] && [ "$name" != "null" ] && checklist_args+=("$name" "$p" "ON")
            done < <(python3 -c '
import sys, json
try:
    for item in json.loads(sys.argv[1]):
        gn = item.get("GameName") or item.get("Game") or item.get("GameId") or "Unknown"
        op = item.get("ResolvedPath") or item.get("AbsolutePath") or ""
        print(f"{gn}\t{op}")
except Exception:
    pass
' "$results" 2>/dev/null)
        fi

        local chosen_games
        chosen_games="$(gsv_ui_checklist "Discovered Saves in Folder ($count found in $elapsed)" "Found $count save location(s) in '$folder' in $elapsed. Select games to back up now (or cancel to keep in database):" "${checklist_args[@]}")"
        if [ $? -eq 0 ] && [ -n "$chosen_games" ]; then
            if gsv_ui_confirm "Backup Now" "Would you like to back up the selected games now?"; then
                _gsv_ui_run_backup_for_games "$results" "$chosen_games"
            fi
        fi
    else
        gsv_ui_message "Scan Complete ($elapsed)" "Scan finished in $elapsed.\nNo game save files detected in '$folder'." "warning"
    fi
}

_gsv_ui_action_view_games() {
    local db_file="${GSV_CONFIG_DIR:-$GSV_ROOT/config}/scan-database.json"
    if [ ! -f "$db_file" ]; then
        if gsv_ui_confirm "No Scan Database" "No scan database exists yet. Would you like to scan for installed games now?"; then
            _gsv_ui_action_scan_all
        fi
        return 0
    fi

    local locations
    locations="$(_gsv_parse_locations_to_array "$db_file")"
    local count=0
    if command -v jq >/dev/null 2>&1; then
        count="$(echo "$locations" | jq '. | length' 2>/dev/null || echo 0)"
    elif command -v python3 >/dev/null 2>&1; then
        count="$(python3 -c 'import sys, json; print(len(json.loads(sys.argv[1])))' "$locations" 2>/dev/null || echo 0)"
    fi

    if [ "$count" -eq 0 ]; then
        if gsv_ui_confirm "Empty Database" "No game saves currently in database. Would you like to scan for installed games now?"; then
            _gsv_ui_action_scan_all
        fi
        return 0
    fi

    local checklist_args=()
    local tool="${GSV_JSON_TOOL:-jq}"
    if [ "$tool" = "jq" ] && command -v jq >/dev/null 2>&1; then
        while IFS=$'\t' read -r name src p; do
            if [ -n "$name" ] && [ "$name" != "null" ]; then
                checklist_args+=("$name" "[$src] $p" "ON")
            fi
        done < <(echo "$locations" | jq -r '.[] | "\((.GameName // .Game // .GameId // "Unknown"))\t\((.Source // "Local"))\t\((.ResolvedPath // .AbsolutePath // .OriginalPath // ""))"' 2>/dev/null)
    elif command -v python3 >/dev/null 2>&1; then
        while IFS=$'\t' read -r name src p; do
            if [ -n "$name" ] && [ "$name" != "null" ]; then
                checklist_args+=("$name" "[$src] $p" "ON")
            fi
        done < <(python3 -c '
import sys, json
try:
    data = json.loads(sys.argv[1])
    for item in data:
        gn = item.get("GameName") or item.get("Game") or item.get("GameId") or "Unknown"
        src = item.get("Source") or "Local"
        op = item.get("ResolvedPath") or item.get("AbsolutePath") or item.get("OriginalPath") or ""
        print(f"{gn}\t{src}\t{op}")
except Exception:
    pass
' "$locations" 2>/dev/null)
    fi

    local chosen_games
    chosen_games="$(gsv_ui_checklist "Tracked Games ($count total)" "Currently tracked game saves. Select games to back up (or cancel to return):" "${checklist_args[@]}")"
    if [ $? -eq 0 ] && [ -n "$chosen_games" ]; then
        if gsv_ui_confirm "Backup Selected Games" "Would you like to back up the selected games now?"; then
            _gsv_ui_run_backup_for_games "$locations" "$chosen_games"
        fi
    fi
}

_gsv_ui_action_backup() {
    local vault_path
    vault_path="$(gsv_resolve_vault_path)"

    local db_file="${GSV_CONFIG_DIR:-$GSV_ROOT/config}/scan-database.json"
    if [ ! -f "$db_file" ]; then
        if gsv_ui_confirm "No Scan Database" "No games recorded yet. Would you like to scan for installed games now?"; then
            _gsv_ui_action_scan_all
            return 0
        fi
        return 0
    fi

    local locations
    locations="$(_gsv_parse_locations_to_array "$db_file")"
    local count=0
    if command -v jq >/dev/null 2>&1; then
        count="$(echo "$locations" | jq '. | length' 2>/dev/null || echo 0)"
    elif command -v python3 >/dev/null 2>&1; then
        count="$(python3 -c 'import sys, json; print(len(json.loads(sys.argv[1])))' "$locations" 2>/dev/null || echo 0)"
    fi

    if [ "$count" -eq 0 ]; then
        if gsv_ui_confirm "Empty Database" "No game saves currently in database. Would you like to scan for installed games now?"; then
            _gsv_ui_action_scan_all
            return 0
        fi
        return 0
    fi

    local checklist_args=()
    local tool="${GSV_JSON_TOOL:-jq}"
    if [ "$tool" = "jq" ] && command -v jq >/dev/null 2>&1; then
        while IFS=$'\t' read -r name src p; do
            if [ -n "$name" ] && [ "$name" != "null" ]; then
                checklist_args+=("$name" "[$src] $p" "ON")
            fi
        done < <(echo "$locations" | jq -r '.[] | "\((.GameName // .Game // .GameId // "Unknown"))\t\((.Source // "Local"))\t\((.ResolvedPath // .AbsolutePath // .OriginalPath // ""))"' 2>/dev/null)
    elif command -v python3 >/dev/null 2>&1; then
        while IFS=$'\t' read -r name src p; do
            if [ -n "$name" ] && [ "$name" != "null" ]; then
                checklist_args+=("$name" "[$src] $p" "ON")
            fi
        done < <(python3 -c '
import sys, json
try:
    data = json.loads(sys.argv[1])
    for item in data:
        gn = item.get("GameName") or item.get("Game") or item.get("GameId") or "Unknown"
        src = item.get("Source") or "Local"
        op = item.get("ResolvedPath") or item.get("AbsolutePath") or item.get("OriginalPath") or ""
        print(f"{gn}\t{src}\t{op}")
except Exception:
    pass
' "$locations" 2>/dev/null)
    fi

    if [ "${#checklist_args[@]}" -eq 0 ]; then
        gsv_ui_message "Error" "No games could be loaded for backup." "error"
        return 0
    fi

    local selected_games
    selected_games="$(gsv_ui_checklist "Backup Game Saves" "Select games to include in snapshot ($count available):" "${checklist_args[@]}")"
    if [ $? -ne 0 ] || [ -z "$selected_games" ]; then
        return 0
    fi

    _gsv_ui_run_backup_for_games "$locations" "$selected_games"
}

_gsv_ui_action_restore() {
    local vault_path
    vault_path="$(gsv_resolve_vault_path)"

    local snaps_json
    snaps_json="$(gsv_list_snapshots "$vault_path" --json)"
    local count=0
    local tool="${GSV_JSON_TOOL:-jq}"
    if [ "$tool" = "jq" ] && command -v jq >/dev/null 2>&1; then
        count="$(echo "$snaps_json" | jq '. | length' 2>/dev/null || echo 0)"
    elif command -v python3 >/dev/null 2>&1; then
        count="$(python3 -c 'import sys, json; print(len(json.loads(sys.argv[1])))' "$snaps_json" 2>/dev/null || echo 0)"
    fi

    if [ "$count" -eq 0 ]; then
        gsv_ui_message "No Snapshots" "No snapshots found in vault." "warning"
        return 0
    fi

    local menu_items=()
    if [ "$tool" = "jq" ] && command -v jq >/dev/null 2>&1; then
        while IFS=$'\t' read -r sid lbl dt gcount; do
            if [ -n "$sid" ]; then
                menu_items+=("$sid" "[$dt] $lbl ($gcount games)")
            fi
        done < <(echo "$snaps_json" | jq -r '.[] | "\(.Id // .SnapshotId)\t\(.Label // "no-label")\t\(.CreatedAt // .CreatedUtc // "")\t\(.TotalGames // .EntryCount // (.Games | length) // 0)"' 2>/dev/null)
    elif command -v python3 >/dev/null 2>&1; then
        while IFS=$'\t' read -r sid lbl dt gcount; do
            if [ -n "$sid" ]; then
                menu_items+=("$sid" "[$dt] $lbl ($gcount games)")
            fi
        done < <(python3 -c '
import sys, json
try:
    for s in json.loads(sys.argv[1]):
        sid = s.get("Id") or s.get("SnapshotId") or ""
        lbl = s.get("Label") or "no-label"
        dt = s.get("CreatedAt") or s.get("CreatedUtc") or ""
        tg = s.get("TotalGames")
        if tg is None:
            tg = s.get("EntryCount")
        if tg is None:
            tg = len(s.get("Games", []))
        print(f"{sid}\t{lbl}\t{dt}\t{tg}")
except Exception:
    pass
' "$snaps_json" 2>/dev/null)
    fi

    local selected_snap
    selected_snap="$(gsv_ui_menu "Select Snapshot" "Choose snapshot to restore:" "${menu_items[@]}")"
    if [ $? -ne 0 ] || [ -z "$selected_snap" ]; then
        return 0
    fi

    local snap_dir
    snap_dir="$(gsv_resolve_snapshot_dir "$selected_snap" "$vault_path")"
    local manifest="$snap_dir/manifest.json"
    if [ ! -f "$manifest" ]; then
        gsv_ui_message "Error" "Manifest not found for snapshot '$selected_snap'." "error"
        return 0
    fi

    local game_checklist=()
    if [ "$tool" = "jq" ] && command -v jq >/dev/null 2>&1; then
        while IFS=$'\t' read -r gname orig; do
            if [ -n "$gname" ]; then
                game_checklist+=("$gname" "$orig" "ON")
            fi
        done < <(jq -r '(.Entries // .Games // [])[] | "\((.Game // .GameName // .GameId // "Unknown"))\t\(.OriginalPath // .ResolvedPath // .AbsolutePath // "")"' "$manifest" 2>/dev/null)
    elif command -v python3 >/dev/null 2>&1; then
        while IFS=$'\t' read -r gname orig; do
            if [ -n "$gname" ]; then
                game_checklist+=("$gname" "$orig" "ON")
            fi
        done < <(python3 -c '
import sys, json
try:
    with open(sys.argv[1]) as f:
        mf = json.load(f)
    entries = mf.get("Entries") or mf.get("Games") or []
    for g in entries:
        gn = g.get("Game") or g.get("GameName") or g.get("GameId") or "Unknown"
        op = g.get("OriginalPath") or g.get("ResolvedPath") or g.get("AbsolutePath") or ""
        print(f"{gn}\t{op}")
except Exception:
    pass
' "$manifest" 2>/dev/null)
    fi

    local chosen_games
    chosen_games="$(gsv_ui_checklist "Select Games to Restore" "Select games to restore:" "${game_checklist[@]}")"
    if [ $? -ne 0 ] || [ -z "$chosen_games" ]; then
        return 0
    fi

    local custom_root
    custom_root="$(gsv_ui_input "Restore Root" "Custom restore root directory (leave empty to restore to original locations):" "")"

    local is_dry=0
    if gsv_ui_confirm "Dry Run" "Perform a dry-run (simulation without restoring files)?"; then
        is_dry=1
    fi

    local games_filter
    games_filter="$(echo "$chosen_games" | paste -sd, -)"

    gsv_restore_snapshot "$selected_snap" "$games_filter" "$is_dry" "$custom_root" "$vault_path"
    local status=$?
    if [ $status -eq 0 ]; then
        if [ "$is_dry" -eq 1 ]; then
            gsv_ui_message "Restore Dry Run Complete" "Dry run simulation completed successfully.\nNo files were modified." "info"
        else
            gsv_ui_message "Restore Complete" "Selected games restored successfully from snapshot '$selected_snap'." "info"
        fi
    else
        gsv_ui_message "Restore Failed" "Restore operation failed. Check logs for details." "error"
    fi
}

_gsv_ui_action_browse_snapshots() {
    local vault_path
    vault_path="$(gsv_resolve_vault_path)"

    local snaps_json
    snaps_json="$(gsv_list_snapshots "$vault_path" --json)"
    local count=0
    local tool="${GSV_JSON_TOOL:-jq}"
    local tool="${GSV_JSON_TOOL:-jq}"
    if [ "$tool" = "jq" ] && command -v jq >/dev/null 2>&1; then
        count="$(echo "$snaps_json" | jq '. | length' 2>/dev/null || echo 0)"
    elif command -v python3 >/dev/null 2>&1; then
        count="$(python3 -c 'import sys, json; print(len(json.loads(sys.argv[1])))' "$snaps_json" 2>/dev/null || echo 0)"
    fi

    if [ "$count" -eq 0 ]; then
        gsv_ui_message "No Snapshots" "No snapshots found in vault." "info"
        return 0
    fi

    local menu_items=()
    if [ "$tool" = "jq" ] && command -v jq >/dev/null 2>&1; then
        while IFS=$'\t' read -r sid lbl dt gcount; do
            if [ -n "$sid" ]; then
                menu_items+=("$sid" "[$dt] $lbl ($gcount games)")
            fi
        done < <(echo "$snaps_json" | jq -r '.[] | "\(.Id // .SnapshotId)\t\(.Label // "no-label")\t\(.CreatedAt // .CreatedUtc // "")\t\(.TotalGames // .EntryCount // (.Games | length) // 0)"' 2>/dev/null)
    elif command -v python3 >/dev/null 2>&1; then
        while IFS=$'\t' read -r sid lbl dt gcount; do
            if [ -n "$sid" ]; then
                menu_items+=("$sid" "[$dt] $lbl ($gcount games)")
            fi
        done < <(python3 -c '
import sys, json
try:
    for s in json.loads(sys.argv[1]):
        sid = s.get("Id") or s.get("SnapshotId") or ""
        lbl = s.get("Label") or "no-label"
        dt = s.get("CreatedAt") or s.get("CreatedUtc") or ""
        tg = s.get("TotalGames")
        if tg is None:
            tg = s.get("EntryCount")
        if tg is None:
            tg = len(s.get("Games", []))
        print(f"{sid}\t{lbl}\t{dt}\t{tg}")
except Exception:
    pass
' "$snaps_json" 2>/dev/null)
    fi

    local sid
    sid="$(gsv_ui_menu "Browse Snapshots" "Select snapshot to inspect details:" "${menu_items[@]}")"
    if [ $? -ne 0 ] || [ -z "$sid" ]; then
        return 0
    fi

    local vault_path
    vault_path="$(gsv_resolve_vault_path)"
    local snap_dir
    snap_dir="$(gsv_resolve_snapshot_dir "$sid" "$vault_path")"
    local mf="$snap_dir/manifest.json"

    local details="Snapshot: $sid\n"
    if [ -f "$mf" ]; then
        if [ "$tool" = "jq" ] && command -v jq >/dev/null 2>&1; then
            details+="$(jq -r '"Label: \(.Label // "none")\nCreated: \(.CreatedAt // .CreatedUtc // "unknown")\nTotal Files: \(.TotalFiles // 0)\nTotal Size: \(.TotalBytes // .TotalSizeBytes // 0) bytes\nGames:\n" + ([(.Entries // .Games // [])[] | (.Game // .GameName // .GameId // "Unknown")] | map("  - " + .) | join("\n"))' "$mf" 2>/dev/null)"
        elif command -v python3 >/dev/null 2>&1; then
            details+="$(python3 -c '
import sys, json
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    tb = d.get("TotalBytes")
    if tb is None:
        tb = d.get("TotalSizeBytes", 0)
    entries = d.get("Entries") or d.get("Games") or []
    lbl = d.get("Label") or "none"
    crt = d.get("CreatedAt") or d.get("CreatedUtc") or "unknown"
    tf = d.get("TotalFiles", 0)
    print(f"Label: {lbl}")
    print(f"Created: {crt}")
    print(f"Total Files: {tf}")
    print(f"Total Size: {tb} bytes")
    print("Games:")
    for g in entries:
        gn = g.get("Game") or g.get("GameName") or g.get("GameId") or "Unknown"
        print(f"  - {gn}")
except Exception as e:
    print(str(e))
' "$mf" 2>/dev/null)"
        fi
    fi
    gsv_ui_message "Snapshot Details: $sid" "$details" "info"
}

_gsv_ui_action_configure_vault() {
    local current_vault
    current_vault="$(gsv_resolve_vault_path)"
    local new_vault
    new_vault="$(gsv_ui_dir_picker "Configure Vault Directory" "$current_vault")"
    if [ $? -ne 0 ] || [ -z "$new_vault" ] || [ "$new_vault" = "$current_vault" ]; then
        return 0
    fi

    if gsv_ui_confirm "Confirm Change" "Set vault directory to:\n$new_vault\nAre you sure?"; then
        mkdir -p "$new_vault" 2>/dev/null || true
        local config_file="${GSV_CONFIG_DIR:-$GSV_ROOT/config}/settings.json"
        gsv_json_set "$config_file" ".BackupRoot" "\"$new_vault\""
        GSV_VAULT_PATH="$new_vault"
        export GSV_VAULT_PATH
        gsv_ui_message "Vault Configured" "Vault location updated to:\n$new_vault" "info"
    fi
}

_gsv_ui_action_doctor() {
    local report_tmp
    report_tmp="$(mktemp "${TMPDIR:-/tmp}/gsv-doctor.XXXXXX")"
    gsv_run_doctor "$report_tmp"
    local report
    report="$(cat "$report_tmp")"
    rm -f "$report_tmp"
    gsv_ui_message "System Health Report" "$report" "info"
}

# ==============================================================================
# Interactive Dashboard Main Loop
# ==============================================================================

# gsv_launch_dashboard()
# Launches the interactive GameSaveVault dashboard menu loop.
gsv_launch_dashboard() {
    gsv_init_env

    while true; do
        local vault_path
        vault_path="$(gsv_resolve_vault_path)"
        local db_file="${GSV_CONFIG_DIR:-$GSV_ROOT/config}/scan-database.json"
        local game_count=0
        if [ -f "$db_file" ]; then
            game_count="$(_gsv_ui_get_game_count "$db_file")"
            [[ ! "$game_count" =~ ^[0-9]+$ ]] && game_count=0
        fi

        local latest_snap="None"
        local snap_dir="$vault_path/snapshots"
        if [ -d "$snap_dir" ]; then
            local latest
            latest="$(find "$snap_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r | head -n 1)"
            if [ -n "$latest" ]; then
                latest_snap="$(basename "$latest")"
            fi
        fi

        local title="GameSaveVault Dashboard"
        local prompt="Vault: $vault_path | Tracked Games: $game_count | Last Snapshot: $latest_snap"

        local choice
        choice="$(gsv_ui_menu "$title" "$prompt" \
            "1" "Scan Installed Games & Prefixes" \
            "2" "Scan Custom Folders" \
            "3" "View Tracked Games & Save Locations" \
            "4" "Backup Saves" \
            "5" "Restore Saves" \
            "6" "Browse Snapshots" \
            "7" "Configure Vault Location" \
            "8" "Health Check / Doctor" \
            "9" "Exit")"
        local status=$?
        if [ $status -ne 0 ] || [ "$choice" = "9" ] || [ "${choice,,}" = "exit" ] || [ "${choice,,}" = "q" ] || [ "${choice,,}" = "quit" ]; then
            break
        fi

        case "$choice" in
            1) _gsv_ui_action_scan_all ;;
            2) _gsv_ui_action_scan_custom ;;
            3) _gsv_ui_action_view_games ;;
            4) _gsv_ui_action_backup ;;
            5) _gsv_ui_action_restore ;;
            6) _gsv_ui_action_browse_snapshots ;;
            7) _gsv_ui_action_configure_vault ;;
            8) _gsv_ui_action_doctor ;;
            *)
                # Unknown choice, loop again
                ;;
        esac
    done

    return 0
}
