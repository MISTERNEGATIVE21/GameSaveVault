#!/usr/bin/env bash
# ==============================================================================
# linux/modules/scanner.sh
# Save scanner (Proton, Flatpak, Wine, Native, Emulators, Custom deep scan)
# for GameSaveVault.
# ==============================================================================

# Guard against duplicate inclusion
if [ -n "${_GSV_SCANNER_LOADED:-}" ]; then
    return 0
fi
_GSV_SCANNER_LOADED=1

# Ensure common.sh is loaded
if [ -z "${_GSV_COMMON_LOADED:-}" ]; then
    _MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=common.sh
    source "$_MODULE_DIR/common.sh"
fi

# ------------------------------------------------------------------------------
# Pruning / Skip Filter
# ------------------------------------------------------------------------------
_gsv_is_pruned() {
    local name="${1,,}"
    case "$name" in
        windows*|winsxs*|\$recycle.bin*|system\ volume\ information*|recovery*|perflogs*|msocache*|config.msi*|\$winreagent*) return 0 ;;
        program\ files*|program\ files\ \(x86\)*|installer*|temp*|tmp*|cache*|caches*|shadercache*|crashreports*|crashdumps*) return 0 ;;
        node_modules*|.git*|.svn*|.hg*|__pycache__*|logs*|log*|packages*|package\ cache*|windows.old*) return 0 ;;
        microsoft*|google*|mozilla*|chrome*|firefox*|edge*|brave*|opera*|adobe*|nvidia*|intel*|amd*) return 0 ;;
        dropbox*|discord*|slack*|spotify*|teams*|zoom*|skype*|telegram*|jetbrains*|visual\ studio*|vs\ code*|vscode*|code*|cursor*|claude*|antigravity*|cherrystudio*|electron*|obs-studio*|arduino*|balena*) return 0 ;;
        alacritty*|kitty*|foot*|ghostty*|hypr*|omarchy*|waybar*|rofi*|wofi*|systemd*|pulse*|pipewire*|wireplumber*|dconf*|glib-2.0*|flatpak*|ibus*|gnome*|nautilus*|fish*|zsh*|bash*) return 0 ;;
        fontconfig*|themes*|icons*|mime*|locale*|applications*|autostart*|btop*|capacitor*|android*) return 0 ;;
        *) return 1 ;;
    esac
}

# ------------------------------------------------------------------------------
# File & Byte Measurement Helper
# ------------------------------------------------------------------------------
_gsv_measure_path() {
    local p="$1"
    if [ -f "$p" ]; then
        local bytes
        bytes="$(stat -c %s "$p" 2>/dev/null || wc -c < "$p" 2>/dev/null || echo 0)"
        echo "1 $bytes"
        return 0
    elif [ -d "$p" ]; then
        local fc bytes
        fc="$(find "$p" -type f 2>/dev/null | wc -l)"
        bytes="$(du -sb "$p" 2>/dev/null | cut -f1)"
        if [ -z "$bytes" ]; then
            bytes=0
        fi
        echo "$fc $bytes"
        return 0
    else
        echo "0 0"
        return 0
    fi
}

# ------------------------------------------------------------------------------
# JSON Helper: Collect Lines of JSON Objects into an Array
# ------------------------------------------------------------------------------
_gsv_json_lines_to_array() {
    local tool="${GSV_JSON_TOOL:-}"
    if [ -z "$tool" ] || [ "$tool" = "none" ]; then
        if command -v jq >/dev/null 2>&1; then
            tool="jq"
        elif command -v python3 >/dev/null 2>&1; then
            tool="python3"
        fi
    fi

    if [ "$tool" = "jq" ]; then
        jq -s '.' 2>/dev/null || echo "[]"
    else
        python3 -c '
import sys, json

items = []
for line in sys.stdin:
    line = line.strip()
    if line:
        try:
            items.append(json.loads(line))
        except Exception:
            pass
print(json.dumps(items, indent=2))
' 2>/dev/null || echo "[]"
    fi
}

# ------------------------------------------------------------------------------
# Location Object Builder (review focus 5: strict JSON escaping)
# ------------------------------------------------------------------------------
_gsv_create_location_json() {
    local game_id="$1"
    local game_name="$2"
    local source="$3"
    local app_id="${4:-}"
    local token="$5"
    local rel_path="$6"
    local abs_path="$7"
    local kind="${8:-Directory}"
    local note="${9:-}"
    local origin="${10:-}"
    local scan_root="${11:-}"
    local file_count="${12:-null}"
    local bytes="${13:-null}"
    local now
    now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

    local tool="${GSV_JSON_TOOL:-}"
    if [ -z "$tool" ] || [ "$tool" = "none" ]; then
        if command -v jq >/dev/null 2>&1; then
            tool="jq"
        elif command -v python3 >/dev/null 2>&1; then
            tool="python3"
        fi
    fi

    if [ "$tool" = "jq" ]; then
        jq -c -n \
            --arg gid "$game_id" \
            --arg gname "$game_name" \
            --arg src "$source" \
            --arg aid "$app_id" \
            --arg tok "$token" \
            --arg rel "$rel_path" \
            --arg abs "$abs_path" \
            --arg kind "$kind" \
            --arg note "$note" \
            --arg orig "$origin" \
            --arg sroot "$scan_root" \
            --arg now "$now" \
            --arg fc "$file_count" \
            --arg b "$bytes" \
            '{
                GameId: $gid,
                GameName: $gname,
                Source: $src,
                AppId: $aid,
                InstallDirHint: "",
                Token: $tok,
                RelativePath: $rel,
                AbsolutePath: $abs,
                ResolvedPath: $abs,
                Kind: $kind,
                RegistryKey: "",
                Note: $note,
                Origin: $orig,
                RuleId: "",
                RestoreMode: "",
                InstallDirNames: [],
                FilePatterns: [],
                FileCount: (if $fc == "null" or $fc == "" then null else ($fc | tonumber) end),
                Bytes: (if $b == "null" or $b == "" then null else ($b | tonumber) end),
                ScanRoot: $sroot,
                DiscoveredUtc: $now
            }'
    else
        python3 -c '
import sys, json

fc = sys.argv[12]
b = sys.argv[13]
obj = {
    "GameId": sys.argv[1],
    "GameName": sys.argv[2],
    "Source": sys.argv[3],
    "AppId": sys.argv[4],
    "InstallDirHint": "",
    "Token": sys.argv[5],
    "RelativePath": sys.argv[6],
    "AbsolutePath": sys.argv[7],
    "ResolvedPath": sys.argv[7],
    "Kind": sys.argv[8],
    "RegistryKey": "",
    "Note": sys.argv[9],
    "Origin": sys.argv[10],
    "RuleId": "",
    "RestoreMode": "",
    "InstallDirNames": [],
    "FilePatterns": [],
    "FileCount": int(fc) if fc not in ("null", "", "None") else None,
    "Bytes": int(b) if b not in ("null", "", "None") else None,
    "ScanRoot": sys.argv[11],
    "DiscoveredUtc": sys.argv[14]
}
print(json.dumps(obj))
' "$game_id" "$game_name" "$source" "$app_id" "$token" "$rel_path" "$abs_path" "$kind" "$note" "$origin" "$scan_root" "$file_count" "$bytes" "$now"
    fi
}

# ------------------------------------------------------------------------------
# Title Resolution
# ------------------------------------------------------------------------------
gsv_lookup_title_name() {
    local appid="${1:-}"
    local steamapps_dir="${2:-}"

    if [ -z "$appid" ]; then
        echo ""
        return 0
    fi

    local title=""
    local cfg_dir="${GSV_CONFIG_DIR:-$GSV_ROOT/config}"
    local data_dir="${GSV_DATA_DIR:-$GSV_ROOT/data}"

    local json_file
    for json_file in "$cfg_dir/title-names.json" "$data_dir/title-names.json"; do
        if [ -f "$json_file" ]; then
            if command -v jq >/dev/null 2>&1; then
                title="$(jq -r --arg id "$appid" '.[$id] // .[($id | ascii_downcase)] // empty' "$json_file" 2>/dev/null || true)"
            fi
            if [ -z "$title" ] && command -v python3 >/dev/null 2>&1; then
                title="$(python3 -c '
import sys, json
try:
    with open(sys.argv[1], "r", encoding="utf-8-sig") as f:
        d = json.load(f)
        aid = sys.argv[2]
        print(d.get(aid, d.get(aid.lower(), "")))
except Exception:
    pass
' "$json_file" "$appid" 2>/dev/null || true)"
            fi
            if [ -n "$title" ] && [ "$title" != "null" ]; then
                echo "$title"
                return 0
            fi
        fi
    done

    # Check adjacent appmanifest_<appid>.acf
    if [ -n "$steamapps_dir" ] && [ -f "$steamapps_dir/appmanifest_${appid}.acf" ]; then
        local acf="$steamapps_dir/appmanifest_${appid}.acf"
        local acf_name
        acf_name="$(sed -n 's/^[[:space:]]*"name"[[:space:]]*"\([^"]*\)".*/\1/p' "$acf" 2>/dev/null | head -n 1)"
        if [ -n "$acf_name" ]; then
            echo "$acf_name"
            return 0
        fi
    fi

    # Fallback to AppID
    echo "AppID $appid"
    return 0
}

# ------------------------------------------------------------------------------
# Wine / Proton User Profile Saves Scanner
# ------------------------------------------------------------------------------
_gsv_scan_wine_user_saves() {
    local user_dir="$1"
    local source="$2"
    local appid="${3:-}"
    local title="${4:-}"
    local origin="${5:-proton}"
    local scan_root="${6:-}"

    [ ! -d "$user_dir" ] && return 0

    local gid_prefix
    if [ -n "$appid" ]; then
        gid_prefix="steam-$appid"
    else
        gid_prefix="${origin}"
    fi

    _process_wine_candidate() {
        local candidate="$1"
        local token_type="$2"
        local rel_path="$3"
        local candidate_game="$4"

        [ ! -d "$candidate" ] && return 0
        local cname
        cname="$(basename "$candidate")"
        _gsv_is_pruned "$cname" && return 0

        local fc bytes
        read -r fc bytes <<< "$(_gsv_measure_path "$candidate")"
        if [ "$fc" -gt 0 ]; then
            local game_name="$title"
            if [ -z "$game_name" ]; then
                game_name="$candidate_game"
            fi
            if [ -z "$game_name" ]; then
                game_name="$cname"
            fi
            local gid="$gid_prefix"
            if [ -z "$appid" ]; then
                local slug
                slug="$(echo "$game_name" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')"
                gid="${gid_prefix}-${slug#-}"
            fi

            _gsv_create_location_json \
                "$gid" \
                "$game_name" \
                "$source" \
                "$appid" \
                "$token_type" \
                "$rel_path" \
                "$candidate" \
                "Directory" \
                "${origin} save" \
                "$origin" \
                "$scan_root" \
                "$fc" \
                "$bytes"
        fi
    }

    # 1. AppData/Roaming
    local roaming="$user_dir/AppData/Roaming"
    if [ -d "$roaming" ]; then
        for sub in "$roaming"/*; do
            [ ! -d "$sub" ] && continue
            local sub_name
            sub_name="$(basename "$sub")"
            _gsv_is_pruned "$sub_name" && continue
            _process_wine_candidate "$sub" "APPDATA" "$sub_name" "$sub_name"
        done
    fi

    # 2. AppData/Local
    local local_dir="$user_dir/AppData/Local"
    if [ -d "$local_dir" ]; then
        for sub in "$local_dir"/*; do
            [ ! -d "$sub" ] && continue
            local sub_name
            sub_name="$(basename "$sub")"
            _gsv_is_pruned "$sub_name" && continue

            local has_subdirs=0
            local direct_files
            direct_files="$(find "$sub" -maxdepth 1 -type f 2>/dev/null | head -n 1)"
            if [ -z "$direct_files" ]; then
                for child in "$sub"/*; do
                    if [ -d "$child" ]; then
                        local cname
                        cname="$(basename "$child")"
                        _gsv_is_pruned "$cname" && continue
                        _process_wine_candidate "$child" "LOCALAPPDATA" "$sub_name/$cname" "$cname"
                        has_subdirs=1
                    fi
                done
            fi
            if [ $has_subdirs -eq 0 ]; then
                _process_wine_candidate "$sub" "LOCALAPPDATA" "$sub_name" "$sub_name"
            fi
        done
    fi

    # 3. AppData/LocalLow
    local locallow="$user_dir/AppData/LocalLow"
    if [ -d "$locallow" ]; then
        for sub in "$locallow"/*; do
            [ ! -d "$sub" ] && continue
            local sub_name
            sub_name="$(basename "$sub")"
            _gsv_is_pruned "$sub_name" && continue

            local has_subdirs=0
            local direct_files
            direct_files="$(find "$sub" -maxdepth 1 -type f 2>/dev/null | head -n 1)"
            if [ -z "$direct_files" ]; then
                for child in "$sub"/*; do
                    if [ -d "$child" ]; then
                        local cname
                        cname="$(basename "$child")"
                        _gsv_is_pruned "$cname" && continue
                        _process_wine_candidate "$child" "LOCALLOW" "$sub_name/$cname" "$cname"
                        has_subdirs=1
                    fi
                done
            fi
            if [ $has_subdirs -eq 0 ]; then
                _process_wine_candidate "$sub" "LOCALLOW" "$sub_name" "$sub_name"
            fi
        done
    fi

    # 4. Documents (and Documents/My Games)
    local docs="$user_dir/Documents"
    if [ -d "$docs" ]; then
        if [ -d "$docs/My Games" ]; then
            for sub in "$docs/My Games"/*; do
                [ ! -d "$sub" ] && continue
                local sub_name
                sub_name="$(basename "$sub")"
                _gsv_is_pruned "$sub_name" && continue
                _process_wine_candidate "$sub" "DOCUMENTS" "My Games/$sub_name" "$sub_name"
            done
        fi
        for sub in "$docs"/*; do
            [ ! -d "$sub" ] && continue
            local sub_name
            sub_name="$(basename "$sub")"
            [ "$sub_name" = "My Games" ] && continue
            _gsv_is_pruned "$sub_name" && continue
            _process_wine_candidate "$sub" "DOCUMENTS" "$sub_name" "$sub_name"
        done
    fi

    # 5. Saved Games
    local saved_games="$user_dir/Saved Games"
    if [ -d "$saved_games" ]; then
        for sub in "$saved_games"/*; do
            [ ! -d "$sub" ] && continue
            local sub_name
            sub_name="$(basename "$sub")"
            _gsv_is_pruned "$sub_name" && continue

            local has_subdirs=0
            local direct_files
            direct_files="$(find "$sub" -maxdepth 1 -type f 2>/dev/null | head -n 1)"
            if [ -z "$direct_files" ]; then
                for child in "$sub"/*; do
                    if [ -d "$child" ]; then
                        local cname
                        cname="$(basename "$child")"
                        _gsv_is_pruned "$cname" && continue
                        _process_wine_candidate "$child" "SAVEDGAMES" "$sub_name/$cname" "$cname"
                        has_subdirs=1
                    fi
                done
            fi
            if [ $has_subdirs -eq 0 ]; then
                _process_wine_candidate "$sub" "SAVEDGAMES" "$sub_name" "$sub_name"
            fi
        done
    fi
}

# ------------------------------------------------------------------------------
# 1. Steam Proton Scanner (Native & Flatpak)
# ------------------------------------------------------------------------------
gsv_scan_steam_proton() {
    local -a roots=("$@")
    if [ ${#roots[@]} -eq 0 ]; then
        if [ -n "${GSV_STEAM_COMPATDATA_DIRS:-}" ]; then
            IFS=':' read -ra roots <<< "$GSV_STEAM_COMPATDATA_DIRS"
        else
            roots=(
                "$HOME/.steam/steam/steamapps/compatdata"
                "$HOME/.local/share/Steam/steamapps/compatdata"
                "$HOME/.steam/root/steamapps/compatdata"
                "$HOME/.var/app/com.valvesoftware.Steam/.steam/steam/steamapps/compatdata"
                "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/compatdata"
            )
            # Inspect libraryfolders.vdf for additional steam libraries
            local lf
            for lf in "$HOME/.steam/steam/steamapps/libraryfolders.vdf" \
                      "$HOME/.local/share/Steam/steamapps/libraryfolders.vdf" \
                      "$HOME/.var/app/com.valvesoftware.Steam/.steam/steam/steamapps/libraryfolders.vdf"; do
                if [ -f "$lf" ]; then
                    while IFS= read -r lib_path; do
                        if [ -n "$lib_path" ] && [ -d "$lib_path/steamapps/compatdata" ]; then
                            roots+=("$lib_path/steamapps/compatdata")
                        fi
                    done < <(grep -oP '"path"\s*"\K[^"]+' "$lf" 2>/dev/null || true)
                fi
            done
        fi
    fi

    {
        local root
        for root in "${roots[@]}"; do
            [ ! -d "$root" ] && continue
            local steamapps_dir
            steamapps_dir="$(dirname "$root")"

            local appid_dir
            for appid_dir in "$root"/*; do
                [ ! -d "$appid_dir" ] && continue
                local appid
                appid="$(basename "$appid_dir")"
                # Steam AppIDs must be numeric
                [[ ! "$appid" =~ ^[0-9]+$ ]] && continue

                # Review Focus 2: Ignore broken/incomplete prefixes gracefully
                local drive_c="$appid_dir/pfx/drive_c"
                [ ! -d "$drive_c" ] && continue
                local users_dir="$drive_c/users"
                [ ! -d "$users_dir" ] && continue

                local title
                title="$(gsv_lookup_title_name "$appid" "$steamapps_dir")"

                local udir
                for udir in "$users_dir"/*; do
                    [ ! -d "$udir" ] && continue
                    local uname
                    uname="$(basename "$udir")"
                    [ "$uname" = "Public" ] || [ "$uname" = "Default" ] && continue
                    _gsv_scan_wine_user_saves "$udir" "SteamProton" "$appid" "$title" "proton" "$root"
                done
            done
        done
    } | _gsv_json_lines_to_array
}

# ------------------------------------------------------------------------------
# 2. Native Games Scanner
# ------------------------------------------------------------------------------
gsv_scan_native_games() {
    local share_dir="${1:-${XDG_DATA_HOME:-$HOME/.local/share}}"
    local config_dir="${2:-${XDG_CONFIG_HOME:-$HOME/.config}}"

    _scan_native_dir() {
        local base_dir="$1"
        local token_type="$2"
        [ ! -d "$base_dir" ] && return 0

        local game_dir
        for game_dir in "$base_dir"/*; do
            [ ! -d "$game_dir" ] && continue
            local gname
            gname="$(basename "$game_dir")"
            _gsv_is_pruned "$gname" && continue

            local is_save=0
            local found_save
            found_save="$(find "$game_dir" -maxdepth 3 -type f \( \
                -iname "*.sav" -o -iname "*.save" -o -iname "*.dat" -o -iname "*.sl2" \
                -o -iname "*.celeste" -o -iname "*.srm" -o -iname "*.state" \
            \) 2>/dev/null | head -n 1)"
            if [ -n "$found_save" ]; then
                is_save=1
            else
                local found_subdir
                found_subdir="$(find "$game_dir" -maxdepth 2 -type d \( \
                    -iname "save" -o -iname "saves" -o -iname "savedata" -o -iname "savegames" -o -iname "gamesaves" \
                \) 2>/dev/null | head -n 1)"
                if [ -n "$found_subdir" ]; then
                    is_save=1
                fi
            fi

            if [ $is_save -eq 1 ]; then
                local fc bytes
                read -r fc bytes <<< "$(_gsv_measure_path "$game_dir")"
                if [ "$fc" -gt 0 ]; then
                    local slug
                    slug="$(echo "$gname" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')"
                    local gid="native-${slug#-}"
                    _gsv_create_location_json \
                        "$gid" \
                        "$gname" \
                        "Native" \
                        "" \
                        "$token_type" \
                        "$gname" \
                        "$game_dir" \
                        "Directory" \
                        "native save" \
                        "native" \
                        "$base_dir" \
                        "$fc" \
                        "$bytes"
                fi
            fi
        done
    }

    {
        _scan_native_dir "$share_dir" "XDG_DATA_HOME"
        _scan_native_dir "$config_dir" "XDG_CONFIG_HOME"
    } | _gsv_json_lines_to_array
}

# ------------------------------------------------------------------------------
# 3. Wine, Lutris, and Heroic Scanner
# ------------------------------------------------------------------------------
gsv_scan_wine_lutris_heroic() {
    local wine_root=""
    local games_root=""
    local heroic_root=""
    local -a heroic_dirs=()
    local -a bottle_dirs=()

    if [ $# -gt 0 ]; then
        wine_root="${1:-}"
        games_root="${2:-}"
        heroic_root="${3:-}"
        [ -n "$heroic_root" ] && heroic_dirs+=("$heroic_root")
        if [ -n "${4:-}" ]; then
            bottle_dirs+=("$4")
        fi
    else
        wine_root="$HOME/.wine"
        games_root="$HOME/Games"
        heroic_root="$HOME/.config/heroic/Prefixes"
        [ -d "$heroic_root" ] && heroic_dirs+=("$heroic_root")
        if [ -d "$HOME/.var/app/com.heroicgameslauncher.hgl/config/heroic/Prefixes" ]; then
            heroic_dirs+=("$HOME/.var/app/com.heroicgameslauncher.hgl/config/heroic/Prefixes")
        fi
        bottle_dirs=(
            "$HOME/.var/app/com.usebottles.bottles/data/bottles/bottles"
            "$HOME/.local/share/bottles/bottles"
        )
    fi

    {
        # 1. Wine prefix
        if [ -n "$wine_root" ] && [ -d "$wine_root/drive_c/users" ]; then
            local udir
            for udir in "$wine_root/drive_c/users"/*; do
                [ ! -d "$udir" ] && continue
                local uname="$(basename "$udir")"
                [ "$uname" = "Public" ] || [ "$uname" = "Default" ] && continue
                _gsv_scan_wine_user_saves "$udir" "Wine" "" "" "wine" "$wine_root"
            done
        fi

        # 2. Lutris prefixes (~/Games/<game>/drive_c/users or ~/Games/<game>/prefix/drive_c/users)
        if [ -n "$games_root" ] && [ -d "$games_root" ]; then
            local gdir
            for gdir in "$games_root"/*; do
                [ ! -d "$gdir" ] && continue
                local gname="$(basename "$gdir")"
                _gsv_is_pruned "$gname" && continue

                local pfx_users=""
                if [ -d "$gdir/drive_c/users" ]; then
                    pfx_users="$gdir/drive_c/users"
                elif [ -d "$gdir/prefix/drive_c/users" ]; then
                    pfx_users="$gdir/prefix/drive_c/users"
                fi

                if [ -n "$pfx_users" ]; then
                    for udir in "$pfx_users"/*; do
                        [ ! -d "$udir" ] && continue
                        local uname="$(basename "$udir")"
                        [ "$uname" = "Public" ] || [ "$uname" = "Default" ] && continue
                        _gsv_scan_wine_user_saves "$udir" "Lutris" "" "$gname" "lutris" "$gdir"
                    done
                fi
            done
        fi

        # 3. Heroic prefixes (~/.config/heroic/Prefixes/<game>/pfx/drive_c/users or ~/.var/app/...)
        local hroot
        for hroot in "${heroic_dirs[@]}"; do
            [ ! -d "$hroot" ] && continue
            local pdir
            for pdir in "$hroot"/*; do
                [ ! -d "$pdir" ] && continue
                local pname="$(basename "$pdir")"
                _gsv_is_pruned "$pname" && continue

                local pfx_users=""
                if [ -d "$pdir/pfx/drive_c/users" ]; then
                    pfx_users="$pdir/pfx/drive_c/users"
                elif [ -d "$pdir/drive_c/users" ]; then
                    pfx_users="$pdir/drive_c/users"
                fi

                if [ -n "$pfx_users" ]; then
                    for udir in "$pfx_users"/*; do
                        [ ! -d "$udir" ] && continue
                        local uname="$(basename "$udir")"
                        [ "$uname" = "Public" ] || [ "$uname" = "Default" ] && continue
                        _gsv_scan_wine_user_saves "$udir" "Heroic" "" "$pname" "heroic" "$pdir"
                    done
                fi
            done
        done

        # 4. Bottles prefixes
        local broot
        for broot in "${bottle_dirs[@]}"; do
            [ ! -d "$broot" ] && continue
            local bdir
            for bdir in "$broot"/*; do
                [ ! -d "$bdir" ] && continue
                local bname="$(basename "$bdir")"
                _gsv_is_pruned "$bname" && continue
                if [ -d "$bdir/drive_c/users" ]; then
                    for udir in "$bdir/drive_c/users"/*; do
                        [ ! -d "$udir" ] && continue
                        local uname="$(basename "$udir")"
                        [ "$uname" = "Public" ] || [ "$uname" = "Default" ] && continue
                        _gsv_scan_wine_user_saves "$udir" "Bottles" "" "$bname" "bottles" "$bdir"
                    done
                fi
            done
        done
    } | _gsv_json_lines_to_array
}

# ------------------------------------------------------------------------------
# 4. Emulators Scanner
# ------------------------------------------------------------------------------
gsv_scan_emulators() {
    local emu_base="${1:-}"

    _scan_ryujinx() {
        local ryu_root="$1"
        [ ! -d "$ryu_root" ] && return 0
        local prof
        for prof in "$ryu_root"/*; do
            [ ! -d "$prof" ] && continue
            local title_dir
            for title_dir in "$prof"/*; do
                [ ! -d "$title_dir" ] && continue
                local title_id="$(basename "$title_dir")"
                if [[ "$title_id" =~ ^[0-9a-fA-F]{16}$ ]]; then
                    local fc bytes
                    read -r fc bytes <<< "$(_gsv_measure_path "$title_dir")"
                    if [ "$fc" -gt 0 ]; then
                        local gname
                        gname="$(gsv_lookup_title_name "$title_id")"
                        if [ -z "$gname" ] || [ "$gname" = "AppID $title_id" ]; then
                            gname="Switch Title $title_id"
                        fi
                        _gsv_create_location_json \
                            "ryujinx-$title_id" \
                            "$gname" \
                            "Emulator (Ryujinx)" \
                            "$title_id" \
                            "XDG_CONFIG_HOME" \
                            "Ryujinx/bis/user/save/$(basename "$prof")/$title_id" \
                            "$title_dir" \
                            "Directory" \
                            "Ryujinx save" \
                            "emulator" \
                            "$ryu_root" \
                            "$fc" \
                            "$bytes"
                    fi
                fi
            done
        done
    }

    _scan_rpcs3() {
        local rpcs3_root="$1"
        [ ! -d "$rpcs3_root" ] && return 0
        local hdd0="$rpcs3_root/dev_hdd0/home"
        [ ! -d "$hdd0" ] && return 0
        local user_dir
        for user_dir in "$hdd0"/*; do
            [ ! -d "$user_dir/savedata" ] && continue
            local save_dir
            for save_dir in "$user_dir/savedata"/*; do
                [ ! -d "$save_dir" ] && continue
                local tid="$(basename "$save_dir")"
                local fc bytes
                read -r fc bytes <<< "$(_gsv_measure_path "$save_dir")"
                if [ "$fc" -gt 0 ]; then
                    _gsv_create_location_json \
                        "rpcs3-${tid,,}" \
                        "RPCS3 $tid" \
                        "Emulator (RPCS3)" \
                        "$tid" \
                        "XDG_CONFIG_HOME" \
                        "rpcs3/dev_hdd0/home/$(basename "$user_dir")/savedata/$tid" \
                        "$save_dir" \
                        "Directory" \
                        "RPCS3 save" \
                        "emulator" \
                        "$rpcs3_root" \
                        "$fc" \
                        "$bytes"
                fi
            done
        done
    }

    _scan_pcsx2() {
        local pcsx2_root="$1"
        [ ! -d "$pcsx2_root" ] && return 0
        local memcards="$pcsx2_root/memcards"
        if [ -d "$memcards" ]; then
            local fc bytes
            read -r fc bytes <<< "$(_gsv_measure_path "$memcards")"
            if [ "$fc" -gt 0 ]; then
                _gsv_create_location_json \
                    "pcsx2-memcards" \
                    "PCSX2 Memory Cards" \
                    "Emulator (PCSX2)" \
                    "" \
                    "XDG_CONFIG_HOME" \
                    "PCSX2/memcards" \
                    "$memcards" \
                    "Directory" \
                    "PCSX2 memcards" \
                    "emulator" \
                    "$pcsx2_root" \
                    "$fc" \
                    "$bytes"
            fi
        fi
    }

    _scan_dolphin() {
        local dol_root="$1"
        [ ! -d "$dol_root" ] && return 0
        local sub
        for sub in "GC" "Wii"; do
            if [ -d "$dol_root/$sub" ]; then
                local fc bytes
                read -r fc bytes <<< "$(_gsv_measure_path "$dol_root/$sub")"
                if [ "$fc" -gt 0 ]; then
                    _gsv_create_location_json \
                        "dolphin-${sub,,}" \
                        "Dolphin $sub Saves" \
                        "Emulator (Dolphin)" \
                        "" \
                        "XDG_DATA_HOME" \
                        "dolphin-emu/$sub" \
                        "$dol_root/$sub" \
                        "Directory" \
                        "Dolphin $sub saves" \
                        "emulator" \
                        "$dol_root" \
                        "$fc" \
                        "$bytes"
                fi
            fi
        done
    }

    _scan_duckstation() {
        local duck_root="$1"
        [ ! -d "$duck_root/memcards" ] && return 0
        local fc bytes
        read -r fc bytes <<< "$(_gsv_measure_path "$duck_root/memcards")"
        if [ "$fc" -gt 0 ]; then
            _gsv_create_location_json \
                "duckstation-memcards" \
                "DuckStation Memory Cards" \
                "Emulator (DuckStation)" \
                "" \
                "XDG_DATA_HOME" \
                "duckstation/memcards" \
                "$duck_root/memcards" \
                "Directory" \
                "DuckStation memcards" \
                "emulator" \
                "$duck_root" \
                "$fc" \
                "$bytes"
        fi
    }

    _scan_retroarch() {
        local retro_root="$1"
        [ ! -d "$retro_root/saves" ] && return 0
        local fc bytes
        read -r fc bytes <<< "$(_gsv_measure_path "$retro_root/saves")"
        if [ "$fc" -gt 0 ]; then
            _gsv_create_location_json \
                "retroarch-saves" \
                "RetroArch Saves" \
                "Emulator (RetroArch)" \
                "" \
                "XDG_CONFIG_HOME" \
                "retroarch/saves" \
                "$retro_root/saves" \
                "Directory" \
                "RetroArch saves" \
                "emulator" \
                "$retro_root" \
                "$fc" \
                "$bytes"
        fi
    }

    {
        if [ -n "$emu_base" ]; then
            _scan_ryujinx "$emu_base/Ryujinx/bis/user/save"
            _scan_rpcs3 "$emu_base/rpcs3"
            _scan_pcsx2 "$emu_base/PCSX2"
            _scan_dolphin "$emu_base/dolphin-emu"
            _scan_duckstation "$emu_base/duckstation"
            _scan_retroarch "$emu_base/retroarch"
        else
            _scan_ryujinx "$HOME/.config/Ryujinx/bis/user/save"
            _scan_ryujinx "$HOME/.var/app/org.ryujinx.Ryujinx/config/Ryujinx/bis/user/save"
            _scan_rpcs3 "$HOME/.config/rpcs3"
            _scan_rpcs3 "$HOME/.var/app/net.rpcs3.RPCS3/config/rpcs3"
            _scan_pcsx2 "$HOME/.config/PCSX2"
            _scan_pcsx2 "$HOME/.var/app/net.pcsx2.PCSX2/config/PCSX2"
            _scan_dolphin "$HOME/.local/share/dolphin-emu"
            _scan_dolphin "$HOME/.var/app/org.DolphinEmu.dolphin-emu/data/dolphin-emu"
            _scan_duckstation "$HOME/.local/share/duckstation"
            _scan_duckstation "$HOME/.var/app/org.duckstation.DuckStation/data/duckstation"
            _scan_retroarch "$HOME/.config/retroarch"
            _scan_retroarch "$HOME/.var/app/org.libretro.RetroArch/config/retroarch"
        fi
    } | _gsv_json_lines_to_array
}

# ------------------------------------------------------------------------------
# 5. Deep Scanner for Custom Folders
# ------------------------------------------------------------------------------
_gsv_deep_walk() {
    local dir="$1"
    local depth="$2"
    local max_depth="$3"
    local scan_root="$4"

    [ ! -d "$dir" ] && return 0
    local dname
    dname="$(basename "$dir")"

    if _gsv_is_pruned "$dname"; then
        return 0
    fi

    local is_save_dir=0
    local game_name=""
    local dlower="${dname,,}"

    # 1. Directory literally named save / saves / savedata / etc.
    if [[ "$dlower" =~ ^(save|saves|savedata|savegames|gamesaves)$ ]]; then
        local parent_dir
        parent_dir="$(dirname "$dir")"
        game_name="$(basename "$parent_dir")"
        is_save_dir=1
    else
        # 2. Directory contains save file extensions directly
        local match_save_files
        match_save_files="$(find "$dir" -maxdepth 1 -type f \( \
            -iname "*.sav" -o -iname "*.save" -o -iname "*.sl2" -o -iname "*.srm" \
            -o -iname "*.state" -o -iname "*.dat" \
        \) 2>/dev/null | head -n 1)"
        if [ -n "$match_save_files" ]; then
            game_name="$dname"
            is_save_dir=1
        fi
    fi

    if [ $is_save_dir -eq 1 ] && [ -n "$game_name" ]; then
        local fc bytes
        read -r fc bytes <<< "$(_gsv_measure_path "$dir")"
        if [ "$fc" -gt 0 ]; then
            local tok_full
            tok_full="$(gsv_path_to_token "$dir")"
            local token="" rel=""
            if [[ "$tok_full" =~ ^%([A-Z0-9_]+)%(/(.*))?$ ]]; then
                token="${BASH_REMATCH[1]}"
                rel="${BASH_REMATCH[3]:-}"
            fi
            local gid
            gid="deep-$(echo "$game_name" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')"
            _gsv_create_location_json \
                "${gid#-}" \
                "$game_name" \
                "Deep scan" \
                "" \
                "$token" \
                "$rel" \
                "$dir" \
                "Directory" \
                "deep scan" \
                "deep-scan" \
                "$scan_root" \
                "$fc" \
                "$bytes"
            return 0
        fi
    fi

    if [ "$depth" -ge "$max_depth" ]; then
        return 0
    fi

    local child
    for child in "$dir"/*; do
        if [ -d "$child" ] && [ ! -L "$child" ]; then
            _gsv_deep_walk "$child" $((depth + 1)) "$max_depth" "$scan_root"
        fi
    done
}

gsv_deep_scan_folder() {
    local folder_path="${1:-}"
    local max_depth="${2:-8}"

    [ -z "$folder_path" ] && { echo "[]"; return 0; }
    [ ! -d "$folder_path" ] && { echo "[]"; return 0; }

    {
        _gsv_deep_walk "$folder_path" 0 "$max_depth" "$folder_path"
    } | _gsv_json_lines_to_array
}

# ------------------------------------------------------------------------------
# 6. Aggregate All Scans
# ------------------------------------------------------------------------------
gsv_scan_all() {
    local proton native wine emu
    proton="$(gsv_scan_steam_proton)"
    native="$(gsv_scan_native_games)"
    wine="$(gsv_scan_wine_lutris_heroic)"
    emu="$(gsv_scan_emulators)"

    local tool="${GSV_JSON_TOOL:-}"
    if [ -z "$tool" ] || [ "$tool" = "none" ]; then
        if command -v jq >/dev/null 2>&1; then
            tool="jq"
        elif command -v python3 >/dev/null 2>&1; then
            tool="python3"
        fi
    fi

    if [ "$tool" = "jq" ]; then
        jq -s '
            [.[][]] |
            unique_by(.ResolvedPath // .AbsolutePath)
        ' <(echo "$proton") <(echo "$native") <(echo "$wine") <(echo "$emu") 2>/dev/null || echo "[]"
    else
        python3 -c '
import sys, json

results = []
seen = set()
for arg in sys.argv[1:]:
    if not arg.strip():
        continue
    try:
        items = json.loads(arg)
        for item in items:
            key = item.get("ResolvedPath") or item.get("AbsolutePath") or ""
            if key and key not in seen:
                seen.add(key)
                results.append(item)
    except Exception:
        pass

print(json.dumps(results, indent=2))
' "$proton" "$native" "$wine" "$emu" 2>/dev/null || echo "[]"
    fi
}

# ------------------------------------------------------------------------------
# 7. Update Scan Database
# ------------------------------------------------------------------------------
gsv_update_scan_database() {
    local locs_input="${1:-[]}"
    local roots_input="${2:-[]}"
    local db_file="${GSV_CONFIG_DIR:-$GSV_ROOT/config}/scan-database.json"

    mkdir -p "$(dirname "$db_file")" 2>/dev/null || true

    python3 -c '
import sys, json, os, datetime

db_path = sys.argv[1]
locs_raw = sys.argv[2]
roots_raw = sys.argv[3] if len(sys.argv) > 3 else "[]"

now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

if os.path.isfile(locs_raw):
    with open(locs_raw, "r", encoding="utf-8-sig") as f:
        new_locs = json.load(f)
else:
    new_locs = json.loads(locs_raw) if locs_raw.strip() else []

if roots_raw.strip() and os.path.isfile(roots_raw):
    with open(roots_raw, "r", encoding="utf-8-sig") as f:
        new_roots = json.load(f)
elif roots_raw.strip():
    new_roots = json.loads(roots_raw)
else:
    new_roots = []

if not new_roots:
    new_roots = list({l.get("ScanRoot") for l in new_locs if l.get("ScanRoot")})

if os.path.isfile(db_path):
    try:
        with open(db_path, "r", encoding="utf-8-sig") as f:
            db = json.load(f)
    except Exception:
        db = {}
else:
    db = {}

if "Version" not in db:
    db["Version"] = 1
if "Tool" not in db:
    db["Tool"] = "GameSaveVault"
if "ToolVersion" not in db:
    db["ToolVersion"] = "1.0.0"
if "CreatedUtc" not in db:
    db["CreatedUtc"] = now
db["UpdatedUtc"] = now
if "IncludeStandard" not in db:
    db["IncludeStandard"] = True

existing_locs = db.get("Locations", [])
existing_roots = db.get("Roots", [])

def loc_key(loc):
    tok = loc.get("Token", "")
    rel = loc.get("RelativePath", "")
    if tok:
        return f"{tok}|{rel}".lower()
    p = loc.get("AbsolutePath") or loc.get("ResolvedPath") or ""
    return f"abs|{p}".lower()

loc_map = {}
order = []
for l in existing_locs:
    k = loc_key(l)
    if k:
        if k not in loc_map:
            order.append(k)
        loc_map[k] = l

for l in new_locs:
    k = loc_key(l)
    if k:
        if k not in loc_map:
            order.append(k)
        loc_map[k] = l

final_locs = [loc_map[k] for k in order]

root_map = {r["Path"]: r for r in existing_roots if "Path" in r}
for r_path in new_roots:
    root_map[r_path] = {
        "Path": r_path,
        "ScannedUtc": now,
        "LocationCount": 0
    }

for r_path, r_obj in root_map.items():
    cnt = sum(1 for l in final_locs if l.get("ScanRoot") == r_path or (l.get("ResolvedPath") or "").startswith(r_path))
    r_obj["LocationCount"] = cnt

db["Roots"] = list(root_map.values())
db["Locations"] = final_locs

tmp_path = db_path + f".tmp.{os.getpid()}"
with open(tmp_path, "w", encoding="utf-8") as f:
    json.dump(db, f, indent=2)
    f.write("\n")
os.replace(tmp_path, db_path)
' "$db_file" "$locs_input" "$roots_input"
}
