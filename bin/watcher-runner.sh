#!/bin/bash
set -uo pipefail

BASE_DIR="$HOME/.local/share/agentic-cleanup"
LOG_FILE="$BASE_DIR/data/watcher.log"

mkdir -p "$BASE_DIR/data"

for script in "$BASE_DIR/watchers"/*.sh; do
    [ -x "$script" ] || continue
    bash "$script" 2>>"$LOG_FILE" \
        || echo "$(date '+%F %T') WARN $(basename "$script") exit $?" >> "$LOG_FILE"
done

exit 0
