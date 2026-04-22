#!/bin/bash
set -euo pipefail

BASE_DIR="$HOME/.local/share/agentic-cleanup"
DATA_DIR="$BASE_DIR/data"
CONTEXT_DIR="$BASE_DIR/context"
CHECKS_DIR="$BASE_DIR/checks"
TOKEN_FILE="$DATA_DIR/.token"
FAIL_FILE="$DATA_DIR/.curl-failures"
LOG_FILE="$DATA_DIR/tick.log"
CHANNEL_URL="http://127.0.0.1:8789?type=tick"
MAX_FAILURES=3

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

mkdir -p "$DATA_DIR" "$CONTEXT_DIR"

for script in "$CHECKS_DIR"/*.sh; do
    [ -x "$script" ] || continue
    bash "$script" 2>>"$LOG_FILE" || log "WARN: $(basename "$script") exited with $?"
done

CONTEXT=""
for f in "$CONTEXT_DIR"/*.md; do
    [ -f "$f" ] || continue
    CONTENT=$(cat "$f")
    [ -z "$CONTENT" ] && continue
    CONTEXT="${CONTEXT}${CONTENT}"$'\n\n'
done

if [ -z "$CONTEXT" ]; then
    echo 0 > "$FAIL_FILE" 2>/dev/null || true
    exit 0
fi

TOKEN=$(cat "$TOKEN_FILE" 2>/dev/null || echo "")
if [ -z "$TOKEN" ]; then
    log "WARN: no auth token found"
    exit 0
fi

HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
    -X POST "$CHANNEL_URL" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: text/plain" \
    --data-binary "$CONTEXT" \
    --max-time 10 2>/dev/null) || HTTP_CODE="000"

if [ "$HTTP_CODE" = "200" ]; then
    echo 0 > "$FAIL_FILE"
    log "OK: context pushed (${#CONTEXT} bytes)"
else
    FAILURES=$(cat "$FAIL_FILE" 2>/dev/null || echo 0)
    FAILURES=$((FAILURES + 1))
    echo "$FAILURES" > "$FAIL_FILE"
    log "ERROR: channel returned HTTP $HTTP_CODE (failure $FAILURES/$MAX_FAILURES)"

    if [ "$FAILURES" -ge "$MAX_FAILURES" ]; then
        log "FATAL: $MAX_FAILURES consecutive failures — channel server likely dead. Stopping timer."
        TIMER_PID_FILE="$DATA_DIR/timer.pid"
        if [ -f "$TIMER_PID_FILE" ]; then
            TIMER_PID=$(cat "$TIMER_PID_FILE")
            pkill -P "$TIMER_PID" 2>/dev/null || true
            kill "$TIMER_PID" 2>/dev/null || true
            rm -f "$TIMER_PID_FILE"
        fi
    fi
fi
