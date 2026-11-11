#!/usr/bin/env bash
# ==============================================================================
# linux/modules/vault.sh
# Vault storage, snapshot backup, selective restore, and rollback engine
# for GameSaveVault.
# ==============================================================================

# Guard against duplicate inclusion
if [ -n "${_GSV_VAULT_LOADED:-}" ]; then
    return 0
fi
_GSV_VAULT_LOADED=1

# Ensure common.sh is loaded
if [ -z "${_GSV_COMMON_LOADED:-}" ]; then
    _MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=common.sh
    source "$_MODULE_DIR/common.sh"
fi

# Ensure scanner.sh is loaded if available
if [ -z "${_GSV_SCANNER_LOADED:-}" ]; then
    _MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$_MODULE_DIR/scanner.sh" ]; then
        # shellcheck source=scanner.sh
        source "$_MODULE_DIR/scanner.sh"
    fi
fi

# ------------------------------------------------------------------------------
# Helper: Format Bytes for Human Display
# ------------------------------------------------------------------------------
_gsv_format_size() {
    local bytes="${1:-0}"
    if [ "$bytes" -lt 1024 ]; then
        echo "${bytes} B"
    elif [ "$bytes" -lt 1048576 ]; then
        awk -v b="$bytes" 'BEGIN { printf "%.1f KB", b / 1024 }'
    elif [ "$bytes" -lt 1073741824 ]; then
        awk -v b="$bytes" 'BEGIN { printf "%.2f MB", b / 1048576 }'
    else
        awk -v b="$bytes" 'BEGIN { printf "%.2f GB", b / 1073741824 }'
    fi
}

# ------------------------------------------------------------------------------
# Helper: Parse Locations Input to JSON Array
# ------------------------------------------------------------------------------
_gsv_parse_locations_to_array() {
    local input="${1:-}"

    if [ -z "$input" ]; then
        local default_db="${GSV_CONFIG_DIR:-$GSV_ROOT/config}/scan-database.json"
        if [ -f "$default_db" ]; then
            input="$default_db"
        else
            echo "[]"
            return 0
        fi
    fi

    local tool="${GSV_JSON_TOOL:-}"
    if [ -z "$tool" ] || [ "$tool" = "none" ]; then
        if command -v jq >/dev/null 2>&1; then
            tool="jq"
        elif command -v python3 >/dev/null 2>&1; then
            tool="python3"
        fi
    fi

    if [ -f "$input" ]; then
        if [ "$tool" = "jq" ]; then
            jq 'if type == "object" and .Locations then .Locations elif type == "array" then . else [] end' "$input" 2>/dev/null || echo "[]"
        else
            python3 -c '
import sys, json
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        data = json.load(f)
    if isinstance(data, dict):
        data = data.get("Locations", [])
    if not isinstance(data, list):
        data = []
    print(json.dumps(data))
except Exception:
    print("[]")
' "$input" 2>/dev/null || echo "[]"
        fi
    else
        if [ "$tool" = "jq" ]; then
            echo "$input" | jq 'if type == "object" and .Locations then .Locations elif type == "array" then . else [] end' 2>/dev/null || echo "[]"
        else
            python3 -c '
import sys, json
try:
    data = json.loads(sys.argv[1])
    if isinstance(data, dict):
        data = data.get("Locations", [])
    if not isinstance(data, list):
        data = []
    print(json.dumps(data))
except Exception:
    print("[]")
' "$input" 2>/dev/null || echo "[]"
        fi
    fi
}

# ------------------------------------------------------------------------------
# Snapshot Backup
# ------------------------------------------------------------------------------

# gsv_create_snapshot(locations_input, is_dry_run, [label], [vault_override])
# Copies save data to <vault>/snapshots/<YYYY-MM-DD_HHMMSS>/data/<Game>/...
# and generates manifest.json according to specification.
gsv_create_snapshot() {
    local locations_input="${1:-}"
    local is_dry_run="${2:-0}"
    local label="${3:-manual-backup}"
    local vault_override="${4:-}"

    local vault_path
    vault_path="$(gsv_resolve_vault_path "$vault_override")"
    if [ -z "$vault_path" ]; then
        gsv_log_error "Unable to resolve vault storage directory."
        return 1
    fi

    local timestamp
    timestamp="$(date '+%Y-%m-%d_%H%M%S')"
    local created_utc
    created_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

    local snap_dir="$vault_path/snapshots/$timestamp"
    local snap_data_dir="$snap_dir/data"

    local raw_locations
    raw_locations="$(_gsv_parse_locations_to_array "$locations_input")"

    local tool="${GSV_JSON_TOOL:-jq}"
    if [ "$tool" != "jq" ] && ! command -v jq >/dev/null 2>&1; then
        tool="python3"
    fi

    # Read location count
    local loc_count=0
    if [ "$tool" = "jq" ]; then
        loc_count="$(echo "$raw_locations" | jq 'length' 2>/dev/null || echo 0)"
    else
        loc_count="$(python3 -c '
import sys, json
try:
    d = json.loads(sys.argv[1])
    print(len(d) if isinstance(d, list) else 0)
except Exception:
    print(0)
' "$raw_locations" 2>/dev/null || echo 0)"
    fi

    if [ "$loc_count" -eq 0 ]; then
        gsv_log_warn "No game save locations provided for snapshot."
        return 0
    fi

    if [ "$is_dry_run" = "1" ]; then
        gsv_log_info "[dry-run] Simulating snapshot creation for $loc_count locations (Label: $label)..."
    else
        gsv_log_info "Creating snapshot '$timestamp' in '$vault_path' (Label: $label)..."
        mkdir -p "$snap_data_dir"
    fi

    local total_games=0
    local total_files=0
    local total_bytes=0

    local entries_tmp
    entries_tmp="$(mktemp "${TMPDIR:-/tmp}/gsv-entries.XXXXXX")"
    echo "[]" > "$entries_tmp"

    local i=0
    while [ "$i" -lt "$loc_count" ]; do
        local loc_item
        if [ "$tool" = "jq" ]; then
            loc_item="$(echo "$raw_locations" | jq -c ".[$i]" 2>/dev/null)"
        else
            loc_item="$(python3 -c '
import sys, json
try:
    d = json.loads(sys.argv[1])
    print(json.dumps(d[int(sys.argv[2])]))
except Exception:
    print("{}")
' "$raw_locations" "$i" 2>/dev/null)"
        fi
        i=$((i + 1))

        [ -z "$loc_item" ] && continue

        # Extract fields
        local game source orig_path token_path kind
        if [ "$tool" = "jq" ]; then
            game="$(echo "$loc_item" | jq -r '(.Game // .GameName // .GameId // "")' 2>/dev/null)"
            source="$(echo "$loc_item" | jq -r '(.Source // .Origin // "Custom")' 2>/dev/null)"
            orig_path="$(echo "$loc_item" | jq -r '(.OriginalPath // .ResolvedPath // .AbsolutePath // .Path // "")' 2>/dev/null)"
            token_path="$(echo "$loc_item" | jq -r '(.TokenPath // (if .Token then ("%" + (.Token | ltrimstr("%") | rtrimstr("%")) + "%" + (if .RelativePath then "/" + .RelativePath else "" end)) else "" end))' 2>/dev/null)"
            kind="$(echo "$loc_item" | jq -r '(.Kind // "")' 2>/dev/null)"
        else
            local parsed_vars
            parsed_vars="$(python3 -c '
import sys, json, shlex
item = json.loads(sys.argv[1])
g = item.get("Game") or item.get("GameName") or item.get("GameId") or ""
s = item.get("Source") or item.get("Origin") or "Custom"
p = item.get("OriginalPath") or item.get("ResolvedPath") or item.get("AbsolutePath") or item.get("Path") or ""
tp = item.get("TokenPath") or ""
if not tp and item.get("Token"):
    t = item.get("Token").strip("%")
    rel = item.get("RelativePath") or ""
    tp = f"%{t}%/{rel}" if rel else f"%{t}%"
k = item.get("Kind") or ""
print(f"game={shlex.quote(g)} source={shlex.quote(s)} orig_path={shlex.quote(p)} token_path={shlex.quote(tp)} kind={shlex.quote(k)}")
' "$loc_item" 2>/dev/null)"
            eval "$parsed_vars"
        fi

        orig_path="${orig_path/#\~/$HOME}"
        [ -z "$orig_path" ] && continue

        if [ -z "$game" ]; then
            game="$(basename "$orig_path")"
        fi

        if [ ! -e "$orig_path" ]; then
            gsv_log_warn "Save path does not exist, skipping '$game': $orig_path"
            continue
        fi

        # Auto-detect kind if not supplied
        if [ -z "$kind" ] || [ "$kind" = "null" ]; then
            if [ -f "$orig_path" ]; then
                kind="File"
            else
                kind="Directory"
            fi
        fi

        # Resolve portable token path if empty
        if [ -z "$token_path" ] || [ "$token_path" = "null" ]; then
            token_path="$(gsv_path_to_token "$orig_path")"
        fi

        # Measure file count and size
        local fc=0
        local sz=0
        if [ "$kind" = "File" ] || [ -f "$orig_path" ]; then
            fc=1
            sz="$(stat -c %s "$orig_path" 2>/dev/null || wc -c < "$orig_path" 2>/dev/null || echo 0)"
        else
            fc="$(find "$orig_path" -type f 2>/dev/null | wc -l)"
            sz="$(du -sb "$orig_path" 2>/dev/null | cut -f1)"
            [ -z "$sz" ] && sz=0
        fi

        local rel_data_path="data/$game"

        if [ "$is_dry_run" = "1" ]; then
            gsv_log_info "[dry-run] Would backup '$game' ($fc files, $(_gsv_format_size "$sz")) from '$orig_path' -> '$snap_dir/$rel_data_path'"
        else
            local target_game_dir="$snap_dir/$rel_data_path"
            mkdir -p "$target_game_dir"
            if [ "$kind" = "File" ] || [ -f "$orig_path" ]; then
                cp -a "$orig_path" "$target_game_dir/"
            else
                cp -a "$orig_path/." "$target_game_dir/"
            fi

            # Collect copied file list
            local files_json="[]"
            if [ "$tool" = "jq" ]; then
                files_json="$(find "$target_game_dir" -type f 2>/dev/null | sed "s|^$snap_dir/||" | jq -R . | jq -s . 2>/dev/null || echo "[]")"
                jq --arg g "$game" \
                   --arg s "$source" \
                   --arg op "$orig_path" \
                   --arg tp "$token_path" \
                   --arg k "$kind" \
                   --arg rdp "$rel_data_path" \
                   --argjson fc "$fc" \
                   --argjson b "$sz" \
                   --argjson fl "$files_json" \
                   '. += [{
                       Game: $g,
                       Source: $s,
                       OriginalPath: $op,
                       TokenPath: $tp,
                       Kind: $k,
                       FileCount: $fc,
                       Bytes: $b,
                       RelativeDataPath: $rdp,
                       Files: $fl
                   }]' "$entries_tmp" > "${entries_tmp}.new" && mv -f "${entries_tmp}.new" "$entries_tmp"
            else
                python3 -c '
import sys, json, os

entries_file, game, source, op, tp, kind, rdp, fc, sz, snap_dir, target_dir = sys.argv[1:12]

with open(entries_file, "r", encoding="utf-8") as f:
    entries = json.load(f)

files = []
for root, _, filenames in os.walk(target_dir):
    for fn in filenames:
        fp = os.path.join(root, fn)
        rel = os.path.relpath(fp, snap_dir)
        files.append(rel)

entries.append({
    "Game": game,
    "Source": source,
    "OriginalPath": op,
    "TokenPath": tp,
    "Kind": kind,
    "FileCount": int(fc),
    "Bytes": int(sz),
    "RelativeDataPath": rdp,
    "Files": sorted(files)
})

with open(entries_file, "w", encoding="utf-8") as f:
    json.dump(entries, f)
' "$entries_tmp" "$game" "$source" "$orig_path" "$token_path" "$kind" "$rel_data_path" "$fc" "$sz" "$snap_dir" "$target_game_dir"
            fi
        fi

        total_games=$((total_games + 1))
        total_files=$((total_files + fc))
        total_bytes=$((total_bytes + sz))
    done

    if [ "$is_dry_run" = "1" ]; then
        rm -f "$entries_tmp"
        gsv_log_info "[dry-run] Snapshot summary: $total_games games, $total_files files, $(_gsv_format_size "$total_bytes"). No files were written."
        return 0
    fi

    # Write manifest.json
    local manifest_path="$snap_dir/manifest.json"
    if [ "$tool" = "jq" ]; then
        jq -n \
            --arg created "$created_utc" \
            --arg platform "Linux" \
            --arg label "$label" \
            --argjson tg "$total_games" \
            --argjson tf "$total_files" \
            --argjson tb "$total_bytes" \
            --slurpfile entries "$entries_tmp" \
            '{
                CreatedAt: $created,
                Platform: $platform,
                Label: $label,
                TotalGames: $tg,
                TotalFiles: $tf,
                TotalBytes: $tb,
                Entries: ($entries[0] // [])
            }' > "$manifest_path"
    else
        python3 -c '
import sys, json

created, label, tg, tf, tb, entries_file, manifest_file = sys.argv[1:8]
with open(entries_file, "r", encoding="utf-8") as f:
    entries = json.load(f)

manifest = {
    "CreatedAt": created,
    "Platform": "Linux",
    "Label": label,
    "TotalGames": int(tg),
    "TotalFiles": int(tf),
    "TotalBytes": int(tb),
    "Entries": entries
}

with open(manifest_file, "w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")
' "$created_utc" "$label" "$total_games" "$total_files" "$total_bytes" "$entries_tmp" "$manifest_path"
    fi

    rm -f "$entries_tmp"

    export GSV_LAST_SNAPSHOT_DIR="$snap_dir"
    gsv_log_info "Snapshot '$timestamp' created successfully at '$snap_dir' ($total_games games, $total_files files, $(_gsv_format_size "$total_bytes"))."
    return 0
}

# ------------------------------------------------------------------------------
# Snapshot Listing & Resolution
# ------------------------------------------------------------------------------

# gsv_resolve_snapshot_dir(snapshot_id, [vault_override])
# Resolves "latest" or snapshot directory name/path to absolute folder.
gsv_resolve_snapshot_dir() {
    local snapshot_id="${1:-latest}"
    local vault_override="${2:-}"

    local vault_path
    vault_path="$(gsv_resolve_vault_path "$vault_override")"
    local snap_root="$vault_path/snapshots"

    if [ ! -d "$snap_root" ]; then
        gsv_log_error "Snapshots directory does not exist: $snap_root" >&2
        return 1
    fi

    # 1. "latest" resolution
    if [ -z "$snapshot_id" ] || [ "$snapshot_id" = "latest" ]; then
        local latest_dir=""
        while IFS= read -r d; do
            [ -z "$d" ] && continue
            if [ -f "$d/manifest.json" ]; then
                latest_dir="$d"
                break
            fi
        done < <(find "$snap_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r)
        if [ -n "$latest_dir" ]; then
            echo "$latest_dir"
            return 0
        fi
        gsv_log_error "No valid snapshots found in '$snap_root'." >&2
        return 1
    fi

    # 2. Direct directory path
    if [ -d "$snapshot_id" ] && [ -f "$snapshot_id/manifest.json" ]; then
        (cd "$snapshot_id" && pwd)
        return 0
    fi

    # 3. Direct folder name under <vault>/snapshots/
    if [ -d "$snap_root/$snapshot_id" ] && [ -f "$snap_root/$snapshot_id/manifest.json" ]; then
        echo "$snap_root/$snapshot_id"
        return 0
    fi

    # 4. Prefix or substring match under snapshots/
    local candidate=""
    for d in "$snap_root"/*"$snapshot_id"*; do
        if [ -d "$d" ] && [ -f "$d/manifest.json" ]; then
            candidate="$d"
            break
        fi
    done

    if [ -n "$candidate" ]; then
        echo "$candidate"
        return 0
    fi

    gsv_log_error "Snapshot '$snapshot_id' not found in '$snap_root'." >&2
    return 1
}

# gsv_list_snapshots([vault_override], [--json])
# Lists snapshots in vault chronologically, formatted as table or JSON array.
gsv_list_snapshots() {
    local vault_override=""
    local as_json=0

    for arg in "$@"; do
        if [ "$arg" = "--json" ]; then
            as_json=1
        elif [ -z "$vault_override" ]; then
            vault_override="$arg"
        fi
    done

    local vault_path
    vault_path="$(gsv_resolve_vault_path "$vault_override")"
    local snap_root="$vault_path/snapshots"

    local tool="${GSV_JSON_TOOL:-jq}"
    if [ "$tool" != "jq" ] && ! command -v jq >/dev/null 2>&1; then
        tool="python3"
    fi

    if [ ! -d "$snap_root" ]; then
        if [ "$as_json" = "1" ]; then
            echo "[]"
        else
            echo "No snapshots found in $snap_root."
        fi
        return 0
    fi

    local snap_dirs=()
    while IFS= read -r d; do
        [ -z "$d" ] && continue
        if [ -f "$d/manifest.json" ]; then
            snap_dirs+=("$d")
        fi
    done < <(find "$snap_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r)

    if [ "${#snap_dirs[@]}" -eq 0 ]; then
        if [ "$as_json" = "1" ]; then
            echo "[]"
        else
            echo "No snapshots found in $snap_root."
        fi
        return 0
    fi

    if [ "$as_json" = "1" ]; then
        local list_tmp
        list_tmp="$(mktemp "${TMPDIR:-/tmp}/gsv-snaplist.XXXXXX")"
        echo "[]" > "$list_tmp"

        for sd in "${snap_dirs[@]}"; do
            local mf="$sd/manifest.json"
            local s_id
            s_id="$(basename "$sd")"

            if [ "$tool" = "jq" ]; then
                jq --arg id "$s_id" --arg path "$sd" --slurpfile m "$mf" \
                   '. += [{
                       Id: $id,
                       Path: $path,
                       CreatedAt: ($m[0].CreatedAt // $m[0].CreatedUtc // ""),
                       Label: ($m[0].Label // ""),
                       TotalGames: ($m[0].TotalGames // $m[0].EntryCount // 0),
                       TotalFiles: ($m[0].TotalFiles // 0),
                       TotalBytes: ($m[0].TotalBytes // $m[0].TotalSizeBytes // 0)
                   }]' "$list_tmp" > "${list_tmp}.new" && mv -f "${list_tmp}.new" "$list_tmp"
            else
                python3 -c '
import sys, json

list_file, sid, spath, mpath = sys.argv[1:5]
with open(list_file, "r", encoding="utf-8") as f:
    items = json.load(f)
try:
    with open(mpath, "r", encoding="utf-8") as f:
        m = json.load(f)
except Exception:
    m = {}

items.append({
    "Id": sid,
    "Path": spath,
    "CreatedAt": m.get("CreatedAt") or m.get("CreatedUtc") or "",
    "Label": m.get("Label", ""),
    "TotalGames": m.get("TotalGames") if m.get("TotalGames") is not None else m.get("EntryCount", 0),
    "TotalFiles": m.get("TotalFiles", 0),
    "TotalBytes": m.get("TotalBytes") if m.get("TotalBytes") is not None else m.get("TotalSizeBytes", 0)
})

with open(list_file, "w", encoding="utf-8") as f:
    json.dump(items, f, indent=2)
' "$list_tmp" "$s_id" "$sd" "$mf"
            fi
        done

        cat "$list_tmp"
        rm -f "$list_tmp"
        return 0
    fi

    # Formatted human table output
    printf "%-22s %-20s %-7s %-7s %-12s %s\n" "SNAPSHOT ID" "CREATED (UTC)" "GAMES" "FILES" "SIZE" "LABEL"
    printf "%s\n" "--------------------------------------------------------------------------------"
    for sd in "${snap_dirs[@]}"; do
        local mf="$sd/manifest.json"
        local s_id
        s_id="$(basename "$sd")"
        local created label tg tf tb
        if [ "$tool" = "jq" ]; then
            created="$(jq -r '(.CreatedAt // .CreatedUtc // "")' "$mf" 2>/dev/null)"
            label="$(jq -r '(.Label // "")' "$mf" 2>/dev/null)"
            tg="$(jq -r '(.TotalGames // .EntryCount // 0)' "$mf" 2>/dev/null)"
            tf="$(jq -r '(.TotalFiles // 0)' "$mf" 2>/dev/null)"
            tb="$(jq -r '(.TotalBytes // .TotalSizeBytes // 0)' "$mf" 2>/dev/null)"
        else
            local snap_vars
            snap_vars="$(python3 -c '
import sys, json, shlex
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        m = json.load(f)
except Exception:
    m = {}
c = str(m.get("CreatedAt") or m.get("CreatedUtc") or "")
l = str(m.get("Label") or "")
tg = m.get("TotalGames") if m.get("TotalGames") is not None else m.get("EntryCount", 0)
tf = int(m.get("TotalFiles") or 0)
tb = m.get("TotalBytes") if m.get("TotalBytes") is not None else m.get("TotalSizeBytes", 0)
print(f"created={shlex.quote(c)} label={shlex.quote(l)} tg={tg} tf={tf} tb={tb}")
' "$mf" 2>/dev/null)"
            eval "$snap_vars"
        fi
        local sz_formatted
        sz_formatted="$(_gsv_format_size "$tb")"
        # Convert ISO UTC to cleaner display if needed: 2026-11-11T13:00:00Z -> 2026-11-11 13:00:00
        local display_date="${created//T/ }"
        display_date="${display_date//Z/}"
        printf "%-22s %-20s %-7s %-7s %-12s %s\n" "$s_id" "$display_date" "$tg" "$tf" "$sz_formatted" "$label"
    done
    return 0
}

# ------------------------------------------------------------------------------
# Snapshot Restore & Rollback Engine
# ------------------------------------------------------------------------------

# gsv_restore_snapshot(snapshot_id, selected_games_filter, is_dry_run, [restore_root], [vault_override])
# Restores games from a snapshot, backing up overwritten targets to <vault>/rollback/<timestamp>/<Game>.
gsv_restore_snapshot() {
    local snapshot_id="${1:-latest}"
    local selected_games_filter="${2:-all}"
    local is_dry_run="${3:-0}"
    local restore_root="${4:-}"
    local vault_override="${5:-}"

    local vault_path
    vault_path="$(gsv_resolve_vault_path "$vault_override")"
    if [ -z "$vault_path" ]; then
        gsv_log_error "Unable to resolve vault directory for restore."
        return 1
    fi

    local snapshot_dir
    snapshot_dir="$(gsv_resolve_snapshot_dir "$snapshot_id" "$vault_path")"
    local resolve_status=$?
    if [ $resolve_status -ne 0 ] || [ -z "$snapshot_dir" ] || [ ! -d "$snapshot_dir" ]; then
        gsv_log_error "Failed to locate snapshot '$snapshot_id'."
        return 1
    fi

    local manifest_path="$snapshot_dir/manifest.json"
    if [ ! -f "$manifest_path" ]; then
        gsv_log_error "Snapshot is missing manifest.json at '$manifest_path'."
        return 1
    fi

    local tool="${GSV_JSON_TOOL:-jq}"
    if [ "$tool" != "jq" ] && ! command -v jq >/dev/null 2>&1; then
        tool="python3"
    fi

    # Filter manifest entries according to selected_games_filter
    local matched_entries_json
    if [ "$tool" = "jq" ]; then
        matched_entries_json="$(jq --arg filter "$selected_games_filter" '
            (.Entries // .Games // []) as $entries |
            if ($filter == "" or $filter == "all" or $filter == "*") then
                $entries
            else
                ($filter | split(",") | map(gsub("^\\s+|\\s+$"; "") | ascii_downcase)) as $targets |
                $entries | map(select(((.Game // .GameName // .GameId // "") | ascii_downcase) as $g | $targets | index($g)))
            end
        ' "$manifest_path" 2>/dev/null || echo "[]")"
    else
        matched_entries_json="$(python3 -c '
import sys, json

mpath, raw_filter = sys.argv[1:3]
try:
    with open(mpath, "r", encoding="utf-8") as f:
        data = json.load(f)
    entries = data.get("Entries") or data.get("Games") or []
except Exception:
    entries = []

filter_clean = raw_filter.strip().lower()
if not filter_clean or filter_clean in ("all", "*"):
    matched = entries
else:
    targets = set(t.strip().lower() for t in raw_filter.split(",") if t.strip())
    matched = [e for e in entries if (e.get("Game") or e.get("GameName") or e.get("GameId") or "").strip().lower() in targets]

print(json.dumps(matched))
' "$manifest_path" "$selected_games_filter" 2>/dev/null || echo "[]")"
    fi

    local match_count=0
    if [ "$tool" = "jq" ]; then
        match_count="$(echo "$matched_entries_json" | jq 'length' 2>/dev/null || echo 0)"
    else
        match_count="$(python3 -c '
import sys, json
try:
    d = json.loads(sys.argv[1])
    print(len(d) if isinstance(d, list) else 0)
except Exception:
    print(0)
' "$matched_entries_json" 2>/dev/null || echo 0)"
    fi

    if [ "$match_count" -eq 0 ]; then
        gsv_log_info "No matching games found in snapshot for filter '$selected_games_filter'."
        return 0
    fi

    local rollback_timestamp
    rollback_timestamp="$(date '+%Y-%m-%d_%H%M%S')"

    if [ "$is_dry_run" = "1" ]; then
        gsv_log_info "[dry-run] Simulating restore of $match_count games from snapshot '$(basename "$snapshot_dir")'..."
    else
        gsv_log_info "Restoring $match_count games from snapshot '$(basename "$snapshot_dir")'..."
    fi

    local i=0
    while [ "$i" -lt "$match_count" ]; do
        local entry_item
        if [ "$tool" = "jq" ]; then
            entry_item="$(echo "$matched_entries_json" | jq -c ".[$i]" 2>/dev/null)"
        else
            entry_item="$(python3 -c '
import sys, json
d = json.loads(sys.argv[1])
print(json.dumps(d[int(sys.argv[2])]))
' "$matched_entries_json" "$i" 2>/dev/null)"
        fi
        i=$((i + 1))

        [ -z "$entry_item" ] && continue

        local game token_path orig_path rel_data_path kind
        if [ "$tool" = "jq" ]; then
            game="$(echo "$entry_item" | jq -r '(.Game // .GameName // .GameId // "")' 2>/dev/null)"
            token_path="$(echo "$entry_item" | jq -r '(.TokenPath // (if .Token then ("%" + (.Token | ltrimstr("%") | rtrimstr("%")) + "%" + (if .RelativePath and .RelativePath != "" then ("/" + (.RelativePath | ltrimstr("/") | ltrimstr("\\"))) else "" end)) else null end) // "")' 2>/dev/null)"
            orig_path="$(echo "$entry_item" | jq -r '(.OriginalPath // .ResolvedPath // .AbsolutePath // "")' 2>/dev/null)"
            rel_data_path="$(echo "$entry_item" | jq -r '(.RelativeDataPath // .Payload // ("data/" + (.Game // .GameName // .GameId // "")))' 2>/dev/null)"
            kind="$(echo "$entry_item" | jq -r '(.Kind // "")' 2>/dev/null)"
        else
            local parsed_entry
            parsed_entry="$(python3 -c '
import sys, json, shlex
item = json.loads(sys.argv[1])
g = item.get("Game") or item.get("GameName") or item.get("GameId") or ""
tok = item.get("Token")
rel = item.get("RelativePath") or ""
if item.get("TokenPath"):
    tp = item.get("TokenPath")
elif tok:
    tok_clean = str(tok).strip("%")
    rel_clean = str(rel).lstrip("/\\").replace("\\", "/")
    tp = f"%{tok_clean}%/{rel_clean}" if rel_clean else f"%{tok_clean}%"
else:
    tp = ""
op = item.get("OriginalPath") or item.get("ResolvedPath") or item.get("AbsolutePath") or ""
rdp = item.get("RelativeDataPath") or item.get("Payload") or f"data/{g}"
rdp = str(rdp).replace("\\", "/")
k = item.get("Kind") or ""
print(f"game={shlex.quote(str(g))} token_path={shlex.quote(str(tp))} orig_path={shlex.quote(str(op))} rel_data_path={shlex.quote(str(rdp))} kind={shlex.quote(str(k))}")
' "$entry_item" 2>/dev/null)"
            eval "$parsed_entry"
        fi

        rel_data_path="${rel_data_path//\\//}"
        token_path="${token_path//\\//}"

        local src_data="$snapshot_dir/$rel_data_path"
        if [ ! -e "$src_data" ]; then
            src_data="$snapshot_dir/data/$game"
        fi

        if [ ! -e "$src_data" ]; then
            gsv_log_error "Snapshot data directory missing for game '$game': $src_data"
            continue
        fi

        # Compute destination path
        local dest=""
        if [ -n "$restore_root" ]; then
            dest="$restore_root/$game"
        else
            local expanded_orig="${orig_path/#\~/$HOME}"
            if [ -n "$orig_path" ] && [ "$orig_path" != "null" ] && [[ "$expanded_orig" == /* ]] && { [ -e "$expanded_orig" ] || [ -d "$(dirname "$expanded_orig")" ]; }; then
                dest="$expanded_orig"
            elif [ -n "$token_path" ] && [ "$token_path" != "null" ]; then
                dest="$(gsv_token_to_path "$token_path")"
            elif [ -n "$orig_path" ] && [ "$orig_path" != "null" ]; then
                dest="$expanded_orig"
            else
                dest="$HOME/GameSaves/$game"
            fi
        fi
        dest="${dest/#\~/$HOME}"

        # Detect if destination is single file or directory
        local is_file_restore=0
        if [ "$kind" = "File" ] || [ -f "$src_data" ]; then
            is_file_restore=1
        elif [ -z "$restore_root" ] && [ -n "$orig_path" ] && [ -f "$orig_path" ]; then
            is_file_restore=1
        fi

        # Rollback collision protection
        if [ -e "$dest" ]; then
            local rollback_target="$vault_path/rollback/$rollback_timestamp/$game"
            if [ "$is_dry_run" = "1" ]; then
                gsv_log_info "[dry-run] Collision detected: '$dest' would be moved to rollback '$rollback_target'"
            else
                gsv_log_info "Collision detected: moving existing '$dest' to rollback '$rollback_target'"
                mkdir -p "$(dirname "$rollback_target")"
                mv "$dest" "$rollback_target" 2>/dev/null || { cp -a "$dest" "$rollback_target" && rm -rf "$dest"; }
            fi
        fi

        # Restore files
        if [ "$is_dry_run" = "1" ]; then
            gsv_log_info "[dry-run] Would restore '$game' from '$src_data' -> '$dest'"
        else
            gsv_log_info "Restoring '$game' to '$dest'..."
            mkdir -p "$(dirname "$dest")"
            if [ "$is_file_restore" -eq 1 ]; then
                if [ -f "$src_data" ]; then
                    cp -a "$src_data" "$dest"
                elif [ -d "$src_data" ]; then
                    # Find the save file within the game directory
                    local sub_file
                    sub_file="$(find "$src_data" -maxdepth 1 -type f 2>/dev/null | head -n 1)"
                    if [ -n "$sub_file" ]; then
                        if [ -d "$dest" ] || [ -n "$restore_root" ]; then
                            mkdir -p "$dest"
                            cp -a "$sub_file" "$dest/"
                        else
                            cp -a "$sub_file" "$dest"
                        fi
                    else
                        mkdir -p "$dest"
                        cp -a "$src_data/." "$dest/"
                    fi
                fi
            else
                mkdir -p "$dest"
                cp -a "$src_data/." "$dest/"
            fi
            gsv_log_info "Successfully restored '$game'."
        fi
    done

    if [ "$is_dry_run" = "1" ]; then
        gsv_log_info "[dry-run] Restore dry run complete. No filesystem changes were made."
    else
        gsv_log_info "Restore operation completed successfully."
    fi
    return 0
}
