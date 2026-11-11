#!/usr/bin/env bash
# ==============================================================================
# gamevault.sh
# Root executable launcher for GameSaveVault on Linux.
# Forwards execution to linux/gamevault.sh preserving all arguments and exit code.
# ==============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/linux/gamevault.sh"

if [ ! -f "$TARGET" ]; then
    echo "Error: Target script not found: $TARGET" >&2
    exit 1
fi

exec "$TARGET" "$@"
