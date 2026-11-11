#!/usr/bin/env bash
# ==============================================================================
# linux/gamevault.sh
# Primary CLI dispatcher and GUI launcher for GameSaveVault on Linux.
# ==============================================================================

set -uo pipefail

# ------------------------------------------------------------------------------
# Environment Resolution & Module Loading
# ------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export GSV_ROOT="${GSV_ROOT:-$REPO_ROOT}"
export GSV_LINUX_DIR="${GSV_LINUX_DIR:-$SCRIPT_DIR}"
export GSV_MODULES_DIR="${GSV_MODULES_DIR:-$SCRIPT_DIR/modules}"
export GSV_CONFIG_DIR="${GSV_CONFIG_DIR:-$GSV_ROOT/config}"
export GSV_DATA_DIR="${GSV_DATA_DIR:-$GSV_ROOT/data}"

# Source core modules
# shellcheck source=modules/common.sh
source "$GSV_MODULES_DIR/common.sh"
# shellcheck source=modules/scanner.sh
source "$GSV_MODULES_DIR/scanner.sh"
# shellcheck source=modules/vault.sh
source "$GSV_MODULES_DIR/vault.sh"
# shellcheck source=modules/ui.sh
source "$GSV_MODULES_DIR/ui.sh"

# Initialize environment
gsv_init_env

# ------------------------------------------------------------------------------
# Help Text
# ------------------------------------------------------------------------------
show_help() {
    cat <<'EOF'
GameSaveVault (Linux) - Game Save Discovery, Backup & Restore

Usage:
  gamevault.sh <command> [options]
  gamevault.sh [options]

Commands:
  scan                    Discover and list installed game save locations
  scan-folders            Deep scan custom folders and update scan-database.json
                            --dirs <path1:path2> (colon or comma separated)
  scan-db                 Display current scan database
  backup                  Create a backup snapshot
                            [--all] [--game <names>] [--label <label>]
                            [--dry-run] [--vault <path>]
  restore                 Restore game saves from snapshot
                            [--snapshot <id|latest>] [--all] [--game <names>]
                            [--restore-root <path>] [--dry-run] [--vault <path>]
  snapshots               List existing snapshots in vault
                            [--vault <path>] [--json]
  doctor                  Run dependency and permission diagnostics
  gui                     Launch interactive graphical or terminal dashboard
  help                    Show this help message

Options:
  -h, --help              Show help information
  --gui                   Force Zenity graphical interface mode
  --tui                   Force Whiptail / Dialog terminal interface mode
  --cli                   Force plain CLI mode
  --vault <path>          Override vault storage location
EOF
}

# ------------------------------------------------------------------------------
# Command Handlers
# ------------------------------------------------------------------------------

cmd_scan() {
    gsv_log_info "Scanning for installed games and save folders..."
    local results
    results="$(gsv_scan_all)"

    local count=0
    if [ "${GSV_JSON_TOOL:-}" = "jq" ] || command -v jq >/dev/null 2>&1; then
        count="$(echo "$results" | jq '. | length' 2>/dev/null || echo 0)"
    elif command -v python3 >/dev/null 2>&1; then
        count="$(python3 -c 'import sys, json; print(len(json.loads(sys.argv[1])))' "$results" 2>/dev/null || echo 0)"
    fi

    if [ "$count" -eq 0 ]; then
        echo "No game saves detected."
        return 0
    fi

    gsv_update_scan_database "$results" >/dev/null 2>&1 || true

    printf "%-30s %-18s %-7s %-10s %s\n" "GAME" "SOURCE" "FILES" "SIZE" "PATH"
    printf "%s\n" "------------------------------------------------------------------------------------------------"

    if command -v jq >/dev/null 2>&1; then
        echo "$results" | jq -r '.[] | [
            (.Game // .GameName // .GameId // "Unknown"),
            (.Source // .Origin // "Unknown"),
            ((.FileCount // 0) | tostring),
            ((.Bytes // 0) | tostring),
            (.ResolvedPath // .AbsolutePath // .Path // "")
        ] | @tsv' | while IFS=$'\t' read -r g s fc b p; do
            local sz
            sz="$(_gsv_format_size "$b")"
            printf "%-30.30s %-18.18s %-7s %-10s %s\n" "$g" "$s" "$fc" "$sz" "$p"
        done
    else
        python3 -c '
import sys, json
data = json.loads(sys.argv[1])
for item in data:
    g = item.get("Game") or item.get("GameName") or item.get("GameId") or "Unknown"
    s = item.get("Source") or item.get("Origin") or "Unknown"
    fc = str(item.get("FileCount") or 0)
    b = int(item.get("Bytes") or 0)
    p = item.get("ResolvedPath") or item.get("AbsolutePath") or item.get("Path") or ""
    print(f"{g}\t{s}\t{fc}\t{b}\t{p}")
' "$results" | while IFS=$'\t' read -r g s fc b p; do
            local sz
            sz="$(_gsv_format_size "$b")"
            printf "%-30.30s %-18.18s %-7s %-10s %s\n" "$g" "$s" "$fc" "$sz" "$p"
        done
    fi

    echo ""
    local db_path="${GSV_CONFIG_DIR:-$GSV_ROOT/config}/scan-database.json"
    echo "Discovered $count save location(s). Database updated: $db_path"
    return 0
}

cmd_scan_folders() {
    local dirs_arg=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --dirs)
                shift
                dirs_arg="${1:-}"
                ;;
            --dirs=*)
                dirs_arg="${1#*=}"
                ;;
            --dir)
                shift
                dirs_arg="${1:-}"
                ;;
            --dir=*)
                dirs_arg="${1#*=}"
                ;;
            *)
                if [ -z "$dirs_arg" ]; then
                    dirs_arg="$1"
                fi
                ;;
        esac
        shift
    done

    if [ -z "$dirs_arg" ]; then
        if [ -t 0 ]; then
            dirs_arg="$(gsv_ui_dir_picker "Select Folder to Deep Scan" "$HOME")"
            if [ -z "$dirs_arg" ]; then
                echo "No folder selected."
                return 0
            fi
        else
            echo "Error: No directories specified for scan-folders. Use --dirs <path1:path2>" >&2
            return 1
        fi
    fi

    local -a raw_paths=()
    IFS=':;, ' read -r -a raw_paths <<< "$dirs_arg"

    local -a valid_paths=()
    for p in "${raw_paths[@]}"; do
        p="${p/#\~/$HOME}"
        if [ -d "$p" ]; then
            valid_paths+=("$(cd "$p" && pwd)")
        else
            gsv_log_warn "Directory not found: $p"
        fi
    done

    if [ ${#valid_paths[@]} -eq 0 ]; then
        echo "Error: No valid directories found to scan in '$dirs_arg'." >&2
        return 1
    fi

    local combined_results="[]"
    local total_count=0

    for vp in "${valid_paths[@]}"; do
        echo "Deep scanning for game saves in: $vp ..."
        local res
        res="$(gsv_deep_scan_folder "$vp")"

        if command -v jq >/dev/null 2>&1; then
            combined_results="$(jq -s '.[0] + .[1] | unique_by(.ResolvedPath // .AbsolutePath)' <(echo "$combined_results") <(echo "$res") 2>/dev/null || echo "$combined_results")"
        else
            combined_results="$(python3 -c '
import sys, json
c = json.loads(sys.argv[1])
r = json.loads(sys.argv[2])
seen = set(x.get("ResolvedPath") or x.get("AbsolutePath") for x in c)
for item in r:
    key = item.get("ResolvedPath") or item.get("AbsolutePath")
    if key not in seen:
        c.append(item)
        seen.add(key)
print(json.dumps(c))
' "$combined_results" "$res" 2>/dev/null || echo "$combined_results")"
        fi
    done

    local roots_json
    if command -v jq >/dev/null 2>&1; then
        roots_json="$(printf '%s\n' "${valid_paths[@]}" | jq -R . | jq -s . 2>/dev/null || echo "[]")"
        total_count="$(echo "$combined_results" | jq '. | length' 2>/dev/null || echo 0)"
    else
        roots_json="$(python3 -c 'import sys, json; print(json.dumps(sys.argv[1:]))' "${valid_paths[@]}" 2>/dev/null || echo "[]")"
        total_count="$(python3 -c 'import sys, json; print(len(json.loads(sys.argv[1])))' "$combined_results" 2>/dev/null || echo 0)"
    fi

    gsv_update_scan_database "$combined_results" "$roots_json" >/dev/null 2>&1 || true

    echo "Found $total_count save location(s) across ${#valid_paths[@]} folder(s). Database updated."

    if [ "$total_count" -gt 0 ]; then
        printf "%-30s %-18s %-7s %-10s %s\n" "GAME" "SOURCE" "FILES" "SIZE" "PATH"
        printf "%s\n" "------------------------------------------------------------------------------------------------"
        if command -v jq >/dev/null 2>&1; then
            echo "$combined_results" | jq -r '.[] | [
                (.Game // .GameName // .GameId // "Unknown"),
                (.Source // .Origin // "Unknown"),
                ((.FileCount // 0) | tostring),
                ((.Bytes // 0) | tostring),
                (.ResolvedPath // .AbsolutePath // .Path // "")
            ] | @tsv' | while IFS=$'\t' read -r g s fc b p; do
                local sz
                sz="$(_gsv_format_size "$b")"
                printf "%-30.30s %-18.18s %-7s %-10s %s\n" "$g" "$s" "$fc" "$sz" "$p"
            done
        else
            python3 -c '
import sys, json
for item in json.loads(sys.argv[1]):
    g = item.get("Game") or item.get("GameName") or item.get("GameId") or "Unknown"
    s = item.get("Source") or item.get("Origin") or "Unknown"
    fc = str(item.get("FileCount") or 0)
    b = int(item.get("Bytes") or 0)
    p = item.get("ResolvedPath") or item.get("AbsolutePath") or item.get("Path") or ""
    print(f"{g}\t{s}\t{fc}\t{b}\t{p}")
' "$combined_results" | while IFS=$'\t' read -r g s fc b p; do
                local sz
                sz="$(_gsv_format_size "$b")"
                printf "%-30.30s %-18.18s %-7s %-10s %s\n" "$g" "$s" "$fc" "$sz" "$p"
            done
        fi
    fi
    return 0
}

cmd_scan_db() {
    local db_path="${GSV_CONFIG_DIR:-$GSV_ROOT/config}/scan-database.json"
    if [ ! -f "$db_path" ]; then
        echo "No scan database found at $db_path."
        echo "Run 'gamevault.sh scan' or 'gamevault.sh scan-folders' first."
        return 0
    fi

    echo "=== Stored Scan Database ==="
    echo "Database:     $db_path"

    local updated roots_len locs_len
    if command -v jq >/dev/null 2>&1; then
        updated="$(jq -r '(.UpdatedUtc // "Unknown")' "$db_path" 2>/dev/null)"
        roots_len="$(jq '(.Roots // []) | length' "$db_path" 2>/dev/null || echo 0)"
        locs_len="$(jq '(.Locations // []) | length' "$db_path" 2>/dev/null || echo 0)"
    else
        local db_meta
        db_meta="$(python3 -c '
import sys, json
with open(sys.argv[1], "r", encoding="utf-8") as f:
    d = json.load(f)
u = d.get("UpdatedUtc") or "Unknown"
r = len(d.get("Roots") or [])
l = len(d.get("Locations") or [])
print(f"{u}\t{r}\t{l}")
' "$db_path" 2>/dev/null || echo "Unknown\t0\t0")"
        IFS=$'\t' read -r updated roots_len locs_len <<< "$db_meta"
    fi

    echo "Last Updated: $updated"
    echo "Roots:        $roots_len"
    echo "Locations:    $locs_len"
    echo ""

    if [ "$locs_len" -eq 0 ]; then
        echo "Database contains 0 locations."
        return 0
    fi

    printf "%-30s %-18s %-7s %-10s %s\n" "GAME" "SOURCE" "FILES" "SIZE" "PATH"
    printf "%s\n" "------------------------------------------------------------------------------------------------"

    if command -v jq >/dev/null 2>&1; then
        jq -r '(.Locations // [])[] | [
            (.Game // .GameName // .GameId // "Unknown"),
            (.Source // .Origin // "Unknown"),
            ((.FileCount // 0) | tostring),
            ((.Bytes // 0) | tostring),
            (.ResolvedPath // .AbsolutePath // .Path // "")
        ] | @tsv' "$db_path" | while IFS=$'\t' read -r g s fc b p; do
            local sz
            sz="$(_gsv_format_size "$b")"
            printf "%-30.30s %-18.18s %-7s %-10s %s\n" "$g" "$s" "$fc" "$sz" "$p"
        done
    else
        python3 -c '
import sys, json
with open(sys.argv[1], "r", encoding="utf-8") as f:
    d = json.load(f)
for item in (d.get("Locations") or []):
    g = item.get("Game") or item.get("GameName") or item.get("GameId") or "Unknown"
    s = item.get("Source") or item.get("Origin") or "Unknown"
    fc = str(item.get("FileCount") or 0)
    b = int(item.get("Bytes") or 0)
    p = item.get("ResolvedPath") or item.get("AbsolutePath") or item.get("Path") or ""
    print(f"{g}\t{s}\t{fc}\t{b}\t{p}")
' "$db_path" | while IFS=$'\t' read -r g s fc b p; do
            local sz
            sz="$(_gsv_format_size "$b")"
            printf "%-30.30s %-18.18s %-7s %-10s %s\n" "$g" "$s" "$fc" "$sz" "$p"
        done
    fi
    return 0
}

cmd_backup() {
    local all_flag=0
    local game_names=""
    local label="manual-backup"
    local is_dry_run=0
    local vault_override="${GLOBAL_VAULT_OVERRIDE:-}"

    while [ $# -gt 0 ]; do
        case "$1" in
            --all)
                all_flag=1
                ;;
            --game)
                shift
                game_names="${1:-}"
                ;;
            --game=*)
                game_names="${1#*=}"
                ;;
            --label)
                shift
                label="${1:-manual-backup}"
                ;;
            --label=*)
                label="${1#*=}"
                ;;
            --dry-run)
                is_dry_run=1
                ;;
            --vault)
                shift
                vault_override="${1:-}"
                ;;
            --vault=*)
                vault_override="${1#*=}"
                ;;
            *)
                ;;
        esac
        shift
    done

    local db_path="${GSV_CONFIG_DIR:-$GSV_ROOT/config}/scan-database.json"
    if [ ! -f "$db_path" ]; then
        gsv_log_info "No scan database found; performing initial scan..."
        local scan_res
        scan_res="$(gsv_scan_all)"
        gsv_update_scan_database "$scan_res" >/dev/null 2>&1 || true
    fi

    local locs_to_backup=""
    if [ -n "$game_names" ]; then
        if command -v jq >/dev/null 2>&1; then
            locs_to_backup="$(jq --arg g "$game_names" '
                ($g | split(",") | map(gsub("^\\s+|\\s+$"; "") | ascii_downcase)) as $targets |
                (.Locations // []) | map(select((.Game // .GameName // "") | ascii_downcase as $gn | $targets | index($gn)))
            ' "$db_path" 2>/dev/null || echo "[]")"
        else
            locs_to_backup="$(python3 -c '
import sys, json
targets = set(x.strip().lower() for x in sys.argv[2].split(",") if x.strip())
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        d = json.load(f)
    locs = d.get("Locations", [])
    matched = [l for l in locs if (l.get("Game") or l.get("GameName") or "").strip().lower() in targets]
    print(json.dumps(matched))
except Exception:
    print("[]")
' "$db_path" "$game_names" 2>/dev/null || echo "[]")"
        fi
    else
        locs_to_backup="$db_path"
    fi

    gsv_create_snapshot "$locs_to_backup" "$is_dry_run" "$label" "$vault_override"
    return $?
}

cmd_restore() {
    local snapshot_id="latest"
    local game_filter="all"
    local is_dry_run=0
    local restore_root=""
    local vault_override="${GLOBAL_VAULT_OVERRIDE:-}"

    while [ $# -gt 0 ]; do
        case "$1" in
            --snapshot)
                shift
                snapshot_id="${1:-latest}"
                ;;
            --snapshot=*)
                snapshot_id="${1#*=}"
                ;;
            --game)
                shift
                game_filter="${1:-all}"
                ;;
            --game=*)
                game_filter="${1#*=}"
                ;;
            --all)
                game_filter="all"
                ;;
            --dry-run)
                is_dry_run=1
                ;;
            --restore-root)
                shift
                restore_root="${1:-}"
                ;;
            --restore-root=*)
                restore_root="${1#*=}"
                ;;
            --vault)
                shift
                vault_override="${1:-}"
                ;;
            --vault=*)
                vault_override="${1#*=}"
                ;;
            *)
                ;;
        esac
        shift
    done

    gsv_restore_snapshot "$snapshot_id" "$game_filter" "$is_dry_run" "$restore_root" "$vault_override"
    return $?
}

cmd_snapshots() {
    local vault_override="${GLOBAL_VAULT_OVERRIDE:-}"
    local as_json=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --vault)
                shift
                vault_override="${1:-}"
                ;;
            --vault=*)
                vault_override="${1#*=}"
                ;;
            --json)
                as_json=1
                ;;
            *)
                if [ -z "$vault_override" ]; then
                    vault_override="$1"
                fi
                ;;
        esac
        shift
    done

    if [ "$as_json" -eq 1 ]; then
        gsv_list_snapshots "$vault_override" --json
    else
        gsv_list_snapshots "$vault_override"
    fi
    return $?
}

cmd_doctor() {
    gsv_run_doctor
    return $?
}

cmd_gui() {
    gsv_launch_dashboard "$@"
    return $?
}

# ------------------------------------------------------------------------------
# Dispatcher Entrypoint
# ------------------------------------------------------------------------------
GLOBAL_VAULT_OVERRIDE=""
COMMAND=""
declare -a CMD_ARGS=()

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            if [ -z "$COMMAND" ]; then
                show_help
                exit 0
            fi
            CMD_ARGS+=("$1")
            ;;
        help)
            if [ -z "$COMMAND" ]; then
                show_help
                exit 0
            fi
            CMD_ARGS+=("$1")
            ;;
        --gui)
            export GSV_UI_MODE="gui"
            ;;
        --tui)
            export GSV_UI_MODE="tui"
            ;;
        --cli)
            export GSV_UI_MODE="cli"
            ;;
        --vault)
            shift
            GLOBAL_VAULT_OVERRIDE="${1:-}"
            export GSV_VAULT_PATH="$GLOBAL_VAULT_OVERRIDE"
            ;;
        --vault=*)
            GLOBAL_VAULT_OVERRIDE="${1#*=}"
            export GSV_VAULT_PATH="$GLOBAL_VAULT_OVERRIDE"
            ;;
        *)
            if [ -z "$COMMAND" ]; then
                COMMAND="$1"
            else
                CMD_ARGS+=("$1")
            fi
            ;;
    esac
    shift
done

# If no command provided: check interactivity
if [ -z "$COMMAND" ]; then
    if [ -t 0 ] && [ -t 1 ]; then
        cmd_gui
        exit $?
    else
        show_help
        exit 0
    fi
fi

# Dispatch command
case "$COMMAND" in
    scan)
        cmd_scan "${CMD_ARGS[@]+"${CMD_ARGS[@]}"}"
        exit $?
        ;;
    scan-folders)
        cmd_scan_folders "${CMD_ARGS[@]+"${CMD_ARGS[@]}"}"
        exit $?
        ;;
    scan-db)
        cmd_scan_db "${CMD_ARGS[@]+"${CMD_ARGS[@]}"}"
        exit $?
        ;;
    backup)
        cmd_backup "${CMD_ARGS[@]+"${CMD_ARGS[@]}"}"
        exit $?
        ;;
    restore)
        cmd_restore "${CMD_ARGS[@]+"${CMD_ARGS[@]}"}"
        exit $?
        ;;
    snapshots)
        cmd_snapshots "${CMD_ARGS[@]+"${CMD_ARGS[@]}"}"
        exit $?
        ;;
    doctor)
        cmd_doctor "${CMD_ARGS[@]+"${CMD_ARGS[@]}"}"
        exit $?
        ;;
    gui)
        cmd_gui "${CMD_ARGS[@]+"${CMD_ARGS[@]}"}"
        exit $?
        ;;
    *)
        echo "Error: Unknown command '$COMMAND'. Run 'gamevault.sh help' for usage." >&2
        exit 1
        ;;
esac
