#!/bin/bash
set -euo pipefail

TARGET_DIR="$HOME/.local/share/agentic-cleanup"

if [ ! -d "$TARGET_DIR" ]; then
    echo "Nothing to uninstall: $TARGET_DIR does not exist."
    exit 0
fi

if [ -f "$TARGET_DIR/data/timer.pid" ]; then
    PID=$(cat "$TARGET_DIR/data/timer.pid")
    if kill -0 "$PID" 2>/dev/null; then
        echo "Killing active timer (PID $PID)..."
        pkill -P "$PID" 2>/dev/null || true
        kill "$PID" 2>/dev/null || true
    fi
fi

echo "Removing $TARGET_DIR..."
rm -rf "$TARGET_DIR"

echo ""
echo "Uninstall complete."
echo ""
echo "Reminder: You may also want to remove per-repo configuration:"
echo "  - Remove SessionStart/SessionEnd hooks from .claude/settings.local.json"
echo "  - Remove the 'cleanup' entry from .mcp.json"
