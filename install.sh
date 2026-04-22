#!/bin/bash
set -euo pipefail

TARGET_DIR="$HOME/.local/share/claude-cleanup"
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

echo "Installing claude-cleanup to $TARGET_DIR..."

if [ -d "$TARGET_DIR" ]; then
    echo "Removing previous installation..."
    rm -rf "$TARGET_DIR"
fi

mkdir -p "$TARGET_DIR"/{data,context}

for item in bin checks cleanup channel add-repo.py uninstall.sh README.md; do
    if [ -e "$SOURCE_DIR/$item" ]; then
        cp -r "$SOURCE_DIR/$item" "$TARGET_DIR/"
    fi
done

find "$TARGET_DIR" -name '*.sh' -exec chmod +x {} \;

echo "Installing channel server dependencies..."
cd "$TARGET_DIR/channel" && bun install --production 2>&1 | tail -1

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "  1. cd into your project repo"
echo "  2. Run: python3 $TARGET_DIR/add-repo.py"
echo "  3. Start Claude with: claude --dangerously-load-development-channels server:cleanup"
