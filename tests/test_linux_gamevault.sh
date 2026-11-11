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
        return 1
    fi
    return 0
}

assert_true() {
    local condition="$1"
    local msg="${2:-Condition is not true}"
    if ! eval "$condition"; then
        echo -e "${RED}FAIL:${NC} $msg ($condition)"
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
    if output=$($test_func 2>&1); then
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
# Load common module
# ==============================================================================
COMMON_SH="$REPO_ROOT/linux/modules/common.sh"
if [ ! -f "$COMMON_SH" ]; then
    echo -e "${RED}ERROR: $COMMON_SH does not exist!${NC}"
    exit 1
fi
# shellcheck source=../linux/modules/common.sh
source "$COMMON_SH"

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
  "nested": {
    "child": "py_child"
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

    # 2. Mounted external drive takes 2nd priority
    local mock_mount="$TEST_TMP_DIR/mock_media/drive1/GameSaveVault"
    mkdir -p "$mock_mount"
    local GSV_MOUNT_ROOTS=("$TEST_TMP_DIR/mock_media")
    res="$(gsv_resolve_vault_path "")"
    assert_equals "$mock_mount" "$res" "Mounted drive priority 2"

    # Remove mock external drive
    rm -rf "$TEST_TMP_DIR/mock_media"
    GSV_MOUNT_ROOTS=()

    # 3. Settings.json BackupRoot takes 3rd priority
    local mock_config="$TEST_TMP_DIR/config"
    mkdir -p "$mock_config"
    echo '{"BackupRoot": "'"$TEST_TMP_DIR/settings_vault"'"}' > "$mock_config/settings.json"
    local orig_config="$GSV_CONFIG_DIR"
    GSV_CONFIG_DIR="$mock_config"

    res="$(gsv_resolve_vault_path "")"
    assert_equals "$TEST_TMP_DIR/settings_vault" "$res" "Settings BackupRoot priority 3"

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

    # Documents/My Games
    local path4="$mock_prefix/Documents/My Games/Skyrim Special Edition/Saves"
    local tok4
    tok4="$(gsv_path_to_token "$path4")"
    assert_equals "%DOCUMENTS%/Skyrim Special Edition/Saves" "$tok4" "Token Documents/My Games"
    local rev4
    rev4="$(gsv_token_to_path "$tok4" "$mock_prefix")"
    assert_equals "$path4" "$rev4" "Round-trip Documents/My Games"

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
