#!/bin/bash
set -euo pipefail

BASE_DIR="$HOME/.local/share/claude-cleanup"
DATA_DIR="$BASE_DIR/data"
CONTEXT_FILE="$BASE_DIR/context/ros2.md"
SAVED_PROCS="$DATA_DIR/ros2-processes"

CURRENT_PROCS=$(mktemp)
trap 'rm -f "$CURRENT_PROCS"' EXIT

ps aux | grep -E '[r]os2|[r]os_|[r]os\.humble' | awk '{print $2, $11, $12}' > "$CURRENT_PROCS" 2>/dev/null || true

if [ ! -s "$CURRENT_PROCS" ]; then
    : > "$CONTEXT_FILE"
    : > "$SAVED_PROCS"
    exit 0
fi

if [ ! -f "$SAVED_PROCS" ]; then
    cp "$CURRENT_PROCS" "$SAVED_PROCS"
    : > "$CONTEXT_FILE"
    exit 0
fi

STALE=""
while IFS= read -r line; do
    PID=$(echo "$line" | awk '{print $1}')
    if grep -q "^${PID} " "$CURRENT_PROCS" 2>/dev/null; then
        STALE="${STALE}  PID ${line}\n"
    fi
done < "$SAVED_PROCS"

if [ -n "$STALE" ]; then
    NODE_LIST=""
    if command -v ros2 &>/dev/null; then
        NODE_LIST=$(timeout 5 ros2 node list 2>/dev/null || echo "(ros2 node list timed out)")
    fi

    cat > "$CONTEXT_FILE" <<EOF
The following ROS2 processes have been running since the previous check and may be stale:
$(echo -e "$STALE")
${NODE_LIST:+Active ROS2 nodes:
$NODE_LIST
}
These processes have persisted across check intervals and are likely leftover from previous work.
Kill them with SIGINT unless they are clearly part of the current task (e.g., you just launched them).
Do NOT kill the ros2 daemon (ros2cli.daemon.daemonize).
Use: kill -SIGINT <pid>, then kill -9 <pid> if it persists.
EOF
else
    : > "$CONTEXT_FILE"
fi

cp "$CURRENT_PROCS" "$SAVED_PROCS"
