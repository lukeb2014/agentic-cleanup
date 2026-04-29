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

echo "Removing session-limit watcher scheduler..."

if systemctl --user --version &>/dev/null && [ -n "${XDG_RUNTIME_DIR:-}" ]; then
    systemctl --user disable --now agentic-cleanup-watcher.timer 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/agentic-cleanup-watcher.service" \
          "$HOME/.config/systemd/user/agentic-cleanup-watcher.timer"
    systemctl --user daemon-reload 2>/dev/null || true
    echo "  Removed systemd user timer."
fi

if crontab -l 2>/dev/null | grep -q AGENTIC_CLEANUP_WATCHER; then
    crontab -l 2>/dev/null | grep -v AGENTIC_CLEANUP_WATCHER | crontab -
    echo "  Removed cron job."
fi

for RC in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$RC" ] || continue
    CHANGED=false
    if grep -qF '# >>> agentic-cleanup autocontinue alias >>>' "$RC"; then
        sed -i '/# >>> agentic-cleanup autocontinue alias >>>/,/# <<< agentic-cleanup autocontinue alias <<</d' "$RC"
        CHANGED=true
    fi
    if grep -qF '# >>> agentic-cleanup aliases >>>' "$RC"; then
        sed -i '/# >>> agentic-cleanup aliases >>>/,/# <<< agentic-cleanup aliases <<</d' "$RC"
        CHANGED=true
    fi
    if [ "$CHANGED" = true ]; then
        sed -i '${/^$/d;}' "$RC"
        echo "  Removed agentic-cleanup aliases from $RC."
        echo "  Open a new shell to clear them from the current environment."
    fi
done

echo ""
echo "Removing $TARGET_DIR..."
rm -rf "$TARGET_DIR"

echo ""
echo "Uninstall complete."
echo ""
echo "Reminder: You may also want to remove per-repo configuration:"
echo "  - Remove SessionStart/SessionEnd hooks from .claude/settings.local.json"
echo "  - Remove the 'cleanup' entry from .mcp.json"
