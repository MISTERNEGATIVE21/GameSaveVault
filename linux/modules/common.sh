#!/usr/bin/env bash
# ==============================================================================
# linux/modules/common.sh
# Core environment, JSON engine, path resolution, and logging for GameSaveVault.
# ==============================================================================

# Guard against duplicate inclusion
if [ -n "${_GSV_COMMON_LOADED:-}" ]; then
    return 0
fi
_GSV_COMMON_LOADED=1

# Global configuration defaults
GSV_ROOT="${GSV_ROOT:-}"
GSV_LINUX_DIR="${GSV_LINUX_DIR:-}"
GSV_MODULES_DIR="${GSV_MODULES_DIR:-}"
GSV_CONFIG_DIR="${GSV_CONFIG_DIR:-}"
GSV_DATA_DIR="${GSV_DATA_DIR:-}"
GSV_JSON_TOOL="${GSV_JSON_TOOL:-}"
GSV_VAULT_PATH="${GSV_VAULT_PATH:-}"
GSV_FORCE_COLOR="${GSV_FORCE_COLOR:-0}"

# ------------------------------------------------------------------------------
# Environment Initialization
# ------------------------------------------------------------------------------
gsv_init_env() {
    # Resolve repository root from location of this script if not already set
    if [ -z "${GSV_ROOT:-}" ] || [ ! -d "${GSV_ROOT:-}" ]; then
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        # linux/modules -> repository root is ../..
        GSV_ROOT="$(cd "$script_dir/../.." && pwd)"
    fi
    export GSV_ROOT

    GSV_LINUX_DIR="${GSV_LINUX_DIR:-$GSV_ROOT/linux}"
    GSV_MODULES_DIR="${GSV_MODULES_DIR:-$GSV_ROOT/linux/modules}"
    GSV_CONFIG_DIR="${GSV_CONFIG_DIR:-$GSV_ROOT/config}"
    GSV_DATA_DIR="${GSV_DATA_DIR:-$GSV_ROOT/data}"
    export GSV_LINUX_DIR GSV_MODULES_DIR GSV_CONFIG_DIR GSV_DATA_DIR

    # Detect JSON processing tool (jq preferred, python3 fallback)
    if [ -z "${GSV_JSON_TOOL:-}" ]; then
        if command -v jq >/dev/null 2>&1; then
            GSV_JSON_TOOL="jq"
        elif command -v python3 >/dev/null 2>&1; then
            GSV_JSON_TOOL="python3"
        else
            GSV_JSON_TOOL="none"
        fi
    fi
    export GSV_JSON_TOOL

    # Ensure config directory exists
    mkdir -p "$GSV_CONFIG_DIR" 2>/dev/null || true
}

# Auto-initialize environment on module load
gsv_init_env

# ------------------------------------------------------------------------------
# JSON Operations
# ------------------------------------------------------------------------------

# gsv_json_get(json_file, query)
# Evaluates filter using jq or python3 fallback. Return JSON string or value.
gsv_json_get() {
    local file="$1"
    local query="${2:-.}"

    if [ ! -f "$file" ]; then
        echo "null"
        return 1
    fi

    local tool="${GSV_JSON_TOOL:-}"
    if [ -z "$tool" ]; then
        if command -v jq >/dev/null 2>&1; then
            tool="jq"
        elif command -v python3 >/dev/null 2>&1; then
            tool="python3"
        else
            tool="none"
        fi
    fi

    case "$tool" in
        jq)
            jq -r "$query" "$file" 2>/dev/null || echo "null"
            ;;
        python3)
            python3 -c '
import sys, json, re

file_path = sys.argv[1]
query = sys.argv[2] if len(sys.argv) > 2 else "."

try:
    with open(file_path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    print("null")
    sys.exit(0)

pattern = re.compile(r"""
    \["([^"]+)"\]         | # 1: ["double quoted"]
    \x27?\[\x27([^\x27]+)\x27\]| # 2: [\x27single quoted\x27]
    \[([0-9]+)\]          | # 3: [0] array index
    (\[\])                | # 4: [] array spread
    \.?"([^"]+)"          | # 5: ."double quoted"
    \.?\x27([^\x27]+)\x27 | # 6: .\x27single quoted\x27
    \.?([a-zA-Z0-9_\-]+)    # 7: .standard_key
""", re.VERBOSE)

def eval_filter(data, expr):
    expr = expr.strip()
    if not expr or expr == ".":
        return data
    curr = data
    for m in pattern.finditer(expr):
        g1, g2, g3, g4, g5, g6, g7 = m.groups()
        prop = g1 or g2 or g5 or g6 or g7
        if prop:
            if isinstance(curr, dict) and prop in curr:
                curr = curr[prop]
            else:
                return None
        elif g3 is not None:
            i = int(g3)
            if isinstance(curr, list) and 0 <= i < len(curr):
                curr = curr[i]
            else:
                return None
    return curr

val = eval_filter(data, query)
if val is None:
    print("null")
elif isinstance(val, str):
    print(val)
elif isinstance(val, bool):
    print("true" if val else "false")
elif isinstance(val, (int, float)):
    print(val)
elif isinstance(val, list) and query.endswith("[]"):
    for item in val:
        if isinstance(item, str):
            print(item)
        else:
            print(json.dumps(item))
else:
    print(json.dumps(val))
' "$file" "$query" 2>/dev/null || echo "null"
            ;;
        *)
            echo "null"
            return 1
            ;;
    esac
}

# gsv_json_set(json_file, key, json_value)
# Updates key in JSON file atomically using a temporary file.
gsv_json_set() {
    local file="$1"
    local key="$2"
    local val="$3"

    local dir
    dir="$(dirname "$file")"
    mkdir -p "$dir" 2>/dev/null || true

    if [ ! -f "$file" ] || [ ! -s "$file" ]; then
        echo '{}' > "$file"
    fi

    local tmp
    tmp="$(mktemp "${file}.tmp.XXXXXX" 2>/dev/null || echo "${file}.tmp.$$.$RANDOM")"

    local tool="${GSV_JSON_TOOL:-}"
    if [ -z "$tool" ]; then
        if command -v jq >/dev/null 2>&1; then
            tool="jq"
        elif command -v python3 >/dev/null 2>&1; then
            tool="python3"
        else
            tool="none"
        fi
    fi

    local status=0
    case "$tool" in
        jq)
            local clean_key="${key#.}"
            local jq_path
            jq_path="$(echo "$clean_key" | awk -F. '{
                printf "["
                for (i=1; i<=NF; i++) {
                    printf "\"%s\"%s", $i, (i==NF ? "" : ", ")
                }
                printf "]"
            }')"

            if echo "$val" | jq . >/dev/null 2>&1; then
                jq --argjson p "$jq_path" --argjson v "$val" 'setpath($p; $v)' "$file" > "$tmp" || status=$?
            else
                jq --argjson p "$jq_path" --arg v "$val" 'setpath($p; $v)' "$file" > "$tmp" || status=$?
            fi
            ;;
        python3)
            python3 -c '
import sys, json

file_path = sys.argv[1]
raw_key = sys.argv[2].lstrip(".")
raw_val = sys.argv[3]
tmp_path = sys.argv[4]

try:
    with open(file_path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    data = {}

try:
    val = json.loads(raw_val)
except Exception:
    val = raw_val

keys = [k for k in raw_key.split(".") if k]
curr = data
for k in keys[:-1]:
    if k not in curr or not isinstance(curr[k], dict):
        curr[k] = {}
    curr = curr[k]
curr[keys[-1]] = val

with open(tmp_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
' "$file" "$key" "$val" "$tmp" || status=$?
            ;;
        *)
            status=1
            ;;
    esac

    if [ $status -eq 0 ] && [ -s "$tmp" ]; then
        mv -f "$tmp" "$file"
        return 0
    else
        rm -f "$tmp"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Vault Path Resolution
# ------------------------------------------------------------------------------

# gsv_resolve_vault_path([override_path])
# Resolution priority:
#   1. CLI parameter override
#   2. Mounted external drive containing GameSaveVault/
#   3. config/settings.json BackupRoot
#   4. Default: ~/GameSaveVault
gsv_resolve_vault_path() {
    local override="${1:-}"

    # 1. CLI parameter override
    if [ -n "$override" ]; then
        local resolved_override="${override/#\~/$HOME}"
        GSV_VAULT_PATH="$resolved_override"
        echo "$resolved_override"
        return 0
    fi

    # 2. Mounted external drive containing GameSaveVault/
    local user_name="${USER:-$(id -un 2>/dev/null || echo "user")}"
    local mount_roots
    if [ -n "${GSV_MOUNT_ROOTS+x}" ] && [ ${#GSV_MOUNT_ROOTS[@]} -gt 0 ]; then
        mount_roots=("${GSV_MOUNT_ROOTS[@]}")
    else
        mount_roots=("/run/media/$user_name" "/media/$user_name" "/mnt")
    fi

    local root_candidate
    for root_candidate in "${mount_roots[@]}"; do
        if [ -d "$root_candidate" ]; then
            local drive
            for drive in "$root_candidate"/*; do
                if [ -d "$drive/GameSaveVault" ] && [ -w "$drive/GameSaveVault" ]; then
                    GSV_VAULT_PATH="$drive/GameSaveVault"
                    echo "$drive/GameSaveVault"
                    return 0
                fi
            done
        fi
    done

    # 3. Path defined in config/settings.json (BackupRoot)
    local settings_file="${GSV_CONFIG_DIR:-$GSV_ROOT/config}/settings.json"
    if [ -f "$settings_file" ]; then
        local backup_root
        backup_root="$(gsv_json_get "$settings_file" ".BackupRoot" 2>/dev/null)"
        if [ -n "$backup_root" ] && [ "$backup_root" != "null" ]; then
            # Ignore Windows paths with drive letters (e.g. D:\...)
            if [[ ! "$backup_root" =~ ^[a-zA-Z]: ]]; then
                backup_root="${backup_root/#\~/$HOME}"
                # Check if backup_root is usable (writable directory or writable parent)
                local is_usable=0
                if [ -e "$backup_root" ]; then
                    if [ -d "$backup_root" ] && [ -w "$backup_root" ]; then
                        is_usable=1
                    fi
                else
                    local parent="$backup_root"
                    while [ -n "$parent" ] && [ "$parent" != "/" ] && [ "$parent" != "." ]; do
                        parent="$(dirname "$parent")"
                        if [ -e "$parent" ]; then
                            if [ -d "$parent" ] && [ -w "$parent" ]; then
                                is_usable=1
                            fi
                            break
                        fi
                    done
                fi

                if [ $is_usable -eq 1 ]; then
                    GSV_VAULT_PATH="$backup_root"
                    echo "$backup_root"
                    return 0
                else
                    gsv_log_warn "Configured BackupRoot '$backup_root' is missing or not writable; falling back to default vault." >&2
                fi
            fi
        fi
    fi

    # 4. Default fallback: ~/GameSaveVault
    local default_vault="$HOME/GameSaveVault"
    GSV_VAULT_PATH="$default_vault"
    echo "$default_vault"
    return 0
}

# ------------------------------------------------------------------------------
# Token Resolution & Path Translation
# ------------------------------------------------------------------------------

# gsv_path_to_token(path)
# Maps concrete path to portable token:
#   - AppData/Roaming     -> %APPDATA%/<rel>
#   - AppData/LocalLow    -> %LOCALLOW%/<rel>
#   - AppData/Local       -> %LOCALAPPDATA%/<rel>
#   - Documents/My Games  -> %DOCUMENTS%/<rel>
#   - Saved Games         -> %SAVEDGAMES%/<rel>
#   - $HOME/.local/share  -> %XDG_DATA_HOME%/<rel>
#   - $HOME/.config       -> %XDG_CONFIG_HOME%/<rel>
#   - Fallback            -> %ROOT%/<path>
gsv_path_to_token() {
    local p="${1:-}"
    # Normalize Windows backslashes to forward slashes
    p="${p//\\//}"
    p="${p%/}"

    # Match Proton / Wine paths first
    if [[ "$p" =~ [Aa][Pp][Pp][Dd][Aa][Tt][Aa]/[Ll][Oo][Cc][Aa][Ll][Ll][Oo][Ww](/(.*))?$ ]]; then
        local rel="${BASH_REMATCH[2]:-}"
        [ -n "$rel" ] && echo "%LOCALLOW%/$rel" || echo "%LOCALLOW%"
        return 0
    fi

    if [[ "$p" =~ [Aa][Pp][Pp][Dd][Aa][Tt][Aa]/[Ll][Oo][Cc][Aa][Ll](/(.*))?$ ]]; then
        local rel="${BASH_REMATCH[2]:-}"
        [ -n "$rel" ] && echo "%LOCALAPPDATA%/$rel" || echo "%LOCALAPPDATA%"
        return 0
    fi

    if [[ "$p" =~ [Aa][Pp][Pp][Dd][Aa][Tt][Aa]/[Rr][Oo][Aa][Mm][Ii][Nn][Gg](/(.*))?$ ]]; then
        local rel="${BASH_REMATCH[2]:-}"
        [ -n "$rel" ] && echo "%APPDATA%/$rel" || echo "%APPDATA%"
        return 0
    fi

    if [[ "$p" =~ [Dd][Oo][Cc][Uu][Mm][Ee][Nn][Tt][Ss](/(.*))?$ ]]; then
        local rel="${BASH_REMATCH[2]:-}"
        [ -n "$rel" ] && echo "%DOCUMENTS%/$rel" || echo "%DOCUMENTS%"
        return 0
    fi

    if [[ "$p" =~ [Ss][Aa][Vv][Ee][Dd]\ [Gg][Aa][Mm][Ee][Ss](/(.*))?$ ]]; then
        local rel="${BASH_REMATCH[2]:-}"
        [ -n "$rel" ] && echo "%SAVEDGAMES%/$rel" || echo "%SAVEDGAMES%"
        return 0
    fi

    # Wine/Proton user profile root fallback (e.g. drive_c/users/<user>/...)
    if [[ "$p" =~ [Dd][Rr][Ii][Vv][Ee]_[Cc]/[Uu][Ss][Ee][Rr][Ss]/[^/]+(/(.*))?$ ]]; then
        local rel="${BASH_REMATCH[2]:-}"
        [ -n "$rel" ] && echo "%USERPROFILE%/$rel" || echo "%USERPROFILE%"
        return 0
    fi

    # Native Linux XDG paths
    local xdg_data="${XDG_DATA_HOME:-$HOME/.local/share}"
    if [[ "$p" == "$xdg_data"/* ]]; then
        local rel="${p#$xdg_data/}"
        echo "%XDG_DATA_HOME%/$rel"
        return 0
    elif [[ "$p" == "$HOME/.local/share"/* ]]; then
        local rel="${p#$HOME/.local/share/}"
        echo "%XDG_DATA_HOME%/$rel"
        return 0
    fi

    local xdg_config="${XDG_CONFIG_HOME:-$HOME/.config}"
    if [[ "$p" == "$xdg_config"/* ]]; then
        local rel="${p#$xdg_config/}"
        echo "%XDG_CONFIG_HOME%/$rel"
        return 0
    elif [[ "$p" == "$HOME/.config"/* ]]; then
        local rel="${p#$HOME/.config/}"
        echo "%XDG_CONFIG_HOME%/$rel"
        return 0
    fi

    # Root filesystem fallback
    local rel="${p#/}"
    echo "%ROOT%/$rel"
    return 0
}

# gsv_token_to_path(token_path, [prefix_root])
# Converts portable token back to system path or prefix-relative path.
gsv_token_to_path() {
    local tok="${1:-}"
    local prefix="${2:-}"

    tok="${tok//\\//}"
    prefix="${prefix//\\//}"
    prefix="${prefix%/}"

    # Auto-detect wine user directory if prefix points to a Proton prefix root
    if [ -n "$prefix" ]; then
        if [ -d "$prefix/drive_c/users/steamuser" ]; then
            prefix="$prefix/drive_c/users/steamuser"
        elif [ -d "$prefix/drive_c/users/${USER:-$(id -un 2>/dev/null || echo "user")}" ]; then
            prefix="$prefix/drive_c/users/${USER:-$(id -un 2>/dev/null || echo "user")}"
        fi
    fi

    local token_name=""
    local rel=""
    if [[ "$tok" =~ ^%([A-Za-z0-9_]+)%(/(.*))?$ ]]; then
        token_name="${BASH_REMATCH[1]^^}"
        rel="${BASH_REMATCH[3]:-}"
    else
        # Not a token path, return as-is
        echo "$tok"
        return 0
    fi

    local base=""
    case "$token_name" in
        APPDATA|APPDATAROAMING)
            if [ -n "$prefix" ]; then
                base="$prefix/AppData/Roaming"
            else
                base="${XDG_CONFIG_HOME:-$HOME/.config}"
            fi
            ;;
        LOCALAPPDATA|APPDATALOCAL)
            if [ -n "$prefix" ]; then
                base="$prefix/AppData/Local"
            else
                base="${XDG_DATA_HOME:-$HOME/.local/share}"
            fi
            ;;
        LOCALLOW|APPDATALOCALLOW)
            if [ -n "$prefix" ]; then
                base="$prefix/AppData/LocalLow"
            else
                base="${XDG_DATA_HOME:-$HOME/.local/share}"
            fi
            ;;
        DOCUMENTS|MYDOCUMENTS)
            if [ -n "$prefix" ]; then
                base="$prefix/Documents"
            else
                base="${XDG_DOCUMENTS_DIR:-$HOME/Documents}"
            fi
            ;;
        USERPROFILE)
            if [ -n "$prefix" ]; then
                base="$prefix"
            else
                base="$HOME"
            fi
            ;;
        SAVEDGAMES)
            if [ -n "$prefix" ]; then
                base="$prefix/Saved Games"
            else
                base="$HOME/Saved Games"
            fi
            ;;
        XDG_DATA_HOME)
            if [ -n "$prefix" ]; then
                base="$prefix/.local/share"
            else
                base="${XDG_DATA_HOME:-$HOME/.local/share}"
            fi
            ;;
        XDG_CONFIG_HOME)
            if [ -n "$prefix" ]; then
                base="$prefix/.config"
            else
                base="${XDG_CONFIG_HOME:-$HOME/.config}"
            fi
            ;;
        ROOT)
            if [ -n "$prefix" ]; then
                echo "$prefix/${rel#/}"
            else
                echo "/${rel#/}"
            fi
            return 0
            ;;
        *)
            if [ -n "$prefix" ]; then
                echo "$prefix/${rel#/}"
            else
                echo "/${rel#/}"
            fi
            return 0
            ;;
    esac

    if [ -n "$rel" ]; then
        echo "$base/$rel"
    else
        echo "$base"
    fi
    return 0
}

# ------------------------------------------------------------------------------
# Logging Helpers
# ------------------------------------------------------------------------------

# gsv_log(level, msg)
# Writes formatted log line to stdout (colored if interactive) and appends
# to <vault>/logs/gamevault.log when vault path is resolved.
gsv_log() {
    local level="${1:-INFO}"
    [ $# -gt 0 ] && shift
    local msg="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local formatted="[$timestamp] [${level^^}] $msg"

    # Terminal output (with ANSI colors if interactive or forced)
    if [ -t 1 ] || [ "${GSV_FORCE_COLOR:-0}" = "1" ]; then
        local color="\033[0m"
        case "${level^^}" in
            INFO)  color="\033[0;32m" ;; # Green
            WARN)  color="\033[0;33m" ;; # Yellow
            ERROR) color="\033[0;31m" ;; # Red
            DEBUG) color="\033[0;90m" ;; # Dim/Gray
        esac
        printf "%b[%s] [%s] %s%b\n" "$color" "$timestamp" "${level^^}" "$msg" "\033[0m"
    else
        printf "%s\n" "$formatted"
    fi

    # Append to vault log file if vault is resolved
    if [ -n "${GSV_VAULT_PATH:-}" ]; then
        mkdir -p "$GSV_VAULT_PATH/logs" 2>/dev/null || true
        printf "%s\n" "$formatted" >> "$GSV_VAULT_PATH/logs/gamevault.log" 2>/dev/null || true
    fi
}

gsv_log_info() {
    gsv_log "INFO" "$*"
}

gsv_log_warn() {
    gsv_log "WARN" "$*"
}

gsv_log_error() {
    gsv_log "ERROR" "$*"
}

gsv_log_debug() {
    gsv_log "DEBUG" "$*"
}
