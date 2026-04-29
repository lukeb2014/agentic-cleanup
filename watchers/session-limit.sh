#!/bin/bash
set -uo pipefail

BASE_DIR="$HOME/.local/share/agentic-cleanup"
DATA_DIR="$BASE_DIR/data"
CONTEXT_DIR="$BASE_DIR/context"
TOKEN_FILE="$DATA_DIR/.token"
STATE_FILE="$DATA_DIR/session-limit-watcher.json"
LOG_FILE="$DATA_DIR/watcher.log"
CHANNEL_URL="http://127.0.0.1:8789?type=session_limit"

now() {
    if [ -n "${AGENTIC_NOW_OVERRIDE:-}" ]; then
        echo "$AGENTIC_NOW_OVERRIDE"
    else
        date +%s
    fi
}

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') session-limit: $1" >> "$LOG_FILE"
}

mkdir -p "$DATA_DIR" "$CONTEXT_DIR"

if ! command -v tmux &>/dev/null; then
    log "tmux required for auto-continue but not installed; skipping"
    exit 0
fi

if ! tmux list-sessions &>/dev/null; then
    log "no tmux server running; nothing to watch"
    exit 0
fi

find_claude_panes() {
    local pane_id pane_pid pane_cmd
    while read -r pane_id pane_pid pane_cmd; do
        if is_claude_pane "$pane_pid" 0; then
            echo "$pane_id"
        fi
    done < <(tmux list-panes -a -F '#{pane_id} #{pane_pid} #{pane_current_command}')
}

is_claude_pane() {
    local pid="$1" depth="$2"
    [ "$depth" -gt 4 ] && return 1

    local comm
    comm=$(ps -o comm= -p "$pid" 2>/dev/null) || return 1
    [ "$comm" = "claude" ] && return 0

    local child
    while read -r child; do
        is_claude_pane "$child" $((depth + 1)) && return 0
    done < <(pgrep -P "$pid" 2>/dev/null)

    return 1
}

parse_reset_time() {
    local captured="$1"
    local reset_time

    reset_time=$(echo "$captured" | grep -oiE '(5[- ]hour|session|usage)[[:space:]]+limit' | head -1)
    [ -z "$reset_time" ] && return 1

    local time_str ampm
    time_str=$(echo "$captured" | grep -oiE 'reset[s]?[[:space:]]+(at[[:space:]]+)?[0-9]{1,2}:[0-9]{2}([[:space:]]*(am|pm|AM|PM))?' | head -1)
    if [ -z "$time_str" ]; then
        time_str=$(echo "$captured" | grep -oiE 'in[[:space:]]+[0-9]+[[:space:]]*(hour|hr|minute|min)[s]?' | head -1)
        if [ -n "$time_str" ]; then
            local hours=0 minutes=0
            hours=$(echo "$time_str" | grep -oiE '[0-9]+[[:space:]]*(hour|hr)' | grep -oE '[0-9]+' || echo 0)
            minutes=$(echo "$time_str" | grep -oiE '[0-9]+[[:space:]]*(minute|min)' | grep -oE '[0-9]+' || echo 0)
            [ -z "$hours" ] && hours=0
            [ -z "$minutes" ] && minutes=0
            local current
            current=$(now)
            echo $((current + hours * 3600 + minutes * 60))
            return 0
        fi
        return 1
    fi

    local hhmm
    hhmm=$(echo "$time_str" | grep -oE '[0-9]{1,2}:[0-9]{2}')
    ampm=$(echo "$time_str" | grep -oiE '(am|pm)' | tr '[:upper:]' '[:lower:]')

    local hour minute
    hour=$(echo "$hhmm" | cut -d: -f1)
    minute=$(echo "$hhmm" | cut -d: -f2)
    hour=$((10#$hour))
    minute=$((10#$minute))

    if [ -n "$ampm" ]; then
        if [ "$ampm" = "pm" ] && [ "$hour" -ne 12 ]; then
            hour=$((hour + 12))
        elif [ "$ampm" = "am" ] && [ "$hour" -eq 12 ]; then
            hour=0
        fi
    fi

    local today_date reset_epoch current
    today_date=$(date '+%Y-%m-%d')
    reset_epoch=$(date -d "$today_date $hour:$minute:00" +%s 2>/dev/null) || return 1
    current=$(now)

    if [ "$reset_epoch" -le "$current" ]; then
        local diff=$((current - reset_epoch))
        if [ "$diff" -gt 21600 ]; then
            reset_epoch=$((reset_epoch + 86400))
        fi
    fi

    echo "$reset_epoch"
    return 0
}

read_state() {
    if [ ! -f "$STATE_FILE" ]; then
        echo '{}'
        return
    fi
    local content
    content=$(cat "$STATE_FILE" 2>/dev/null) || { echo '{}'; return; }
    if ! echo "$content" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        log "WARN: state file corrupted, resetting"
        echo '{}'
        return
    fi
    echo "$content"
}

write_state() {
    local state="$1"
    echo "$state" > "$STATE_FILE.tmp"
    mv -f "$STATE_FILE.tmp" "$STATE_FILE"
}

get_field() {
    local state="$1" pane="$2" field="$3"
    echo "$state" | python3 -c "
import sys, json
s = json.load(sys.stdin)
v = s.get('$pane', {}).get('$field')
print('' if v is None else v)
" 2>/dev/null
}

set_fields() {
    local state="$1" pane="$2"
    shift 2
    local py_assigns=""
    while [ $# -ge 2 ]; do
        local key="$1" val="$2"
        shift 2
        if [ "$val" = "null" ]; then
            py_assigns="$py_assigns
s.setdefault('$pane', {})['$key'] = None"
        else
            py_assigns="$py_assigns
s.setdefault('$pane', {})['$key'] = $val"
        fi
    done
    echo "$state" | python3 -c "
import sys, json
s = json.load(sys.stdin)
$py_assigns
print(json.dumps(s))
" 2>/dev/null
}

remove_pane() {
    local state="$1" pane="$2"
    echo "$state" | python3 -c "
import sys, json
s = json.load(sys.stdin)
s.pop('$pane', None)
print(json.dumps(s))
" 2>/dev/null
}

continue_protocol() {
    local pane_id="$1"
    local current
    current=$(now)

    tmux send-keys -t "$pane_id" Enter
    log "sent Enter to pane $pane_id"

    local token
    token=$(cat "$TOKEN_FILE" 2>/dev/null || echo "")
    if [ -z "$token" ]; then
        log "no token found, skipping channel POST for $pane_id"
    else
        local http_code
        http_code=$(curl -s -o /dev/null -w '%{http_code}' \
            -X POST "$CHANNEL_URL" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: text/plain" \
            --data-binary 'continue' \
            --connect-timeout 2 --max-time 5 2>/dev/null) || http_code="000"

        if [ "$http_code" = "200" ]; then
            log "channel POST succeeded for pane $pane_id"
        else
            log "WARN: channel POST returned HTTP $http_code for pane $pane_id"
        fi
    fi

    local time_str
    time_str=$(date -d "@$current" '+%H:%M' 2>/dev/null || date '+%H:%M')
    echo "Watcher resumed pane $pane_id at $time_str after a session-limit reset." > "$CONTEXT_DIR/session-limit.md"
}

CLAUDE_PANES=$(find_claude_panes)
STATE=$(read_state)
CURRENT=$(now)
FOUND_PANES=""

for pane_id in $CLAUDE_PANES; do
    FOUND_PANES="$FOUND_PANES $pane_id"

    CAPTURED=$(tmux capture-pane -p -t "$pane_id" -S -80 2>/dev/null) || continue

    RESET_EPOCH=$(parse_reset_time "$CAPTURED") || {
        STATE=$(remove_pane "$STATE" "$pane_id")
        continue
    }

    STORED_RESET=$(get_field "$STATE" "$pane_id" "reset_at")
    STORED_ATTEMPTED=$(get_field "$STATE" "$pane_id" "attempted_at")

    if [ -n "$STORED_RESET" ] && [ "$STORED_RESET" != "$RESET_EPOCH" ]; then
        log "new lockout detected on $pane_id (reset_at changed: $STORED_RESET -> $RESET_EPOCH)"
        STATE=$(set_fields "$STATE" "$pane_id" \
            "detected_at" "$CURRENT" \
            "reset_at" "$RESET_EPOCH" \
            "attempted_at" "null" \
            "lockout_id" "\"${CURRENT}-${pane_id}\"")
        STORED_ATTEMPTED=""
    elif [ -z "$STORED_RESET" ]; then
        log "lockout detected on $pane_id (reset_at=$RESET_EPOCH)"
        STATE=$(set_fields "$STATE" "$pane_id" \
            "detected_at" "$CURRENT" \
            "reset_at" "$RESET_EPOCH" \
            "attempted_at" "null" \
            "lockout_id" "\"${CURRENT}-${pane_id}\"")
        STORED_ATTEMPTED=""
    fi

    if [ "$RESET_EPOCH" -gt "$CURRENT" ]; then
        log "pane $pane_id pending reset ($(( (RESET_EPOCH - CURRENT) / 60 )) min remaining)"
        continue
    fi

    if [ -n "$STORED_ATTEMPTED" ]; then
        log "pane $pane_id already attempted, skipping"
        continue
    fi

    continue_protocol "$pane_id"
    STATE=$(set_fields "$STATE" "$pane_id" "attempted_at" "$CURRENT")
    log "continue protocol completed for pane $pane_id"
done

ALL_PANES=$(echo "$STATE" | python3 -c "
import sys, json
s = json.load(sys.stdin)
for k in s: print(k)
" 2>/dev/null)

for stored_pane in $ALL_PANES; do
    if ! echo "$FOUND_PANES" | grep -qw "$stored_pane"; then
        STATE=$(remove_pane "$STATE" "$stored_pane")
    fi
done

write_state "$STATE"
exit 0
