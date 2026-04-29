#!/bin/bash
set -euo pipefail

TARGET_DIR="$HOME/.local/share/agentic-cleanup"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! command -v bun &>/dev/null; then
    echo "Error: Bun is required but not installed."
    echo "Install it with: curl -fsSL https://bun.sh/install | bash"
    exit 1
fi

if [ -f "$TARGET_DIR/data/timer.pid" ]; then
    PID=$(cat "$TARGET_DIR/data/timer.pid")
    if kill -0 "$PID" 2>/dev/null; then
        echo "Error: An active Claude session is using this installation (timer PID $PID)."
        echo "Please exit Claude Code first, then re-run install.sh."
        exit 1
    fi
fi

echo "Installing agentic-cleanup to $TARGET_DIR..."

if [ -d "$TARGET_DIR" ]; then
    echo "Removing previous installation..."
    rm -rf "$TARGET_DIR"
fi

mkdir -p "$TARGET_DIR"/{data,context}

for item in bin checks cleanup channel watchers systemd add-repo.py uninstall.sh README.md; do
    if [ -e "$SOURCE_DIR/$item" ]; then
        cp -r "$SOURCE_DIR/$item" "$TARGET_DIR/"
    fi
done

find "$TARGET_DIR" -name '*.sh' -exec chmod +x {} \;

echo "Installing channel server dependencies..."
cd "$TARGET_DIR/channel" && bun install --production 2>&1 | tail -1

echo ""
echo "Installing session-limit watcher scheduler..."

install_systemd_timer() {
    local unit_dir="$HOME/.config/systemd/user"
    mkdir -p "$unit_dir"
    sed "s|@TARGET_DIR@|$TARGET_DIR|g" "$TARGET_DIR/systemd/agentic-cleanup-watcher.service.in" \
        > "$unit_dir/agentic-cleanup-watcher.service"
    sed "s|@TARGET_DIR@|$TARGET_DIR|g" "$TARGET_DIR/systemd/agentic-cleanup-watcher.timer.in" \
        > "$unit_dir/agentic-cleanup-watcher.timer"
    systemctl --user daemon-reload
    systemctl --user enable --now agentic-cleanup-watcher.timer
    echo "  Installed systemd user timer (every 3 hours)."
}

install_cron_fallback() {
    local cron_line="0 */3 * * * bash $TARGET_DIR/bin/watcher-runner.sh   # AGENTIC_CLEANUP_WATCHER"
    ( crontab -l 2>/dev/null | grep -v AGENTIC_CLEANUP_WATCHER; echo "$cron_line" ) | crontab -
    echo "  Installed cron job (every 3 hours)."
}

if systemctl --user --version &>/dev/null && [ -n "${XDG_RUNTIME_DIR:-}" ]; then
    install_systemd_timer
else
    install_cron_fallback
fi

if ! command -v tmux &>/dev/null; then
    echo ""
    echo "Note: tmux is not installed. The session-limit watcher requires tmux."
    echo "Install with:  sudo apt install tmux       (Ubuntu/Debian)"
    echo "               sudo dnf install tmux       (Fedora/RHEL)"
    echo "               sudo pacman -S tmux         (Arch)"
    echo "               brew install tmux           (macOS)"
fi

AUTOCLEAN_ALIAS='alias claude-autoclean='"'"'claude --dangerously-skip-permissions --dangerously-load-development-channels server:cleanup'"'"''
AUTOCONTINUE_ALIAS='alias claude-autocontinue='"'"'tmux new-session -A -s claude-autocontinue "claude --dangerously-skip-permissions --dangerously-load-development-channels server:cleanup"'"'"''
SENTINEL_OPEN="# >>> agentic-cleanup aliases >>>"
SENTINEL_CLOSE="# <<< agentic-cleanup aliases <<<"

RC_FILE=""
if [[ "${SHELL:-}" == *zsh ]] && [ -f "$HOME/.zshrc" ]; then
    RC_FILE="$HOME/.zshrc"
elif [ -f "$HOME/.bashrc" ]; then
    RC_FILE="$HOME/.bashrc"
fi

if [ -n "$RC_FILE" ]; then
    # Remove old sentinel blocks (both old and new naming)
    sed -i '/# >>> agentic-cleanup autocontinue alias >>>/,/# <<< agentic-cleanup autocontinue alias <<</d' "$RC_FILE"
    sed -i '/# >>> agentic-cleanup aliases >>>/,/# <<< agentic-cleanup aliases <<</d' "$RC_FILE"
    sed -i '${/^$/d;}' "$RC_FILE"

    printf '\n%s\n%s\n%s\n%s\n' "$SENTINEL_OPEN" "$AUTOCLEAN_ALIAS" "$AUTOCONTINUE_ALIAS" "$SENTINEL_CLOSE" >> "$RC_FILE"
    echo ""
    echo "Added 'claude-autoclean' and 'claude-autocontinue' aliases to $RC_FILE."
    echo "Run \`source $RC_FILE\` (or open a new shell) to use them."
else
    echo ""
    echo "Could not detect shell rc file. Add these aliases manually:"
    echo "  $AUTOCLEAN_ALIAS"
    echo "  $AUTOCONTINUE_ALIAS"
fi

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "  1. cd into your project repo"
echo "  2. Run: python3 $TARGET_DIR/add-repo.py"
echo "  3. Start Claude with: claude-autocontinue (tmux) or claude --dangerously-load-development-channels server:cleanup"
