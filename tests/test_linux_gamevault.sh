#!/usr/bin/env bash
# ==============================================================================
# tests/test_linux_gamevault.sh
# Test runner and unit test suite for Linux GameSaveVault (gamevault.sh)
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TEST_TMP_DIR="$(mktemp -d /tmp/gsv-test.XXXXXX)"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Assertion helpers
assert_equals() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-Assertion failed}"
    if [ "$expected" != "$actual" ]; then
        echo -e "${RED}FAIL:${NC} $msg"
        echo -e "  Expected: [${expected}]"
        echo -e "  Actual:   [${actual}]"
        _TEST_FAIL=1
        return 1
    fi
    return 0
}

assert_match() {
    local pattern="$1"
    local actual="$2"
    local msg="${3:-Pattern match failed}"
    if [[ ! "$actual" =~ $pattern ]]; then
        echo -e "${RED}FAIL:${NC} $msg"
        echo -e "  Pattern: [${pattern}]"
        echo -e "  Actual:  [${actual}]"
        _TEST_FAIL=1
        return 1
    fi
    return 0
}

assert_true() {
    local condition="$1"
    local msg="${2:-Condition is not true}"
    if ! eval "$condition"; then
        echo -e "${RED}FAIL:${NC} $msg ($condition)"
        _TEST_FAIL=1
        return 1
    fi
    return 0
}

run_test() {
    local test_func="$1"
    local desc="${2:-$test_func}"
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -ne "  RUN: $desc ... "
    local output
    if output=$(
        exec 2>&1
        _TEST_FAIL=0
        $test_func
        exit $_TEST_FAIL
    ); then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}PASS${NC}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}FAIL${NC}"
        if [ -n "$output" ]; then
            echo "$output" | sed 's/^/    /'
        fi
    fi
}

# ==============================================================================
# Load modules
# ==============================================================================
COMMON_SH="$REPO_ROOT/linux/modules/common.sh"
if [ ! -f "$COMMON_SH" ]; then
    echo -e "${RED}ERROR: $COMMON_SH does not exist!${NC}"
    exit 1
fi
# shellcheck source=../linux/modules/common.sh
source "$COMMON_SH"

SCANNER_SH="$REPO_ROOT/linux/modules/scanner.sh"
if [ -f "$SCANNER_SH" ]; then
    # shellcheck source=../linux/modules/scanner.sh
    source "$SCANNER_SH"
fi

VAULT_SH="$REPO_ROOT/linux/modules/vault.sh"
if [ -f "$VAULT_SH" ]; then
    # shellcheck source=../linux/modules/vault.sh
    source "$VAULT_SH"
fi

UI_SH="$REPO_ROOT/linux/modules/ui.sh"
if [ -f "$UI_SH" ]; then
    # shellcheck source=../linux/modules/ui.sh
    source "$UI_SH"
fi

# ==============================================================================
# Unit Tests: common.sh
# ==============================================================================

test_env_init() {
    gsv_init_env
    assert_equals "$REPO_ROOT" "$GSV_ROOT" "GSV_ROOT matches REPO_ROOT"
    assert_equals "$REPO_ROOT/config" "$GSV_CONFIG_DIR" "GSV_CONFIG_DIR matches"
    assert_equals "$REPO_ROOT/data" "$GSV_DATA_DIR" "GSV_DATA_DIR matches"
    assert_true "[ '$GSV_JSON_TOOL' = 'jq' ] || [ '$GSV_JSON_TOOL' = 'python3' ]" "GSV_JSON_TOOL detected"
}

test_json_get_jq() {
    GSV_JSON_TOOL="jq"
    local sample="$TEST_TMP_DIR/sample_jq.json"
    cat <<'EOF' > "$sample"
{
  "stringKey": "hello world",
  "numberKey": 42,
  "boolKey": true,
  "nullKey": null,
  "Game Title": {
    "save": "elden_ring_save"
  },
  "nested": {
    "child": "deep_value"
  },
  "arrayKey": ["item1", "item2"]
}
EOF

    local val
    val="$(gsv_json_get "$sample" ".stringKey")"
    assert_equals "hello world" "$val" "gsv_json_get string key"

    val="$(gsv_json_get "$sample" ".numberKey")"
    assert_equals "42" "$val" "gsv_json_get number key"

    val="$(gsv_json_get "$sample" ".boolKey")"
    assert_equals "true" "$val" "gsv_json_get bool key"

    val="$(gsv_json_get "$sample" ".nested.child")"
    assert_equals "deep_value" "$val" "gsv_json_get nested key"

    val="$(gsv_json_get "$sample" '.["Game Title"].save')"
    assert_equals "elden_ring_save" "$val" "gsv_json_get bracket quoted key with space"

    val="$(gsv_json_get "$sample" ".arrayKey[0]")"
    assert_equals "item1" "$val" "gsv_json_get array index"

    val="$(gsv_json_get "$sample" ".nonExistent")"
    assert_equals "null" "$val" "gsv_json_get non-existent key"
}

test_json_get_python() {
    GSV_JSON_TOOL="python3"
    local sample="$TEST_TMP_DIR/sample_py.json"
    cat <<'EOF' > "$sample"
{
  "stringKey": "python test",
  "numberKey": 99,
  "boolKey": false,
  "Elden Ring": {
    "save": "py_elden_save"
  },
  "nested": {
    "child": "py_child",
    "spaced key": "spaced_val"
  },
  "arrayKey": ["alpha", "beta"]
}
EOF

    local val
    val="$(gsv_json_get "$sample" ".stringKey")"
    assert_equals "python test" "$val" "py fallback string key"

    val="$(gsv_json_get "$sample" ".numberKey")"
    assert_equals "99" "$val" "py fallback number key"

    val="$(gsv_json_get "$sample" ".boolKey")"
    assert_equals "false" "$val" "py fallback bool key"

    val="$(gsv_json_get "$sample" ".nested.child")"
    assert_equals "py_child" "$val" "py fallback nested key"

    val="$(gsv_json_get "$sample" '.["Elden Ring"].save')"
    assert_equals "py_elden_save" "$val" "py fallback double bracket quoted key with space"

    val="$(gsv_json_get "$sample" ".nested[\"spaced key\"]")"
    assert_equals "spaced_val" "$val" "py fallback nested bracket quoted key with space"

    val="$(gsv_json_get "$sample" ".arrayKey[1]")"
    assert_equals "beta" "$val" "py fallback array index"

    val="$(gsv_json_get "$sample" ".notThere")"
    assert_equals "null" "$val" "py fallback non-existent key"
}

test_json_set_jq() {
    GSV_JSON_TOOL="jq"
    local target="$TEST_TMP_DIR/set_jq.json"
    echo '{}' > "$target"

    gsv_json_set "$target" "appName" '"GameSaveVault"'
    local val
    val="$(gsv_json_get "$target" ".appName")"
    assert_equals "GameSaveVault" "$val" "jq json_set string"

    gsv_json_set "$target" "count" 10
    val="$(gsv_json_get "$target" ".count")"
    assert_equals "10" "$val" "jq json_set number"

    gsv_json_set "$target" "active" true
    val="$(gsv_json_get "$target" ".active")"
    assert_equals "true" "$val" "jq json_set bool"

    gsv_json_set "$target" "config.subpath" '"sub_val"'
    val="$(gsv_json_get "$target" ".config.subpath")"
    assert_equals "sub_val" "$val" "jq json_set nested key"

    # Test auto-creating non-existent file
    local new_file="$TEST_TMP_DIR/auto_created.json"
    gsv_json_set "$new_file" "init" '"yes"'
    val="$(gsv_json_get "$new_file" ".init")"
    assert_equals "yes" "$val" "jq json_set creates new file"
}

test_json_set_python() {
    GSV_JSON_TOOL="python3"
    local target="$TEST_TMP_DIR/set_py.json"
    echo '{}' > "$target"

    gsv_json_set "$target" "appName" '"GameSaveVaultPy"'
    local val
    val="$(gsv_json_get "$target" ".appName")"
    assert_equals "GameSaveVaultPy" "$val" "py json_set string"

    gsv_json_set "$target" "count" 25
    val="$(gsv_json_get "$target" ".count")"
    assert_equals "25" "$val" "py json_set number"

    gsv_json_set "$target" "active" false
    val="$(gsv_json_get "$target" ".active")"
    assert_equals "false" "$val" "py json_set bool"

    gsv_json_set "$target" "options.timeout" 300
    val="$(gsv_json_get "$target" ".options.timeout")"
    assert_equals "300" "$val" "py json_set nested key"

    # Test auto-creating non-existent file with python
    local new_py_file="$TEST_TMP_DIR/auto_created_py.json"
    gsv_json_set "$new_py_file" "init" '"yes_py"'
    val="$(gsv_json_get "$new_py_file" ".init")"
    assert_equals "yes_py" "$val" "py json_set creates new file"
}

test_vault_resolution_order() {
    # 1. Override path takes top priority
    local res
    res="$(gsv_resolve_vault_path "/tmp/my_override_vault")"
    assert_equals "/tmp/my_override_vault" "$res" "Override path priority 1"

    # Override path with tilde expansion
    res="$(gsv_resolve_vault_path "~/custom_vault")"
    assert_equals "$HOME/custom_vault" "$res" "Override tilde expansion"

    # 2. Mounted external drive takes 2nd priority (must be writable)
    local mock_mount="$TEST_TMP_DIR/mock_media/drive1/GameSaveVault"
    mkdir -p "$mock_mount"
    local GSV_MOUNT_ROOTS=("$TEST_TMP_DIR/mock_media")
    res="$(gsv_resolve_vault_path "")"
    assert_equals "$mock_mount" "$res" "Mounted drive priority 2"

    # Writable check: read-only external drive is skipped
    local ro_mount="$TEST_TMP_DIR/mock_ro_media/drive2/GameSaveVault"
    mkdir -p "$ro_mount"
    chmod 555 "$ro_mount"
    GSV_MOUNT_ROOTS=("$TEST_TMP_DIR/mock_ro_media")
    res="$(gsv_resolve_vault_path "")"
    # Should skip the read-only drive and fall through to default ~/GameSaveVault
    assert_equals "$HOME/GameSaveVault" "$res" "Read-only mounted drive is skipped"
    chmod 755 "$ro_mount"
    rm -rf "$TEST_TMP_DIR/mock_ro_media"

    # Remove mock external drive
    rm -rf "$TEST_TMP_DIR/mock_media"
    unset GSV_MOUNT_ROOTS

    # 3. Settings.json BackupRoot takes 3rd priority
    local mock_config="$TEST_TMP_DIR/config"
    mkdir -p "$mock_config"
    echo '{"BackupRoot": "'"$TEST_TMP_DIR/settings_vault"'"}' > "$mock_config/settings.json"
    local orig_config="$GSV_CONFIG_DIR"
    GSV_CONFIG_DIR="$mock_config"

    res="$(gsv_resolve_vault_path "")"
    assert_equals "$TEST_TMP_DIR/settings_vault" "$res" "Settings BackupRoot priority 3"

    # Settings BackupRoot pointing to missing/unmounted/unwritable drive falls back to ~/GameSaveVault
    echo '{"BackupRoot": "/mnt/missing_unmounted_drive/GameSaveVault"}' > "$mock_config/settings.json"
    res="$(gsv_resolve_vault_path "")"
    assert_equals "$HOME/GameSaveVault" "$res" "Unmounted/missing BackupRoot falls back to default"

    # 4. Default ~/GameSaveVault when settings empty or Windows-formatted
    echo '{"BackupRoot": "D:\\GameSaveVault"}' > "$mock_config/settings.json"
    res="$(gsv_resolve_vault_path "")"
    assert_equals "$HOME/GameSaveVault" "$res" "Default fallback ~/GameSaveVault"

    GSV_CONFIG_DIR="$orig_config"
}

test_token_mapping_roundtrip() {
    local mock_prefix="$TEST_TMP_DIR/pfx/drive_c/users/steamuser"
    mkdir -p "$mock_prefix/AppData/Roaming"
    mkdir -p "$mock_prefix/AppData/Local"
    mkdir -p "$mock_prefix/AppData/LocalLow"
    mkdir -p "$mock_prefix/Documents/My Games"
    mkdir -p "$mock_prefix/Saved Games"

    # AppData/Roaming
    local path1="$mock_prefix/AppData/Roaming/EldenRing/save.sl2"
    local tok1
    tok1="$(gsv_path_to_token "$path1")"
    assert_equals "%APPDATA%/EldenRing/save.sl2" "$tok1" "Token AppData/Roaming"
    local rev1
    rev1="$(gsv_token_to_path "$tok1" "$mock_prefix")"
    assert_equals "$path1" "$rev1" "Round-trip AppData/Roaming"

    # AppData/Local
    local path2="$mock_prefix/AppData/Local/Hades/Profile1.sav"
    local tok2
    tok2="$(gsv_path_to_token "$path2")"
    assert_equals "%LOCALAPPDATA%/Hades/Profile1.sav" "$tok2" "Token AppData/Local"
    local rev2
    rev2="$(gsv_token_to_path "$tok2" "$mock_prefix")"
    assert_equals "$path2" "$rev2" "Round-trip AppData/Local"

    # AppData/LocalLow
    local path3="$mock_prefix/AppData/LocalLow/IronGate/Valheim/worlds"
    local tok3
    tok3="$(gsv_path_to_token "$path3")"
    assert_equals "%LOCALLOW%/IronGate/Valheim/worlds" "$tok3" "Token AppData/LocalLow"
    local rev3
    rev3="$(gsv_token_to_path "$tok3" "$mock_prefix")"
    assert_equals "$path3" "$rev3" "Round-trip AppData/LocalLow"

    # Documents/My Games (preserves whatever follows Documents/)
    local path4="$mock_prefix/Documents/My Games/Skyrim Special Edition/Saves"
    local tok4
    tok4="$(gsv_path_to_token "$path4")"
    assert_equals "%DOCUMENTS%/My Games/Skyrim Special Edition/Saves" "$tok4" "Token Documents/My Games"
    local rev4
    rev4="$(gsv_token_to_path "$tok4" "$mock_prefix")"
    assert_equals "$path4" "$rev4" "Round-trip Documents/My Games"

    # Documents publisher path (without My Games, e.g. Witcher 3, GTA V)
    local path4b="$mock_prefix/Documents/The Witcher 3/gamesaves"
    local tok4b
    tok4b="$(gsv_path_to_token "$path4b")"
    assert_equals "%DOCUMENTS%/The Witcher 3/gamesaves" "$tok4b" "Token Documents without My Games"
    local rev4b
    rev4b="$(gsv_token_to_path "$tok4b" "$mock_prefix")"
    assert_equals "$path4b" "$rev4b" "Round-trip Documents without My Games"

    # UserProfile fallback in Wine/Proton prefixes
    local path_prof="$mock_prefix/custom_saves/slot0.sav"
    local tok_prof
    tok_prof="$(gsv_path_to_token "$path_prof")"
    assert_equals "%USERPROFILE%/custom_saves/slot0.sav" "$tok_prof" "Token USERPROFILE"
    local rev_prof
    rev_prof="$(gsv_token_to_path "$tok_prof" "$mock_prefix")"
    assert_equals "$path_prof" "$rev_prof" "Round-trip USERPROFILE"

    # Saved Games
    local path5="$mock_prefix/Saved Games/CD Projekt Red/Cyberpunk 2077"
    local tok5
    tok5="$(gsv_path_to_token "$path5")"
    assert_equals "%SAVEDGAMES%/CD Projekt Red/Cyberpunk 2077" "$tok5" "Token Saved Games"
    local rev5
    rev5="$(gsv_token_to_path "$tok5" "$mock_prefix")"
    assert_equals "$path5" "$rev5" "Round-trip Saved Games"

    # Native ~/.local/share
    local path6="$HOME/.local/share/Celeste/Saves"
    local tok6
    tok6="$(gsv_path_to_token "$path6")"
    assert_equals "%XDG_DATA_HOME%/Celeste/Saves" "$tok6" "Token XDG_DATA_HOME"
    local rev6
    rev6="$(gsv_token_to_path "$tok6")"
    assert_equals "$path6" "$rev6" "Round-trip XDG_DATA_HOME"

    # Native ~/.config
    local path7="$HOME/.config/Ryujinx/bis/user/save"
    local tok7
    tok7="$(gsv_path_to_token "$path7")"
    assert_equals "%XDG_CONFIG_HOME%/Ryujinx/bis/user/save" "$tok7" "Token XDG_CONFIG_HOME"
    local rev7
    rev7="$(gsv_token_to_path "$tok7")"
    assert_equals "$path7" "$rev7" "Round-trip XDG_CONFIG_HOME"

    # Root fallback
    local path8="/opt/custom_game/saves"
    local tok8
    tok8="$(gsv_path_to_token "$path8")"
    assert_equals "%ROOT%/opt/custom_game/saves" "$tok8" "Token ROOT fallback"
    local rev8
    rev8="$(gsv_token_to_path "$tok8")"
    assert_equals "$path8" "$rev8" "Round-trip ROOT fallback"

    # Backslash normalization
    local path9="C:\\users\\steamuser\\AppData\\Roaming\\Game\\save.dat"
    local tok9
    tok9="$(gsv_path_to_token "$path9")"
    assert_equals "%APPDATA%/Game/save.dat" "$tok9" "Token normalization with backslashes"

    # Flatpak Steam Proton path & prefix auto-detection
    local flatpak_pfx="$TEST_TMP_DIR/flatpak_pfx"
    mkdir -p "$flatpak_pfx/drive_c/users/steamuser/AppData/Roaming"
    local path10="$flatpak_pfx/drive_c/users/steamuser/AppData/Roaming/DarkSoulsIII/save.sl2"
    local tok10
    tok10="$(gsv_path_to_token "$path10")"
    assert_equals "%APPDATA%/DarkSoulsIII/save.sl2" "$tok10" "Token Flatpak Proton path"
    # When passing prefix root containing drive_c/users/steamuser, it auto-resolves
    local rev10
    rev10="$(gsv_token_to_path "$tok10" "$flatpak_pfx")"
    assert_equals "$path10" "$rev10" "Prefix auto-detection from pfx root"

    # Case-insensitivity in Proton paths
    local path11="$mock_prefix/appdata/local/GameTitle/save.bin"
    local tok11
    tok11="$(gsv_path_to_token "$path11")"
    assert_equals "%LOCALAPPDATA%/GameTitle/save.bin" "$tok11" "Case-insensitive appdata/local token"
}

test_logging_helpers() {
    local mock_vault="$TEST_TMP_DIR/mock_vault"
    mkdir -p "$mock_vault"
    GSV_VAULT_PATH="$mock_vault"
    GSV_FORCE_COLOR=0

    local log_out
    log_out="$(gsv_log)"
    assert_match "\[INFO\]" "$log_out" "gsv_log with 0 arguments"

    log_out="$(gsv_log_info "Test information message")"
    assert_match "\[INFO\] Test information message" "$log_out" "gsv_log_info stdout"

    log_out="$(gsv_log_warn "Test warning message")"
    assert_match "\[WARN\] Test warning message" "$log_out" "gsv_log_warn stdout"

    log_out="$(gsv_log_error "Test error message")"
    assert_match "\[ERROR\] Test error message" "$log_out" "gsv_log_error stdout"

    # Verify log file was written
    local log_file="$mock_vault/logs/gamevault.log"
    assert_true "[ -f '$log_file' ]" "Log file created in vault"

    local log_content
    log_content="$(cat "$log_file")"
    assert_match "Test information message" "$log_content" "Log file contains info"
    assert_match "Test warning message" "$log_content" "Log file contains warn"
    assert_match "Test error message" "$log_content" "Log file contains error"
}

# ==============================================================================
# Unit Tests: scanner.sh
# ==============================================================================

test_scan_steam_proton() {
    local mock_steam="$TEST_TMP_DIR/mock_steam"
    local mock_compat="$mock_steam/steamapps/compatdata"
    local pfx_elden="$mock_compat/1245620/pfx/drive_c/users/steamuser/AppData/Roaming/EldenRing"
    mkdir -p "$pfx_elden"
    echo "slot0_data" > "$pfx_elden/ER0000.sl2"

    local orig_config="$GSV_CONFIG_DIR"
    local mock_cfg="$TEST_TMP_DIR/mock_cfg_steam"
    mkdir -p "$mock_cfg"
    echo '{"1245620": "ELDEN RING"}' > "$mock_cfg/title-names.json"
    GSV_CONFIG_DIR="$mock_cfg"

    local result
    result="$(gsv_scan_steam_proton "$mock_compat")"
    GSV_CONFIG_DIR="$orig_config"

    assert_true "echo '$result' | jq . >/dev/null 2>&1" "Result is valid JSON"
    local count
    count="$(echo "$result" | jq 'length')"
    assert_equals "1" "$count" "Found 1 Elden Ring save location"

    local gname gid aid src tok
    gname="$(echo "$result" | jq -r '.[0].GameName')"
    gid="$(echo "$result" | jq -r '.[0].GameId')"
    aid="$(echo "$result" | jq -r '.[0].AppId')"
    src="$(echo "$result" | jq -r '.[0].Source')"
    tok="$(echo "$result" | jq -r '.[0].Token')"

    assert_equals "ELDEN RING" "$gname" "GameName resolved from title-names.json"
    assert_equals "steam-1245620" "$gid" "GameId is steam-1245620"
    assert_equals "1245620" "$aid" "AppId is 1245620"
    assert_equals "SteamProton" "$src" "Source is SteamProton"
    assert_equals "APPDATA" "$tok" "Token is APPDATA"

    local fc bytes
    fc="$(echo "$result" | jq -r '.[0].FileCount')"
    bytes="$(echo "$result" | jq -r '.[0].Bytes')"
    assert_equals "1" "$fc" "File count is 1"
    assert_true "[ '$bytes' -gt 0 ]" "Bytes greater than 0"
}

test_scan_steam_proton_incomplete_prefix() {
    local mock_compat="$TEST_TMP_DIR/mock_steam_incomplete/compatdata"
    # 1. Missing pfx/drive_c entirely
    mkdir -p "$mock_compat/999001/pfx"
    # 2. Has drive_c but missing users/
    mkdir -p "$mock_compat/999002/pfx/drive_c"
    # 3. Has users/steamuser but no save directories
    mkdir -p "$mock_compat/999003/pfx/drive_c/users/steamuser"
    # 4. Valid prefix alongside incomplete ones
    local valid_pfx="$mock_compat/999004/pfx/drive_c/users/steamuser/Documents/My Games/ValidGame"
    mkdir -p "$valid_pfx"
    echo "save" > "$valid_pfx/save.sav"

    local result
    result="$(gsv_scan_steam_proton "$mock_compat")"

    assert_true "echo '$result' | jq . >/dev/null 2>&1" "Result is valid JSON even with incomplete prefixes"
    local count
    count="$(echo "$result" | jq 'length')"
    assert_equals "1" "$count" "Only valid prefix is returned"

    local gname
    gname="$(echo "$result" | jq -r '.[0].GameName')"
    assert_equals "AppID 999004" "$gname" "Fallback to AppID when not in title-names"
}

test_title_lookup_special_characters() {
    local mock_compat="$TEST_TMP_DIR/mock_steam_special/compatdata"
    local special_title="Dragon's Dogma 2: \"Deluxe\" & Special \\ Paths"
    local pfx_special="$mock_compat/1086940/pfx/drive_c/users/steamuser/AppData/Local/Capcom/DD2"
    mkdir -p "$pfx_special"
    echo "profile_data" > "$pfx_special/data001.bin"

    local orig_config="$GSV_CONFIG_DIR"
    local mock_cfg="$TEST_TMP_DIR/mock_cfg_special"
    mkdir -p "$mock_cfg"
    python3 -c '
import json, sys
data = {"1086940": sys.argv[1]}
with open(sys.argv[2], "w", encoding="utf-8") as f:
    json.dump(data, f)
' "$special_title" "$mock_cfg/title-names.json"
    GSV_CONFIG_DIR="$mock_cfg"

    local result
    result="$(gsv_scan_steam_proton "$mock_compat")"
    GSV_CONFIG_DIR="$orig_config"

    echo "$result" | jq . >/dev/null 2>&1
    local jq_status=$?
    assert_equals "0" "$jq_status" "Valid JSON with special characters"

    local parsed_title
    parsed_title="$(echo "$result" | jq -r '.[0].GameName')"
    assert_equals "$special_title" "$parsed_title" "Special character title survived JSON escaping"
}

test_scan_native_games() {
    local mock_home="$TEST_TMP_DIR/mock_home_native"
    local mock_share="$mock_home/.local/share"
    local mock_config="$mock_home/.config"

    mkdir -p "$mock_share/Celeste/Saves"
    echo "celeste_data" > "$mock_share/Celeste/Saves/0.celeste"

    mkdir -p "$mock_config/Hollow Knight"
    echo "hk_data" > "$mock_config/Hollow Knight/user1.dat"

    # System directory that must be ignored
    mkdir -p "$mock_share/systemd"
    echo "service" > "$mock_share/systemd/user.service"

    local result
    result="$(gsv_scan_native_games "$mock_share" "$mock_config")"

    assert_true "echo '$result' | jq . >/dev/null 2>&1" "Native games scan is valid JSON"
    local count
    count="$(echo "$result" | jq 'length')"
    assert_equals "2" "$count" "Found 2 native game save locations (Celeste, Hollow Knight)"

    local src0 src1
    src0="$(echo "$result" | jq -r '.[0].Source')"
    src1="$(echo "$result" | jq -r '.[1].Source')"
    assert_equals "Native" "$src0" "Source is Native"
    assert_equals "Native" "$src1" "Source is Native"
}

test_scan_wine_lutris_heroic() {
    local mock_roots="$TEST_TMP_DIR/mock_wine_lutris"
    local mock_wine="$mock_roots/.wine/drive_c/users/tester/AppData/Roaming/WineGame"
    mkdir -p "$mock_wine"
    echo "wine_save" > "$mock_wine/save.bin"

    local mock_games="$mock_roots/Games/lutris-game/drive_c/users/tester/Saved Games/LutrisGame"
    mkdir -p "$mock_games"
    echo "lutris_save" > "$mock_games/save.sav"

    local mock_heroic="$mock_roots/.config/heroic/Prefixes/HeroicGame/pfx/drive_c/users/tester/Documents/HeroicGame"
    mkdir -p "$mock_heroic"
    echo "heroic_save" > "$mock_heroic/game.dat"

    local result
    result="$(gsv_scan_wine_lutris_heroic "$mock_roots/.wine" "$mock_roots/Games" "$mock_roots/.config/heroic/Prefixes")"

    assert_true "echo '$result' | jq . >/dev/null 2>&1" "Wine/Lutris/Heroic scan is valid JSON"
    local count
    count="$(echo "$result" | jq 'length')"
    assert_equals "3" "$count" "Found Wine, Lutris, and Heroic prefixes"
}

test_scan_emulators() {
    local mock_emu="$TEST_TMP_DIR/mock_emu"
    # Ryujinx save for Stardew Valley (title 0100e65002bb8000 in data/title-names.json)
    local ryu_save="$mock_emu/Ryujinx/bis/user/save/0000000000000001/0100e65002bb8000/0"
    mkdir -p "$ryu_save"
    echo "stardew_save" > "$ryu_save/savegame.sav"

    # RPCS3 save
    local rpcs3_save="$mock_emu/rpcs3/dev_hdd0/home/00000001/savedata/BLUS30443"
    mkdir -p "$rpcs3_save"
    echo "rpcs3_data" > "$rpcs3_save/SYS-DATA"

    local result
    result="$(gsv_scan_emulators "$mock_emu")"

    assert_true "echo '$result' | jq . >/dev/null 2>&1" "Emulator scan is valid JSON"
    local count
    count="$(echo "$result" | jq 'length')"
    assert_equals "2" "$count" "Found 2 emulator save locations"

    local ryu_name
    ryu_name="$(echo "$result" | jq -r '.[] | select(.GameId | startswith("ryujinx")) | .GameName')"
    assert_equals "Stardew Valley" "$ryu_name" "Ryujinx title resolved to Stardew Valley"
}

test_deep_scan_folder() {
    local custom_root="$TEST_TMP_DIR/deep_scan_root"
    mkdir -p "$custom_root/GameAlpha/saves"
    echo "alpha_save" > "$custom_root/GameAlpha/saves/slot1.sav"

    mkdir -p "$custom_root/GameBeta"
    echo "beta_save" > "$custom_root/GameBeta/profile.sl2"

    mkdir -p "$custom_root/GameGamma/savedata"
    echo "gamma_save" > "$custom_root/GameGamma/savedata/save001.dat"

    # Pruned directories
    mkdir -p "$custom_root/.git/hooks"
    echo "hook" > "$custom_root/.git/hooks/pre-commit.sav"

    mkdir -p "$custom_root/cache/temp"
    echo "tmp" > "$custom_root/cache/temp/data.dat"

    local result
    result="$(gsv_deep_scan_folder "$custom_root" 5)"

    assert_true "echo '$result' | jq . >/dev/null 2>&1" "Deep scan returns valid JSON"
    local count
    count="$(echo "$result" | jq 'length')"
    assert_equals "3" "$count" "Found 3 deep scan game locations"

    local has_git has_cache
    has_git="$(echo "$result" | jq '[.[] | select(.AbsolutePath | contains(".git"))] | length')"
    has_cache="$(echo "$result" | jq '[.[] | select(.AbsolutePath | contains("cache"))] | length')"
    assert_equals "0" "$has_git" "Pruned .git directory"
    assert_equals "0" "$has_cache" "Pruned cache directory"
}

test_update_scan_database() {
    local mock_config="$TEST_TMP_DIR/mock_scandb_config"
    mkdir -p "$mock_config"
    local orig_config="$GSV_CONFIG_DIR"
    GSV_CONFIG_DIR="$mock_config"

    local locs='[
      {
        "GameId": "steam-1245620",
        "GameName": "ELDEN RING",
        "Source": "SteamProton",
        "AppId": "1245620",
        "InstallDirHint": "",
        "Token": "APPDATA",
        "RelativePath": "EldenRing",
        "AbsolutePath": "/home/user/.steam/steam/steamapps/compatdata/1245620/pfx/drive_c/users/steamuser/AppData/Roaming/EldenRing",
        "ResolvedPath": "/home/user/.steam/steam/steamapps/compatdata/1245620/pfx/drive_c/users/steamuser/AppData/Roaming/EldenRing",
        "Kind": "Directory",
        "RegistryKey": "",
        "Note": "",
        "Origin": "proton",
        "RuleId": "",
        "RestoreMode": "",
        "InstallDirNames": [],
        "FilePatterns": [],
        "FileCount": 1,
        "Bytes": 1024,
        "ScanRoot": "/home/user/.steam/steam/steamapps/compatdata",
        "DiscoveredUtc": "2026-11-11T12:00:00Z"
      }
    ]'

    gsv_update_scan_database "$locs" '["/home/user/.steam/steam/steamapps/compatdata"]'

    local db_file="$mock_config/scan-database.json"
    assert_true "[ -f '$db_file' ]" "scan-database.json was created"

    local version tool roots_len locs_len
    version="$(gsv_json_get "$db_file" ".Version")"
    tool="$(gsv_json_get "$db_file" ".Tool")"
    roots_len="$(echo "$(cat "$db_file")" | jq '.Roots | length')"
    locs_len="$(echo "$(cat "$db_file")" | jq '.Locations | length')"

    assert_equals "1" "$version" "Database Version is 1"
    assert_equals "GameSaveVault" "$tool" "Database Tool is GameSaveVault"
    assert_equals "1" "$roots_len" "Roots length is 1"
    assert_equals "1" "$locs_len" "Locations length is 1"

    # Add second scan result to test merge / deduplication
    local locs2='[
      {
        "GameId": "native-celeste",
        "GameName": "Celeste",
        "Source": "Native",
        "AppId": "",
        "InstallDirHint": "",
        "Token": "XDG_DATA_HOME",
        "RelativePath": "Celeste/Saves",
        "AbsolutePath": "/home/user/.local/share/Celeste/Saves",
        "ResolvedPath": "/home/user/.local/share/Celeste/Saves",
        "Kind": "Directory",
        "RegistryKey": "",
        "Note": "",
        "Origin": "native",
        "RuleId": "",
        "RestoreMode": "",
        "InstallDirNames": [],
        "FilePatterns": [],
        "FileCount": 2,
        "Bytes": 2048,
        "ScanRoot": "/home/user/.local/share",
        "DiscoveredUtc": "2026-11-11T12:05:00Z"
      }
    ]'

    gsv_update_scan_database "$locs2" '["/home/user/.local/share"]'

    roots_len="$(echo "$(cat "$db_file")" | jq '.Roots | length')"
    locs_len="$(echo "$(cat "$db_file")" | jq '.Locations | length')"
    assert_equals "2" "$roots_len" "Roots updated to 2"
    assert_equals "2" "$locs_len" "Locations updated to 2"

    GSV_CONFIG_DIR="$orig_config"
}

test_scan_all() {
    local orig_home="$HOME"
    local orig_data="${XDG_DATA_HOME:-}"
    local orig_cfg="${XDG_CONFIG_HOME:-}"
    local mock_home="$TEST_TMP_DIR/mock_home_all"
    mkdir -p "$mock_home/.local/share/TestGame/saves"
    echo "test" > "$mock_home/.local/share/TestGame/saves/save.sav"
    HOME="$mock_home"
    XDG_DATA_HOME="$mock_home/.local/share"
    XDG_CONFIG_HOME="$mock_home/.config"

    local all_result
    all_result="$(gsv_scan_all)"
    HOME="$orig_home"
    if [ -n "$orig_data" ]; then
        XDG_DATA_HOME="$orig_data"
    else
        unset XDG_DATA_HOME
    fi
    if [ -n "$orig_cfg" ]; then
        XDG_CONFIG_HOME="$orig_cfg"
    else
        unset XDG_CONFIG_HOME
    fi

    assert_true "[ -n '$all_result' ]" "gsv_scan_all returned output"
    echo "$all_result" | jq . >/dev/null 2>&1
    local jq_status=$?
    assert_equals "0" "$jq_status" "gsv_scan_all produces valid JSON array"

    local is_array
    is_array="$(echo "$all_result" | jq 'if type == "array" then "true" else "false" end' 2>/dev/null)"
    assert_equals '"true"' "$is_array" "Output is a JSON array"

    local count
    count="$(echo "$all_result" | jq 'length')"
    assert_equals "1" "$count" "gsv_scan_all found 1 game in mock home"
}

# ==============================================================================
# Unit Tests: vault.sh (Task 4)
# ==============================================================================

test_vault_create_snapshot() {
    local mock_vault="$TEST_TMP_DIR/mock_vault_1"
    local mock_saves="$TEST_TMP_DIR/mock_saves_1"
    mkdir -p "$mock_saves/HollowKnight"
    mkdir -p "$mock_saves/EldenRing"
    echo "hk_save_content_12345" > "$mock_saves/HollowKnight/user1.dat"
    echo "er_save_content_67890" > "$mock_saves/EldenRing/ER0000.sl2"

    local locs='[
      {
        "Game": "Hollow Knight",
        "Source": "Native",
        "OriginalPath": "'"$mock_saves/HollowKnight"'",
        "TokenPath": "%XDG_DATA_HOME%/HollowKnight"
      },
      {
        "Game": "Elden Ring",
        "Source": "SteamProton",
        "OriginalPath": "'"$mock_saves/EldenRing"'",
        "TokenPath": "%APPDATA%/EldenRing"
      }
    ]'

    gsv_create_snapshot "$locs" 0 "test-backup" "$mock_vault"
    local status=$?
    assert_equals "0" "$status" "gsv_create_snapshot returned success"

    assert_true "[ -d '$mock_vault/snapshots' ]" "Snapshots directory was created"

    local snap_dirs=("$mock_vault/snapshots"/*)
    assert_equals "1" "${#snap_dirs[@]}" "Exactly one snapshot directory created"

    local snap_dir="${snap_dirs[0]}"
    local manifest="$snap_dir/manifest.json"
    assert_true "[ -f '$manifest' ]" "manifest.json exists in snapshot"

    # Verify manifest JSON schema
    local platform label total_games total_files total_bytes
    platform="$(gsv_json_get "$manifest" ".Platform")"
    label="$(gsv_json_get "$manifest" ".Label")"
    total_games="$(gsv_json_get "$manifest" ".TotalGames")"
    total_files="$(gsv_json_get "$manifest" ".TotalFiles")"
    total_bytes="$(gsv_json_get "$manifest" ".TotalBytes")"

    assert_equals "Linux" "$platform" "Manifest Platform is Linux"
    assert_equals "test-backup" "$label" "Manifest Label is test-backup"
    assert_equals "2" "$total_games" "TotalGames is 2"
    assert_equals "2" "$total_files" "TotalFiles is 2"
    assert_true "[ '$total_bytes' -gt 0 ]" "TotalBytes is greater than 0"

    # Verify copied data files
    assert_true "[ -f '$snap_dir/data/Hollow Knight/user1.dat' ]" "Hollow Knight save file copied"
    assert_true "[ -f '$snap_dir/data/Elden Ring/ER0000.sl2' ]" "Elden Ring save file copied"
    local content_hk
    content_hk="$(cat "$snap_dir/data/Hollow Knight/user1.dat")"
    assert_equals "hk_save_content_12345" "$content_hk" "Hollow Knight save data matches"

    # Verify entries in manifest
    local entry0_game entry0_token
    entry0_game="$(gsv_json_get "$manifest" ".Entries[0].Game")"
    entry0_token="$(gsv_json_get "$manifest" ".Entries[0].TokenPath")"
    assert_true "[ -n '$entry0_game' ]" "First entry has Game"
    assert_true "[ -n '$entry0_token' ]" "First entry has TokenPath"
}

test_vault_create_snapshot_from_file() {
    local mock_vault="$TEST_TMP_DIR/mock_vault_file"
    local mock_saves="$TEST_TMP_DIR/mock_saves_file"
    mkdir -p "$mock_saves/Celeste"
    echo "celeste_data" > "$mock_saves/Celeste/0.celeste"

    local loc_file="$TEST_TMP_DIR/locs_input.json"
    cat <<EOF > "$loc_file"
[
  {
    "GameName": "Celeste",
    "Source": "Native",
    "ResolvedPath": "$mock_saves/Celeste",
    "Token": "XDG_DATA_HOME"
  }
]
EOF

    gsv_create_snapshot "$loc_file" 0 "file-backup" "$mock_vault"
    local status=$?
    assert_equals "0" "$status" "gsv_create_snapshot with file input returned success"

    local snap_dirs=("$mock_vault/snapshots"/*)
    assert_equals "1" "${#snap_dirs[@]}" "Snapshot directory created from file"
    assert_true "[ -f '${snap_dirs[0]}/data/Celeste/0.celeste' ]" "Celeste save file copied"
}

test_vault_dry_run_backup() {
    local mock_vault="$TEST_TMP_DIR/mock_vault_dry"
    local mock_saves="$TEST_TMP_DIR/mock_saves_dry"
    mkdir -p "$mock_saves/Doom"
    echo "doom_data" > "$mock_saves/Doom/doom.sav"

    local locs='[
      {
        "Game": "Doom",
        "Source": "Native",
        "OriginalPath": "'"$mock_saves/Doom"'"
      }
    ]'

    gsv_create_snapshot "$locs" 1 "dry-backup" "$mock_vault"
    local status=$?
    assert_equals "0" "$status" "gsv_create_snapshot dry-run returns success"
    assert_true "[ ! -d '$mock_vault/snapshots' ]" "No snapshots folder created during dry-run"
}

test_vault_list_and_resolve_snapshots() {
    local mock_vault="$TEST_TMP_DIR/mock_vault_list"
    local mock_saves="$TEST_TMP_DIR/mock_saves_list"
    mkdir -p "$mock_saves/Game1"
    echo "data1" > "$mock_saves/Game1/save1.dat"

    local locs='[{"Game": "Game1", "OriginalPath": "'"$mock_saves/Game1"'"}]'
    gsv_create_snapshot "$locs" 0 "snap1" "$mock_vault"
    sleep 1
    gsv_create_snapshot "$locs" 0 "snap2" "$mock_vault"

    local table_out
    table_out="$(gsv_list_snapshots "$mock_vault")"
    assert_match "snap1" "$table_out" "Table output contains snap1"
    assert_match "snap2" "$table_out" "Table output contains snap2"

    local json_out
    json_out="$(gsv_list_snapshots "$mock_vault" --json)"
    local json_len
    json_len="$(echo "$json_out" | jq 'length')"
    assert_equals "2" "$json_len" "JSON output has 2 snapshots"

    local latest_dir
    latest_dir="$(gsv_resolve_snapshot_dir "latest" "$mock_vault")"
    assert_true "[ -d '$latest_dir' ]" "Resolved latest snapshot dir exists"
    assert_match "snap2" "$(cat "$latest_dir/manifest.json")" "Latest snapshot matches newest snap2"

    local resolved_explicit
    local snap_id
    snap_id="$(basename "$latest_dir")"
    resolved_explicit="$(gsv_resolve_snapshot_dir "$snap_id" "$mock_vault")"
    assert_equals "$latest_dir" "$resolved_explicit" "Explicit snapshot ID matches"
}

test_vault_restore_snapshot() {
    local mock_vault="$TEST_TMP_DIR/mock_vault_rest"
    local mock_saves="$TEST_TMP_DIR/mock_saves_rest"
    local restore_dest="$TEST_TMP_DIR/mock_restore_dest"
    mkdir -p "$mock_saves/GameA"
    mkdir -p "$mock_saves/GameB"
    echo "saveA_content" > "$mock_saves/GameA/a.sav"
    echo "saveB_content" > "$mock_saves/GameB/b.sav"

    local locs='[
      {"Game": "GameA", "OriginalPath": "'"$mock_saves/GameA"'"},
      {"Game": "GameB", "OriginalPath": "'"$mock_saves/GameB"'"}
    ]'
    gsv_create_snapshot "$locs" 0 "backup-for-restore" "$mock_vault"

    # Selective restore GameA only
    gsv_restore_snapshot "latest" "GameA" 0 "$restore_dest" "$mock_vault"
    local status=$?
    assert_equals "0" "$status" "gsv_restore_snapshot succeeded"
    assert_true "[ -f '$restore_dest/GameA/a.sav' ]" "GameA restored to restore_root"
    assert_equals "saveA_content" "$(cat "$restore_dest/GameA/a.sav")" "Restored file content matches"
    assert_true "[ ! -e '$restore_dest/GameB' ]" "GameB not restored due to selective filter"
}

test_vault_restore_token_path() {
    local mock_vault="$TEST_TMP_DIR/mock_vault_tok"
    local orig_home="$HOME"
    local mock_home="$TEST_TMP_DIR/mock_home_restore"
    mkdir -p "$mock_home/.local/share/NativeGame"
    echo "original_native_data" > "$mock_home/.local/share/NativeGame/save.sav"
    HOME="$mock_home"
    export XDG_DATA_HOME="$mock_home/.local/share"

    local locs='[
      {"Game": "NativeGame", "OriginalPath": "'"$mock_home/.local/share/NativeGame"'", "TokenPath": "%XDG_DATA_HOME%/NativeGame"}
    ]'
    gsv_create_snapshot "$locs" 0 "token-backup" "$mock_vault"

    # Delete original
    rm -rf "$mock_home/.local/share/NativeGame"
    assert_true "[ ! -d '$mock_home/.local/share/NativeGame' ]" "Original game folder removed"

    # Restore without restore_root -> resolves via %XDG_DATA_HOME%
    gsv_restore_snapshot "latest" "NativeGame" 0 "" "$mock_vault"
    assert_true "[ -f '$mock_home/.local/share/NativeGame/save.sav' ]" "Restored to token destination"
    assert_equals "original_native_data" "$(cat "$mock_home/.local/share/NativeGame/save.sav")" "Restored token content matches"

    HOME="$orig_home"
    unset XDG_DATA_HOME
}

test_vault_rollback_collision_protection() {
    local mock_vault="$TEST_TMP_DIR/mock_vault_rb"
    local mock_saves="$TEST_TMP_DIR/mock_saves_rb"
    local restore_dest="$TEST_TMP_DIR/mock_restore_rb"
    mkdir -p "$mock_saves/GameC"
    echo "snapshot_version_c" > "$mock_saves/GameC/save.dat"

    local locs='[{"Game": "GameC", "OriginalPath": "'"$mock_saves/GameC"'"}]'
    gsv_create_snapshot "$locs" 0 "rb-backup" "$mock_vault"

    # Pre-populate restore destination with conflicting data
    mkdir -p "$restore_dest/GameC"
    echo "conflicting_local_data" > "$restore_dest/GameC/save.dat"

    gsv_restore_snapshot "latest" "GameC" 0 "$restore_dest" "$mock_vault"
    local status=$?
    assert_equals "0" "$status" "Restore succeeded despite collision"

    # Verify destination received restored snapshot version
    assert_equals "snapshot_version_c" "$(cat "$restore_dest/GameC/save.dat")" "Target destination has restored snapshot file"

    # Verify conflicting data was preserved in rollback
    assert_true "[ -d '$mock_vault/rollback' ]" "Rollback directory created"
    local rb_files
    rb_files="$(find "$mock_vault/rollback" -type f -name "save.dat")"
    assert_true "[ -n '$rb_files' ]" "Conflicting file found in rollback directory"
    local rb_content
    rb_content="$(cat $rb_files)"
    assert_equals "conflicting_local_data" "$rb_content" "Rollback preserved conflicting local data"
}

test_vault_dry_run_restore() {
    local mock_vault="$TEST_TMP_DIR/mock_vault_dry_rest"
    local mock_saves="$TEST_TMP_DIR/mock_saves_dry_rest"
    local restore_dest="$TEST_TMP_DIR/mock_restore_dry_dest"
    mkdir -p "$mock_saves/GameD"
    echo "snapshot_d" > "$mock_saves/GameD/d.sav"

    local locs='[{"Game": "GameD", "OriginalPath": "'"$mock_saves/GameD"'"}]'
    gsv_create_snapshot "$locs" 0 "dry-restore-snap" "$mock_vault"

    # Pre-populate target
    mkdir -p "$restore_dest/GameD"
    echo "untouched_data" > "$restore_dest/GameD/d.sav"

    gsv_restore_snapshot "latest" "GameD" 1 "$restore_dest" "$mock_vault"
    local status=$?
    assert_equals "0" "$status" "Dry run restore returned success"

    assert_equals "untouched_data" "$(cat "$restore_dest/GameD/d.sav")" "Destination data untouched in dry run"
    assert_true "[ ! -d '$mock_vault/rollback' ]" "No rollback directory created during dry run"
}

test_vault_restore_zero_matching_games() {
    local mock_vault="$TEST_TMP_DIR/mock_vault_zero"
    local mock_saves="$TEST_TMP_DIR/mock_saves_zero"
    local restore_dest="$TEST_TMP_DIR/mock_restore_zero"
    mkdir -p "$mock_saves/GameE"
    echo "snap_e" > "$mock_saves/GameE/e.sav"

    local locs='[{"Game": "GameE", "OriginalPath": "'"$mock_saves/GameE"'"}]'
    gsv_create_snapshot "$locs" 0 "zero-match-snap" "$mock_vault"

    gsv_restore_snapshot "latest" "NonExistentGameX,NonExistentGameY" 0 "$restore_dest" "$mock_vault"
    local status=$?
    assert_equals "0" "$status" "Restore with 0 matching games exits cleanly with status 0"
    assert_true "[ ! -d '$restore_dest/GameE' ]" "Nothing was restored"
}

# ==============================================================================
# Unit Tests: ui.sh
# ==============================================================================

test_ui_mode_detection_override() {
    local mode
    mode=$(GSV_UI_MODE="cli" gsv_ui_detect)
    assert_equals "cli" "$mode" "Override cli returns cli"

    mode=$(GSV_UI_MODE="gui" gsv_ui_detect)
    assert_equals "zenity" "$mode" "Override gui returns zenity"

    mode=$(GSV_UI_MODE="zenity" gsv_ui_detect)
    assert_equals "zenity" "$mode" "Override zenity returns zenity"

    mode=$(GSV_UI_MODE="dialog" gsv_ui_detect)
    assert_equals "dialog" "$mode" "Override dialog returns dialog"

    mode=$(GSV_UI_MODE="whiptail" gsv_ui_detect)
    assert_equals "whiptail" "$mode" "Override whiptail returns whiptail"

    mode=$(GSV_UI_MODE="tui" gsv_ui_detect)
    assert_true "[ '$mode' = 'whiptail' ] || [ '$mode' = 'dialog' ] || [ '$mode' = 'cli' ]" "Override tui selects available TUI tool"
}

test_ui_mode_detection_auto() {
    local mode
    # Auto-detection when DISPLAY is set and zenity is in PATH
    mode=$(unset GSV_UI_MODE; DISPLAY=":0" gsv_ui_detect)
    assert_equals "zenity" "$mode" "Auto-detection chooses zenity when DISPLAY is active"

    # Auto-detection in headless / non-terminal without display falls back to cli
    mode=$(unset GSV_UI_MODE DISPLAY WAYLAND_DISPLAY; echo "" | gsv_ui_detect)
    assert_equals "cli" "$mode" "Auto-detection chooses cli when headless without DISPLAY"
}

test_ui_message_cli() {
    local out
    out=$(GSV_UI_MODE="cli" gsv_ui_message "Test Info" "Hello Info World" "info")
    local status=$?
    assert_equals "0" "$status" "gsv_ui_message info succeeded"

    out=$(GSV_UI_MODE="cli" gsv_ui_message "Test Warning" "Hello Warning" "warning")
    status=$?
    assert_equals "0" "$status" "gsv_ui_message warning succeeded"

    out=$(GSV_UI_MODE="cli" gsv_ui_message "Test Error" "Hello Error" "error")
    status=$?
    assert_equals "0" "$status" "gsv_ui_message error succeeded"
}

test_ui_confirm_cli() {
    echo "y" | GSV_UI_MODE="cli" gsv_ui_confirm "Confirm" "Proceed with operation?"
    assert_equals "0" "$?" "Confirm with 'y' returns 0"

    echo "yes" | GSV_UI_MODE="cli" gsv_ui_confirm "Confirm" "Proceed with operation?"
    assert_equals "0" "$?" "Confirm with 'yes' returns 0"

    echo "n" | GSV_UI_MODE="cli" gsv_ui_confirm "Confirm" "Proceed with operation?"
    assert_equals "1" "$?" "Confirm with 'n' returns 1"

    echo "no" | GSV_UI_MODE="cli" gsv_ui_confirm "Confirm" "Proceed with operation?"
    assert_equals "1" "$?" "Confirm with 'no' returns 1"

    echo "" | GSV_UI_MODE="cli" gsv_ui_confirm "Confirm" "Proceed with operation?"
    assert_equals "1" "$?" "Confirm with empty/default returns 1"
}

test_ui_menu_cli() {
    local choice
    choice=$(printf "2\n" | GSV_UI_MODE="cli" gsv_ui_menu "Main Menu" "Choose an option:" "scan" "Scan games" "backup" "Backup saves" "restore" "Restore saves")
    assert_equals "backup" "$choice" "Menu selection by number 2 returns 'backup'"

    choice=$(printf "restore\n" | GSV_UI_MODE="cli" gsv_ui_menu "Main Menu" "Choose an option:" "scan" "Scan games" "backup" "Backup saves" "restore" "Restore saves")
    assert_equals "restore" "$choice" "Menu selection by tag returns 'restore'"

    choice=$(printf "invalid\n" | GSV_UI_MODE="cli" gsv_ui_menu "Main Menu" "Choose an option:" "scan" "Scan games" "exit" "Exit")
    local status=$?
    assert_equals "1" "$status" "Invalid menu choice returns exit status 1"
}

test_ui_checklist_cli() {
    local selected
    # Selection by comma-separated numbers
    selected=$(printf "1,3\n" | GSV_UI_MODE="cli" gsv_ui_checklist "Game Select" "Select games:" "GameA" "Path A" "OFF" "GameB" "Path B" "OFF" "GameC" "Path C" "OFF")
    assert_match "GameA" "$selected" "Selected contains GameA"
    assert_match "GameC" "$selected" "Selected contains GameC"
    assert_true "[[ ! '$selected' =~ 'GameB' ]]" "Selected does not contain GameB"

    # Selection by default (Enter takes items marked ON/TRUE)
    selected=$(printf "\n" | GSV_UI_MODE="cli" gsv_ui_checklist "Game Select" "Select games:" "GameA" "Path A" "ON" "GameB" "Path B" "OFF" "GameC" "Path C" "TRUE")
    assert_match "GameA" "$selected" "Default contains GameA"
    assert_match "GameC" "$selected" "Default contains GameC"
    assert_true "[[ ! '$selected' =~ 'GameB' ]]" "Default does not contain GameB"

    # Selection by "all"
    selected=$(printf "all\n" | GSV_UI_MODE="cli" gsv_ui_checklist "Game Select" "Select games:" "GameA" "Path A" "OFF" "GameB" "Path B" "OFF")
    assert_match "GameA" "$selected" "'all' contains GameA"
    assert_match "GameB" "$selected" "'all' contains GameB"

    # Selection by "none"
    selected=$(printf "none\n" | GSV_UI_MODE="cli" gsv_ui_checklist "Game Select" "Select games:" "GameA" "Path A" "ON" "GameB" "Path B" "ON")
    assert_equals "" "$selected" "'none' returns empty selection"
}

test_ui_dir_picker_cli() {
    local picked
    picked=$(printf "/custom/game/vault\n" | GSV_UI_MODE="cli" gsv_ui_dir_picker "Select Vault" "/default/vault")
    assert_equals "/custom/game/vault" "$picked" "Custom dir input returns custom path"

    picked=$(printf "\n" | GSV_UI_MODE="cli" gsv_ui_dir_picker "Select Vault" "/default/vault")
    assert_equals "/default/vault" "$picked" "Default dir input returns default path"
}

test_ui_input_cli() {
    local val
    val=$(printf "my-custom-snapshot\n" | GSV_UI_MODE="cli" gsv_ui_input "Snapshot Label" "Enter label:" "manual-backup")
    assert_equals "my-custom-snapshot" "$val" "Custom input string returned"

    val=$(printf "\n" | GSV_UI_MODE="cli" gsv_ui_input "Snapshot Label" "Enter label:" "manual-backup")
    assert_equals "manual-backup" "$val" "Default input string returned on empty enter"
}

test_doctor_health_check() {
    local report_file="$TEST_TMP_DIR/doctor_report.txt"
    local status
    gsv_run_doctor "$report_file"
    status=$?
    assert_equals "0" "$status" "gsv_run_doctor returned 0 for healthy environment"
    assert_true "[ -f '$report_file' ]" "Doctor report file created"

    local report_content
    report_content=$(cat "$report_file")
    assert_match "GameSaveVault Health Check" "$report_content" "Report contains title"
    assert_match "jq" "$report_content" "Report mentions jq"
    assert_match "rsync" "$report_content" "Report mentions rsync"
    assert_match "Vault Path" "$report_content" "Report checks Vault Path"
}

test_launch_dashboard_exit() {
    # Option 9 is Exit in the main menu loop
    printf "9\n" | GSV_UI_MODE="cli" gsv_launch_dashboard
    local status=$?
    assert_equals "0" "$status" "Dashboard loop exits cleanly on option 9"
}

test_ui_action_backup_gamename_resolution() {
    local mock_cfg="$TEST_TMP_DIR/mock_backup_ui_cfg"
    local mock_vault="$TEST_TMP_DIR/mock_backup_ui_vault"
    local mock_saves="$TEST_TMP_DIR/mock_backup_ui_saves"
    mkdir -p "$mock_cfg" "$mock_saves/MyCustomGame" "$mock_vault"
    echo '{"BackupRoot": "'"$mock_vault"'"}' > "$mock_cfg/settings.json"
    export GSV_CONFIG_DIR="$mock_cfg"

    echo "save_content" > "$mock_saves/MyCustomGame/save.sav"

    cat <<EOF > "$mock_cfg/scan-database.json"
{
  "Version": 1,
  "Roots": [],
  "Locations": [
    {
      "GameId": "custom-game-1",
      "GameName": "MyCustomGame",
      "Source": "Custom",
      "ResolvedPath": "$mock_saves/MyCustomGame",
      "FileCount": 1,
      "Bytes": 12
    }
  ]
}
EOF

    # In CLI mode, checklist prompts user to toggle/select. "1" toggles item 1, "done" completes selection.
    # Then dry run prompt "y", snapshot label "ui-test-snap".
    local out
    out=$(printf "1\ndone\ny\nui-test-snap\n" | GSV_UI_MODE="cli" _gsv_ui_action_backup 2>&1)
    local status=$?
    assert_equals "0" "$status" "Backup UI action succeeds with GameName schema"
    assert_match "MyCustomGame" "$out" "Checklist presents game name MyCustomGame"
}

test_ui_action_browse_snapshots_jq() {
    local mock_cfg="$TEST_TMP_DIR/mock_browse_jq_cfg"
    local mock_vault="$TEST_TMP_DIR/mock_browse_jq_vault"
    local mock_saves="$TEST_TMP_DIR/mock_browse_jq_saves"
    mkdir -p "$mock_cfg" "$mock_saves/BrowseGameA" "$mock_vault"
    echo '{"BackupRoot": "'"$mock_vault"'"}' > "$mock_cfg/settings.json"
    export GSV_CONFIG_DIR="$mock_cfg"

    echo "save_a" > "$mock_saves/BrowseGameA/save.dat"

    local locs='[{"Game": "BrowseGameA", "OriginalPath": "'"$mock_saves/BrowseGameA"'"}]'
    GSV_JSON_TOOL="jq"
    gsv_create_snapshot "$locs" 0 "browse-label-jq" "$mock_vault" >/dev/null 2>&1

    local out
    out=$(printf "1\n" | GSV_UI_MODE="cli" GSV_JSON_TOOL="jq" _gsv_ui_action_browse_snapshots)
    local status=$?
    assert_equals "0" "$status" "_gsv_ui_action_browse_snapshots with jq succeeded"
    assert_match "BrowseGameA" "$out" "Snapshot details contains game name under jq"
    assert_match "browse-label-jq" "$out" "Snapshot details contains label under jq"
}

test_ui_action_browse_snapshots_python() {
    local mock_cfg="$TEST_TMP_DIR/mock_browse_py_cfg"
    local mock_vault="$TEST_TMP_DIR/mock_browse_py_vault"
    local mock_saves="$TEST_TMP_DIR/mock_browse_py_saves"
    mkdir -p "$mock_cfg" "$mock_saves/BrowseGamePy" "$mock_vault"
    echo '{"BackupRoot": "'"$mock_vault"'"}' > "$mock_cfg/settings.json"
    export GSV_CONFIG_DIR="$mock_cfg"

    echo "save_py" > "$mock_saves/BrowseGamePy/save.dat"

    local locs='[{"Game": "BrowseGamePy", "OriginalPath": "'"$mock_saves/BrowseGamePy"'"}]'
    GSV_JSON_TOOL="python3"
    gsv_create_snapshot "$locs" 0 "browse-label-py" "$mock_vault" >/dev/null 2>&1

    local out
    out=$(printf "1\n" | GSV_UI_MODE="cli" GSV_JSON_TOOL="python3" _gsv_ui_action_browse_snapshots)
    local status=$?
    assert_equals "0" "$status" "_gsv_ui_action_browse_snapshots with python3 succeeded"
    assert_match "BrowseGamePy" "$out" "Snapshot details contains game name under python3"
    assert_match "browse-label-py" "$out" "Snapshot details contains label under python3"
}

test_ui_action_restore_jq() {
    local mock_cfg="$TEST_TMP_DIR/mock_restore_ui_jq_cfg"
    local mock_vault="$TEST_TMP_DIR/mock_restore_ui_jq_vault"
    local mock_saves="$TEST_TMP_DIR/mock_restore_ui_jq_saves"
    mkdir -p "$mock_cfg" "$mock_saves/RestoreGameJQ" "$mock_vault"
    echo '{"BackupRoot": "'"$mock_vault"'"}' > "$mock_cfg/settings.json"
    export GSV_CONFIG_DIR="$mock_cfg"

    echo "restore_data_jq" > "$mock_saves/RestoreGameJQ/save.dat"

    local locs='[{"Game": "RestoreGameJQ", "OriginalPath": "'"$mock_saves/RestoreGameJQ"'"}]'
    GSV_JSON_TOOL="jq"
    gsv_create_snapshot "$locs" 0 "restore-snap-jq" "$mock_vault" >/dev/null 2>&1

    local out
    out=$(printf "1\n1\n\ny\n" | GSV_UI_MODE="cli" GSV_JSON_TOOL="jq" _gsv_ui_action_restore)
    local status=$?
    assert_equals "0" "$status" "_gsv_ui_action_restore with jq succeeded"
    assert_match "Restore Dry Run Complete" "$out" "Restore action confirmed dry run with jq"
}

test_ui_action_restore_python() {
    local mock_cfg="$TEST_TMP_DIR/mock_restore_ui_py_cfg"
    local mock_vault="$TEST_TMP_DIR/mock_restore_ui_py_vault"
    local mock_saves="$TEST_TMP_DIR/mock_restore_ui_py_saves"
    mkdir -p "$mock_cfg" "$mock_saves/RestoreGamePy" "$mock_vault"
    echo '{"BackupRoot": "'"$mock_vault"'"}' > "$mock_cfg/settings.json"
    export GSV_CONFIG_DIR="$mock_cfg"

    echo "restore_data_py" > "$mock_saves/RestoreGamePy/save.dat"

    local locs='[{"Game": "RestoreGamePy", "OriginalPath": "'"$mock_saves/RestoreGamePy"'"}]'
    GSV_JSON_TOOL="python3"
    gsv_create_snapshot "$locs" 0 "restore-snap-py" "$mock_vault" >/dev/null 2>&1

    local out
    out=$(printf "1\n1\n\ny\n" | GSV_UI_MODE="cli" GSV_JSON_TOOL="python3" _gsv_ui_action_restore)
    local status=$?
    assert_equals "0" "$status" "_gsv_ui_action_restore with python3 succeeded"
    assert_match "Restore Dry Run Complete" "$out" "Restore action confirmed dry run with python3"
}

test_ui_action_configure_vault() {
    local mock_cfg="$TEST_TMP_DIR/mock_cfg_test"
    local old_vault="$TEST_TMP_DIR/old_mock_vault"
    local new_vault="$TEST_TMP_DIR/new_mock_vault"
    mkdir -p "$mock_cfg" "$old_vault"

    export GSV_CONFIG_DIR="$mock_cfg"
    echo '{"BackupRoot": "'"$old_vault"'"}' > "$mock_cfg/settings.json"

    # Use here-string so _gsv_ui_action_configure_vault runs in current shell, not a subshell pipeline
    GSV_UI_MODE="cli" _gsv_ui_action_configure_vault <<< "$(printf "%s\ny\n" "$new_vault")" >/dev/null 2>&1
    local status=$?
    assert_equals "0" "$status" "_gsv_ui_action_configure_vault succeeded"

    # Verify settings.json exists and BackupRoot is set
    local settings_file="$mock_cfg/settings.json"
    assert_true "[ -f '$settings_file' ]" "settings.json created"
    local configured_path
    configured_path="$(gsv_json_get "$settings_file" ".BackupRoot")"
    assert_equals "$new_vault" "$configured_path" "settings.json has correct BackupRoot"
    assert_equals "$new_vault" "$GSV_VAULT_PATH" "GSV_VAULT_PATH was updated"
}

test_dashboard_game_count_python_fallback() {
    local mock_db="$TEST_TMP_DIR/mock_db_count.json"
    cat <<'EOF' > "$mock_db"
{
  "Version": "1.0",
  "Locations": [
    {"Game": "Game1", "OriginalPath": "/path/1"},
    {"Game": "Game2", "OriginalPath": "/path/2"}
  ]
}
EOF
    local count
    count=$(GSV_JSON_TOOL="python3" _gsv_ui_get_game_count "$mock_db")
    assert_equals "2" "$count" "_gsv_ui_get_game_count returns 2 under python3 fallback"
}

# ==============================================================================
# CLI Dispatcher Tests (gamevault.sh and linux/gamevault.sh)
# ==============================================================================

test_cli_root_forwarding() {
    local root_sh="$REPO_ROOT/gamevault.sh"
    assert_true "[ -f '$root_sh' ]" "Root gamevault.sh exists"
    assert_true "[ -x '$root_sh' ]" "Root gamevault.sh is executable"

    local output code
    output=$("$root_sh" --help 2>&1)
    code=$?
    assert_equals "0" "$code" "Root gamevault.sh --help exits with 0"
    assert_match "GameSaveVault" "$output" "Root script outputs GameSaveVault header"
    assert_match "Commands:" "$output" "Root script lists commands"
}

test_cli_help_options() {
    local linux_sh="$REPO_ROOT/linux/gamevault.sh"
    assert_true "[ -f '$linux_sh' ]" "linux/gamevault.sh exists"
    assert_true "[ -x '$linux_sh' ]" "linux/gamevault.sh is executable"

    local out1 out2 out3 code
    out1=$("$linux_sh" help 2>&1)
    code=$?
    assert_equals "0" "$code" "gamevault.sh help exits with 0"
    assert_match "Usage:" "$out1" "help contains Usage:"

    out2=$("$linux_sh" --help 2>&1)
    code=$?
    assert_equals "0" "$code" "gamevault.sh --help exits with 0"

    out3=$("$linux_sh" -h 2>&1)
    code=$?
    assert_equals "0" "$code" "gamevault.sh -h exits with 0"
}

test_cli_no_args_non_interactive() {
    local root_sh="$REPO_ROOT/gamevault.sh"
    local output code
    output=$("$root_sh" < /dev/null 2>&1)
    code=$?
    assert_equals "0" "$code" "No-args in non-interactive mode exits with 0"
    assert_match "Usage:" "$output" "No-args in non-interactive mode outputs usage"
}

test_cli_doctor() {
    local root_sh="$REPO_ROOT/gamevault.sh"
    local output code
    output=$("$root_sh" doctor 2>&1)
    code=$?
    assert_equals "0" "$code" "gamevault.sh doctor exits with 0"
    assert_match "Health Check" "$output" "gamevault.sh doctor outputs health check summary"
}

test_cli_invalid_command() {
    local root_sh="$REPO_ROOT/gamevault.sh"
    local output code
    output=$("$root_sh" invalid-command-name 2>&1)
    code=$?
    assert_equals "1" "$code" "Invalid command exits with status 1"
    assert_match "Unknown command" "$output" "Invalid command outputs unknown command error"
}

test_cli_scan_and_scan_db() {
    local root_sh="$REPO_ROOT/gamevault.sh"
    local test_env_dir="$TEST_TMP_DIR/cli_scan_env"
    mkdir -p "$test_env_dir/config" "$test_env_dir/custom_games/MyGame"
    echo "save_data" > "$test_env_dir/custom_games/MyGame/slot1.sav"

    local output code
    # 1. scan-db with no database yet
    output=$(GSV_CONFIG_DIR="$test_env_dir/config" "$root_sh" scan-db 2>&1)
    code=$?
    assert_equals "0" "$code" "scan-db with empty db exits 0"
    assert_match "No scan database" "$output" "scan-db reports no database found"

    # 2. scan-folders on custom dir
    output=$(GSV_CONFIG_DIR="$test_env_dir/config" "$root_sh" scan-folders --dirs "$test_env_dir/custom_games" 2>&1)
    code=$?
    assert_equals "0" "$code" "scan-folders exits 0"
    assert_match "MyGame" "$output" "scan-folders finds MyGame"

    # 3. scan-db after scanning
    output=$(GSV_CONFIG_DIR="$test_env_dir/config" "$root_sh" scan-db 2>&1)
    code=$?
    assert_equals "0" "$code" "scan-db after scan exits 0"
    assert_match "MyGame" "$output" "scan-db displays MyGame"

    # 4. scan command
    output=$(GSV_CONFIG_DIR="$test_env_dir/config" "$root_sh" scan 2>&1)
    code=$?
    assert_equals "0" "$code" "scan exits 0"
}

test_cli_backup_and_restore_dry_run() {
    local root_sh="$REPO_ROOT/gamevault.sh"
    local test_env_dir="$TEST_TMP_DIR/cli_backup_dry"
    local mock_config="$test_env_dir/config"
    local mock_vault="$test_env_dir/vault"
    local mock_game_dir="$test_env_dir/games/TestHero"
    mkdir -p "$mock_config" "$mock_vault" "$mock_game_dir"
    echo "hero_save_content" > "$mock_game_dir/hero.sav"

    # Populate scan database
    local locs='[
      {
        "GameId": "custom-testhero",
        "GameName": "TestHero",
        "Source": "Custom",
        "AppId": "",
        "Token": "HOME",
        "RelativePath": "games/TestHero",
        "AbsolutePath": "'"$mock_game_dir"'",
        "ResolvedPath": "'"$mock_game_dir"'",
        "Kind": "Directory",
        "FileCount": 1,
        "Bytes": 17,
        "Origin": "custom"
      }
    ]'
    GSV_CONFIG_DIR="$mock_config" gsv_update_scan_database "$locs" "[\"$test_env_dir/games\"]"

    # Backup dry run
    local out_backup code
    out_backup=$(GSV_CONFIG_DIR="$mock_config" "$root_sh" backup --dry-run --vault "$mock_vault" 2>&1)
    code=$?
    assert_equals "0" "$code" "backup --dry-run exits 0"
    assert_match "dry-run" "$out_backup" "backup --dry-run mentions dry-run"
    assert_true "[ ! -d '$mock_vault/snapshots' ]" "backup --dry-run created no snapshot directory"

    # Real backup so restore dry run has a snapshot to inspect
    GSV_CONFIG_DIR="$mock_config" "$root_sh" backup --label "dry-test" --vault "$mock_vault" >/dev/null 2>&1

    # Restore dry run
    local out_restore
    out_restore=$(GSV_CONFIG_DIR="$mock_config" "$root_sh" restore --dry-run --vault "$mock_vault" 2>&1)
    code=$?
    assert_equals "0" "$code" "restore --dry-run exits 0"
    assert_match "dry-run" "$out_restore" "restore --dry-run mentions dry-run"
}

test_cli_snapshots() {
    local root_sh="$REPO_ROOT/gamevault.sh"
    local test_env_dir="$TEST_TMP_DIR/cli_snapshots_env"
    local mock_config="$test_env_dir/config"
    local mock_vault="$test_env_dir/vault"
    local mock_game_dir="$test_env_dir/games/Chrono"
    mkdir -p "$mock_config" "$mock_vault" "$mock_game_dir"
    echo "chrono_save" > "$mock_game_dir/save.dat"

    local locs='[
      {
        "GameId": "custom-chrono",
        "GameName": "ChronoTrigger",
        "Source": "Custom",
        "Token": "HOME",
        "RelativePath": "games/Chrono",
        "AbsolutePath": "'"$mock_game_dir"'",
        "ResolvedPath": "'"$mock_game_dir"'",
        "Kind": "Directory",
        "FileCount": 1,
        "Bytes": 11,
        "Origin": "custom"
      }
    ]'
    GSV_CONFIG_DIR="$mock_config" gsv_update_scan_database "$locs"

    # Snapshots before any backup
    local out_none code
    out_none=$("$root_sh" snapshots --vault "$mock_vault" 2>&1)
    code=$?
    assert_equals "0" "$code" "snapshots exits 0 when empty"
    assert_match "No snapshots found" "$out_none" "snapshots reports no snapshots found"

    # Create backup
    GSV_CONFIG_DIR="$mock_config" "$root_sh" backup --label "chrono-release" --vault "$mock_vault" >/dev/null 2>&1

    # Snapshots table view
    local out_table
    out_table=$("$root_sh" snapshots --vault "$mock_vault" 2>&1)
    code=$?
    assert_equals "0" "$code" "snapshots exits 0 after backup"
    assert_match "chrono-release" "$out_table" "snapshots output includes label chrono-release"

    # Snapshots json view
    local out_json
    out_json=$("$root_sh" snapshots --vault "$mock_vault" --json 2>&1)
    code=$?
    assert_equals "0" "$code" "snapshots --json exits 0"
    assert_match "chrono-release" "$out_json" "snapshots --json includes label"
}

test_root_install_shims() {
    assert_true "[ -f '$REPO_ROOT/Install.ps1' ]" "Root Install.ps1 exists"
    assert_true "[ -f '$REPO_ROOT/Install-GameSaveVault.ps1' ]" "Root Install-GameSaveVault.ps1 exists"
    assert_true "grep -q 'windows.*Install\.ps1' '$REPO_ROOT/Install.ps1'" "Root Install.ps1 forwards to windows/Install.ps1"
    assert_true "grep -q 'windows.*Install-GameSaveVault\.ps1' '$REPO_ROOT/Install-GameSaveVault.ps1'" "Root Install-GameSaveVault.ps1 forwards to windows/Install-GameSaveVault.ps1"
}

test_vault_restore_proton_prefix_priority() {
    local mock_vault="$TEST_TMP_DIR/mock_vault_proton"
    local prefix_dir="$TEST_TMP_DIR/steam_compat/12345/pfx/drive_c/users/steamuser/AppData/Local"
    local game_save_dir="$prefix_dir/ProtonGame"
    mkdir -p "$game_save_dir"
    echo "proton_save_original" > "$game_save_dir/save.bin"

    local locs='[
      {
        "Game": "ProtonGame",
        "OriginalPath": "'"$game_save_dir"'",
        "TokenPath": "%LOCALAPPDATA%/ProtonGame"
      }
    ]'
    gsv_create_snapshot "$locs" 0 "proton-backup" "$mock_vault"
    assert_equals "0" "$?" "gsv_create_snapshot succeeded for Proton game"

    # Scenario 1: Remove the save folder, but keep parent prefix directory intact
    rm -rf "$game_save_dir"
    assert_true "[ ! -d '$game_save_dir' ]" "Game save folder removed"
    assert_true "[ -d '$prefix_dir' ]" "Parent prefix directory still exists"

    # Restore: should prioritize orig_path because parent exists
    gsv_restore_snapshot "latest" "ProtonGame" 0 "" "$mock_vault"
    assert_equals "0" "$?" "gsv_restore_snapshot returned success"
    assert_true "[ -f '$game_save_dir/save.bin' ]" "Restored directly into Proton prefix orig_path"
    assert_equals "proton_save_original" "$(cat "$game_save_dir/save.bin")" "Restored file content matches"

    # Scenario 2: Prefix does NOT exist on machine (parent missing) -> falls back to token path
    rm -rf "$TEST_TMP_DIR/steam_compat"
    assert_true "[ ! -d '$prefix_dir' ]" "Proton prefix parent deleted"

    local orig_home="$HOME"
    local mock_home="$TEST_TMP_DIR/mock_home_fallback"
    mkdir -p "$mock_home/.local/share"
    HOME="$mock_home"
    export XDG_DATA_HOME="$mock_home/.local/share"

    gsv_restore_snapshot "latest" "ProtonGame" 0 "" "$mock_vault"
    assert_equals "0" "$?" "gsv_restore_snapshot fallback returned success"
    assert_true "[ -f '$mock_home/.local/share/ProtonGame/save.bin' ]" "Fell back to token_path destination"
    assert_equals "proton_save_original" "$(cat "$mock_home/.local/share/ProtonGame/save.bin")" "Fallback restored content matches"

    HOME="$orig_home"
    unset XDG_DATA_HOME
}

test_vault_paths_and_dirs_with_spaces() {
    local vault_with_spaces="$TEST_TMP_DIR/My Vault With Spaces"
    mkdir -p "$vault_with_spaces"

    local save_dir="$TEST_TMP_DIR/Saved Games/My Special Game"
    mkdir -p "$save_dir"
    echo "space_data" > "$save_dir/save.dat"

    # Snapshot into vault with spaces
    local locs='[{"Game": "My Special Game", "OriginalPath": "'"$save_dir"'"}]'
    gsv_create_snapshot "$locs" 0 "backup with spaces" "$vault_with_spaces"
    assert_equals "0" "$?" "gsv_create_snapshot into vault with spaces succeeded"

    # Verify gsv_resolve_snapshot_dir with spaces
    local resolved_dir
    resolved_dir="$(gsv_resolve_snapshot_dir "latest" "$vault_with_spaces")"
    assert_equals "0" "$?" "gsv_resolve_snapshot_dir succeeded with spaces"
    assert_true "[ -d '$resolved_dir' ]" "Resolved directory exists"

    # Verify gsv_list_snapshots with spaces
    local list_out
    list_out="$(gsv_list_snapshots "$vault_with_spaces")"
    assert_equals "0" "$?" "gsv_list_snapshots succeeded with spaces"
    assert_match "backup with spaces" "$list_out" "Table listing contains label"

    local list_json
    list_json="$(gsv_list_snapshots "$vault_with_spaces" --json)"
    assert_equals "0" "$?" "gsv_list_snapshots --json succeeded with spaces"
    assert_match "backup with spaces" "$list_json" "JSON listing contains label"

    # Verify cmd_scan_folders with colon-separated paths containing spaces
    local scan_dir1="$TEST_TMP_DIR/Saved Games/Folder One"
    local scan_dir2="$TEST_TMP_DIR/Saved Games/Folder Two"
    mkdir -p "$scan_dir1" "$scan_dir2"
    echo "save1" > "$scan_dir1/slot1.sav"
    echo "save2" > "$scan_dir2/slot2.sav"

    # Test running cmd_scan_folders via gamevault.sh
    local scan_out
    scan_out="$("$REPO_ROOT/linux/gamevault.sh" scan-folders --dirs "$scan_dir1:$scan_dir2" 2>&1)"
    local scan_status=$?
    assert_equals "0" "$scan_status" "scan-folders with spaces succeeded"
    assert_match "Folder One" "$scan_out" "scan-folders found Folder One"
    assert_match "Folder Two" "$scan_out" "scan-folders found Folder Two"
}

test_windows_manifest_cross_platform_compatibility() {
    local mock_vault="$TEST_TMP_DIR/mock_vault_win"
    local snap_id="2026-11-11_150000"
    local snap_dir="$mock_vault/snapshots/$snap_id"
    local payload_dir="$snap_dir/payload/0000"
    mkdir -p "$payload_dir"
    echo "win_save_payload_content" > "$payload_dir/save.bin"

    # Windows GSV manifest schema
    cat <<EOF > "$snap_dir/manifest.json"
{
  "Version": 1,
  "Tool": "GameSaveVault",
  "ToolVersion": "2.0.0",
  "CreatedUtc": "2026-11-11T15:00:00.0000000Z",
  "Label": "windows-cross-platform-test",
  "Machine": "WIN-GAMING-RIG",
  "User": "Gamer",
  "Os": "Microsoft Windows NT 10.0.22631.0",
  "BackupRoot": "C:\\\\Users\\\\Gamer\\\\Documents\\\\GameSaves",
  "EntryCount": 1,
  "TotalFiles": 1,
  "TotalBytes": 24,
  "Entries": [
    {
      "GameId": "win_rpg",
      "GameName": "Windows RPG",
      "Source": "Custom",
      "Token": "APPDATA",
      "RelativePath": "WindowsRPG\\\\Saves",
      "AbsolutePath": "C:\\\\Users\\\\Gamer\\\\AppData\\\\Roaming\\\\WindowsRPG\\\\Saves",
      "Kind": "Directory",
      "Payload": "payload\\\\0000",
      "FileCount": 1,
      "Bytes": 24,
      "Files": [
        {
          "Path": "save.bin",
          "Size": 24,
          "LastWriteUtc": "2026-11-11T15:00:00.0000000Z"
        }
      ]
    }
  ],
  "Errors": []
}
EOF

    # 1. Test gsv_list_snapshots reads Windows manifest metadata
    local list_out
    list_out="$(gsv_list_snapshots "$mock_vault")"
    assert_equals "0" "$?" "gsv_list_snapshots succeeded for Windows manifest"
    assert_match "windows-cross-platform-test" "$list_out" "Table listing includes Windows label"
    assert_match "2026-11-11 15:00:00" "$list_out" "Table listing displays CreatedUtc"

    local list_json
    list_json="$(gsv_list_snapshots "$mock_vault" --json)"
    assert_equals "0" "$?" "gsv_list_snapshots --json succeeded for Windows manifest"
    assert_match "2026-11-11T15:00:00" "$list_json" "JSON listing includes CreatedAt from CreatedUtc"
    assert_match '"TotalGames": 1' "$list_json" "JSON listing includes TotalGames from EntryCount"

    # 2. Test gsv_restore_snapshot restores using Windows manifest fields
    local orig_home="$HOME"
    local mock_home="$TEST_TMP_DIR/mock_home_win_restore"
    mkdir -p "$mock_home/.config"
    HOME="$mock_home"
    export XDG_CONFIG_HOME="$mock_home/.config"

    # Restore Windows RPG by name
    gsv_restore_snapshot "latest" "Windows RPG" 0 "" "$mock_vault"
    assert_equals "0" "$?" "gsv_restore_snapshot succeeded for Windows snapshot"

    # Dest should resolve via %APPDATA%/WindowsRPG/Saves -> $mock_home/.config/WindowsRPG/Saves
    local restored_file="$mock_home/.config/WindowsRPG/Saves/save.bin"
    assert_true "[ -f '$restored_file' ]" "Windows snapshot restored to mapped Linux token location ($restored_file)"
    assert_equals "win_save_payload_content" "$(cat "$restored_file")" "Restored Windows payload content matches"

    HOME="$orig_home"
    unset XDG_CONFIG_HOME
}

# ==============================================================================
# Runner
# ==============================================================================
echo -e "${BLUE}=== Running Linux GameSaveVault Test Suite ===${NC}"
echo

run_test test_env_init "Environment initialization (gsv_init_env)"
run_test test_json_get_jq "JSON get with jq (gsv_json_get)"
run_test test_json_get_python "JSON get with python3 fallback (gsv_json_get)"
run_test test_json_set_jq "JSON set with jq (gsv_json_set)"
run_test test_json_set_python "JSON set with python3 fallback (gsv_json_set)"
run_test test_vault_resolution_order "Vault resolution order (gsv_resolve_vault_path)"
run_test test_token_mapping_roundtrip "Token mapping round-trip (gsv_path_to_token / gsv_token_to_path)"
run_test test_logging_helpers "Logging helpers (gsv_log_*)"

run_test test_scan_steam_proton "Scan Steam Proton prefix (gsv_scan_steam_proton)"
run_test test_scan_steam_proton_incomplete_prefix "Graceful handling of incomplete Proton prefixes"
run_test test_title_lookup_special_characters "JSON escaping and title lookup with special characters"
run_test test_scan_native_games "Scan native Linux game saves (gsv_scan_native_games)"
run_test test_scan_wine_lutris_heroic "Scan Wine, Lutris, and Heroic prefixes (gsv_scan_wine_lutris_heroic)"
run_test test_scan_emulators "Scan emulator save paths (gsv_scan_emulators)"
run_test test_deep_scan_folder "Deep scan custom folder for save extensions (gsv_deep_scan_folder)"
run_test test_update_scan_database "Update scan database JSON and schema compliance (gsv_update_scan_database)"
run_test test_scan_all "Aggregate all scans (gsv_scan_all)"

run_test test_vault_create_snapshot "Create snapshot with manifest and copied saves (gsv_create_snapshot)"
run_test test_vault_create_snapshot_from_file "Create snapshot from file input (gsv_create_snapshot)"
run_test test_vault_dry_run_backup "Dry run backup creates no files (gsv_create_snapshot)"
run_test test_vault_list_and_resolve_snapshots "List and resolve snapshots (gsv_list_snapshots / gsv_resolve_snapshot_dir)"
run_test test_vault_restore_snapshot "Restore snapshot with selective filtering (gsv_restore_snapshot)"
run_test test_vault_restore_token_path "Restore snapshot using token path resolution (gsv_restore_snapshot)"
run_test test_vault_rollback_collision_protection "Rollback safety preserves conflicting destination (gsv_restore_snapshot)"
run_test test_vault_dry_run_restore "Dry run restore makes no modifications (gsv_restore_snapshot)"
run_test test_vault_restore_zero_matching_games "Restore with 0 matching games exits cleanly (gsv_restore_snapshot)"

run_test test_ui_mode_detection_override "UI mode override via GSV_UI_MODE (gsv_ui_detect)"
run_test test_ui_mode_detection_auto "UI mode auto-detection (gsv_ui_detect)"
run_test test_ui_message_cli "Headless CLI message box (gsv_ui_message)"
run_test test_ui_confirm_cli "Headless CLI confirm prompt (gsv_ui_confirm)"
run_test test_ui_menu_cli "Headless CLI menu selection (gsv_ui_menu)"
run_test test_ui_checklist_cli "Headless CLI multi-select checklist (gsv_ui_checklist)"
run_test test_ui_dir_picker_cli "Headless CLI directory picker (gsv_ui_dir_picker)"
run_test test_ui_input_cli "Headless CLI text input prompt (gsv_ui_input)"
run_test test_doctor_health_check "Health check diagnostics (gsv_run_doctor)"
run_test test_launch_dashboard_exit "Interactive dashboard main menu loop (gsv_launch_dashboard)"
run_test test_ui_action_backup_gamename_resolution "Backup UI action with GameName schema (_gsv_ui_action_backup)"
run_test test_ui_action_browse_snapshots_jq "Browse snapshots UI action with jq (_gsv_ui_action_browse_snapshots)"
run_test test_ui_action_browse_snapshots_python "Browse snapshots UI action with python3 fallback (_gsv_ui_action_browse_snapshots)"
run_test test_ui_action_restore_jq "Restore snapshot UI action with jq (_gsv_ui_action_restore)"
run_test test_ui_action_restore_python "Restore snapshot UI action with python3 fallback (_gsv_ui_action_restore)"
run_test test_ui_action_configure_vault "Configure vault UI action settings update (_gsv_ui_action_configure_vault)"
run_test test_dashboard_game_count_python_fallback "Dashboard game count extraction under python3 fallback (_gsv_ui_get_game_count)"

run_test test_cli_root_forwarding "Root gamevault.sh forwards to linux/gamevault.sh"
run_test test_cli_help_options "CLI help options (--help, -h, help)"
run_test test_cli_no_args_non_interactive "CLI non-interactive execution with no arguments displays help"
run_test test_cli_doctor "CLI doctor command executes health check"
run_test test_cli_invalid_command "CLI invalid command returns exit code 1"
run_test test_cli_scan_and_scan_db "CLI scan, scan-folders, and scan-db workflows"
run_test test_cli_backup_and_restore_dry_run "CLI backup and restore --dry-run flags"
run_test test_cli_snapshots "CLI snapshots list in table and json formats"

run_test test_root_install_shims "Root install shims forward to windows/ scripts"
run_test test_vault_restore_proton_prefix_priority "Proton restore prioritizes orig_path when parent exists"
run_test test_vault_paths_and_dirs_with_spaces "Vault paths and custom dirs with spaces work without word-splitting"
run_test test_windows_manifest_cross_platform_compatibility "Windows-format manifest fields parsed and restored on Linux"

echo
echo -e "${BLUE}=== Test Summary ===${NC}"
echo "Total tests: $TESTS_RUN"
echo -e "Passed:      ${GREEN}$TESTS_PASSED${NC}"
if [ "$TESTS_FAILED" -gt 0 ]; then
    echo -e "Failed:      ${RED}$TESTS_FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed successfully.${NC}"
    exit 0
fi
