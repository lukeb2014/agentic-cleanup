#!/bin/bash
set +e

BASE_DIR="$HOME/.local/share/claude-cleanup"
DATA_DIR="$BASE_DIR/data"
CONTEXT_DIR="$BASE_DIR/context"
BIN_DIR="$BASE_DIR/bin"
TOKEN_FILE="$DATA_DIR/.token"
TIMER_PID_FILE="$DATA_DIR/timer.pid"
CHANNEL_URL="http://127.0.0.1:8789?type=session_end"

if [ -f "$TIMER_PID_FILE" ]; then
    TIMER_PID=$(cat "$TIMER_PID_FILE")
    pkill -P "$TIMER_PID" 2>/dev/null || true
    kill "$TIMER_PID" 2>/dev/null || true
    rm -f "$TIMER_PID_FILE"
fi

bash "$BIN_DIR/tick.sh" 2>/dev/null || true

for script in "$BASE_DIR/cleanup"/*.sh; do
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
    TOKEN=$(cat "$TOKEN_FILE" 2>/dev/null || echo "")
    if [ -n "$TOKEN" ]; then
        curl -s -o /dev/null \
            -X POST "$CHANNEL_URL" \
            -H "Authorization: Bearer $TOKEN" \
            -H "Content-Type: text/plain" \
            --data-binary "$CONTEXT" \
            --connect-timeout 2 --max-time 5 2>/dev/null || true
    fi
fi

exit 0
