#!/bin/bash
set -euo pipefail

BASE_DIR="$HOME/.local/share/agentic-cleanup"
DATA_DIR="$BASE_DIR/data"
CONTEXT_DIR="$BASE_DIR/context"
BIN_DIR="$BASE_DIR/bin"
TOKEN_FILE="$DATA_DIR/.token"
TIMER_PID_FILE="$DATA_DIR/timer.pid"
CHANNEL_URL="http://127.0.0.1:8789?type=session_start"

mkdir -p "$DATA_DIR" "$CONTEXT_DIR"

if [ -f "$TIMER_PID_FILE" ]; then
    OLD_PID=$(cat "$TIMER_PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        pkill -P "$OLD_PID" 2>/dev/null || true
        kill "$OLD_PID" 2>/dev/null || true
    fi
    rm -f "$TIMER_PID_FILE"
fi

TOKEN=$(head -c 48 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)
install -m 600 /dev/null "$TOKEN_FILE"
echo "$TOKEN" > "$TOKEN_FILE"

echo 0 > "$DATA_DIR/.curl-failures"
rm -f "$DATA_DIR/ros2-processes"

for script in "$BASE_DIR/checks"/*.sh; do
    [ -x "$script" ] || continue
    bash "$script" 2>/dev/null || true
done

CONTEXT=""
for f in "$CONTEXT_DIR"/*.md; do
    [ -f "$f" ] || continue
    CONTENT=$(cat "$f")
    [ -z "$CONTENT" ] && continue
    CONTEXT="${CONTEXT}${CONTENT}"$'\n\n'
done

if [ -n "$CONTEXT" ]; then
    curl -s -o /dev/null \
        -X POST "$CHANNEL_URL" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: text/plain" \
        --data-binary "$CONTEXT" \
        --max-time 10 2>/dev/null || true
fi

(
    while sleep 1800; do
        bash "$BIN_DIR/tick.sh"
    done
) </dev/null >/dev/null 2>&1 &
echo $! > "$TIMER_PID_FILE"

exit 0
