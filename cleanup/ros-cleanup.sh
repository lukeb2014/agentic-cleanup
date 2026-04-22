#!/bin/bash
set -euo pipefail

BASE_DIR="$HOME/.local/share/claude-cleanup"
CONTEXT_FILE="$BASE_DIR/context/ros-cleanup.md"

PROCS=$(ps aux | grep -E '[r]os2|[r]os_|[r]os\.humble' | awk '{print "  PID " $2 " — " $11 " " $12}' 2>/dev/null || true)

if [ -z "$PROCS" ]; then
    : > "$CONTEXT_FILE"
    exit 0
fi

cat > "$CONTEXT_FILE" <<EOF
Session is ending. The following ROS2-related processes are still running:
${PROCS}

Kill any processes that you started or that are no longer needed:
1. First try: kill -SIGINT <pid>
2. If still running after a few seconds: kill -9 <pid>
3. Verify with: ps aux | grep -E 'ros2|ros_'
Do NOT kill the ros2 daemon (ros2cli.daemon) unless explicitly asked.
EOF
