#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
PASS=0
FAIL=0

MOCK_DIR=$(mktemp -d)
MOCK_BIN="$MOCK_DIR/bin"
trap 'rm -rf "$MOCK_DIR"' EXIT

mkdir -p "$MOCK_BIN"
mkdir -p "$MOCK_DIR/home/.local/share/agentic-cleanup"/{data,context,watchers}

cp "$BASE_DIR/watchers/session-limit.sh" \
   "$MOCK_DIR/home/.local/share/agentic-cleanup/watchers/"
chmod +x "$MOCK_DIR/home/.local/share/agentic-cleanup/watchers/session-limit.sh"

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected='$expected', got='$actual')"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected to contain '$needle')"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if ! echo "$haystack" | grep -qF "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (should not contain '$needle')"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_exists() {
    local desc="$1" path="$2"
    if [ -f "$path" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (file not found: $path)"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_missing() {
    local desc="$1" path="$2"
    if [ ! -f "$path" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (file should not exist: $path)"
        FAIL=$((FAIL + 1))
    fi
}

count_lines() {
    local file="$1"
    if [ -f "$file" ]; then
        wc -l < "$file"
    else
        echo 0
    fi
}

DATA_DIR="$MOCK_DIR/home/.local/share/agentic-cleanup/data"
CONTEXT_DIR="$MOCK_DIR/home/.local/share/agentic-cleanup/context"
STATE_FILE="$DATA_DIR/session-limit-watcher.json"
SENDKEYS_LOG="$MOCK_DIR/sendkeys.log"
CURL_LOG="$MOCK_DIR/curl.log"

MOCK_TMUX_BEHAVIOR="no_server"
MOCK_PANE_OUTPUT=""
MOCK_CURL_HTTP="200"

setup_tmux_shim() {
    cat > "$MOCK_BIN/tmux" << 'SHIMEOF'
#!/bin/bash
MOCK_DIR="$(dirname "$(dirname "$0")")"
BEHAVIOR=$(cat "$MOCK_DIR/tmux_behavior" 2>/dev/null || echo "no_server")

case "$1" in
    list-sessions)
        if [ "$BEHAVIOR" = "no_server" ]; then
            exit 1
        fi
        echo "claude-autocontinue: 1 windows"
        ;;
    list-panes)
        if [ "$BEHAVIOR" = "no_panes" ]; then
            exit 0
        elif [ "$BEHAVIOR" = "one_claude_pane" ] || [ "$BEHAVIOR" = "two_claude_panes" ]; then
            echo "%1 1000 bash"
            if [ "$BEHAVIOR" = "two_claude_panes" ]; then
                echo "%2 2000 bash"
            fi
        fi
        ;;
    capture-pane)
        pane_id=""
        while [ $# -gt 0 ]; do
            case "$1" in
                -t) pane_id="$2"; shift 2 ;;
                *) shift ;;
            esac
        done
        if [ -f "$MOCK_DIR/pane_output_${pane_id}" ]; then
            cat "$MOCK_DIR/pane_output_${pane_id}"
        elif [ -f "$MOCK_DIR/pane_output" ]; then
            cat "$MOCK_DIR/pane_output"
        fi
        ;;
    send-keys)
        pane_id="" key=""
        while [ $# -gt 0 ]; do
            case "$1" in
                -t) pane_id="$2"; shift 2 ;;
                send-keys) shift ;;
                *) key="$1"; shift ;;
            esac
        done
        echo "send-keys $pane_id $key" >> "$MOCK_DIR/sendkeys.log"
        ;;
esac
SHIMEOF
    chmod +x "$MOCK_BIN/tmux"
}

setup_curl_shim() {
    cat > "$MOCK_BIN/curl" << 'SHIMEOF'
#!/bin/bash
MOCK_DIR="$(dirname "$(dirname "$0")")"
HTTP=$(cat "$MOCK_DIR/curl_http" 2>/dev/null || echo "200")

url="" body="" auth=""
while [ $# -gt 0 ]; do
    case "$1" in
        -X) shift 2 ;;
        -H) auth="$2"; shift 2 ;;
        --data-binary) body="$2"; shift 2 ;;
        -s) shift ;;
        -o|-w) shift 2 ;;
        --connect-timeout|--max-time) shift 2 ;;
        http*) url="$1"; shift ;;
        *) shift ;;
    esac
done

echo "POST $url body=$body" >> "$MOCK_DIR/curl.log"
echo -n "$HTTP"
SHIMEOF
    chmod +x "$MOCK_BIN/curl"
}

setup_ps_shim() {
    cat > "$MOCK_BIN/ps" << 'SHIMEOF'
#!/bin/bash
MOCK_DIR="$(dirname "$(dirname "$0")")"
while [ $# -gt 0 ]; do
    case "$1" in
        -o) shift 2 ;;
        -p)
            pid="$2"
            if [ "$pid" = "1001" ] || [ "$pid" = "2001" ]; then
                echo "claude"
            else
                echo "bash"
            fi
            exit 0
            ;;
        *) shift ;;
    esac
done
echo "bash"
SHIMEOF
    chmod +x "$MOCK_BIN/ps"
}

setup_pgrep_shim() {
    cat > "$MOCK_BIN/pgrep" << 'SHIMEOF'
#!/bin/bash
MOCK_DIR="$(dirname "$(dirname "$0")")"
while [ $# -gt 0 ]; do
    case "$1" in
        -P)
            ppid="$2"
            if [ "$ppid" = "1000" ]; then
                echo "1001"
            elif [ "$ppid" = "2000" ]; then
                echo "2001"
            fi
            exit 0
            ;;
        *) shift ;;
    esac
done
exit 1
SHIMEOF
    chmod +x "$MOCK_BIN/pgrep"
}

reset_test() {
    rm -f "$SENDKEYS_LOG" "$CURL_LOG" "$STATE_FILE"
    rm -f "$DATA_DIR/watcher.log"
    rm -f "$CONTEXT_DIR/session-limit.md"
    rm -f "$MOCK_DIR/tmux_behavior" "$MOCK_DIR/pane_output" "$MOCK_DIR/pane_output_%1" "$MOCK_DIR/pane_output_%2" "$MOCK_DIR/curl_http"
    echo '{}' > "$STATE_FILE"
}

run_watcher() {
    HOME="$MOCK_DIR/home" \
    PATH="$MOCK_BIN:$PATH" \
    AGENTIC_NOW_OVERRIDE="${MOCK_NOW:-}" \
    bash "$MOCK_DIR/home/.local/share/agentic-cleanup/watchers/session-limit.sh" 2>/dev/null
    return $?
}

setup_tmux_shim
setup_curl_shim
setup_ps_shim
setup_pgrep_shim

echo "=== Session-Limit Watcher Tests ==="
echo ""

# Test 1: No tmux on PATH
echo "Test 1: No tmux on PATH exits 0, state untouched"
reset_test
echo '{}' > "$STATE_FILE"
HOME="$MOCK_DIR/home" PATH="/usr/bin:/bin" AGENTIC_NOW_OVERRIDE="1700000000" \
    bash "$MOCK_DIR/home/.local/share/agentic-cleanup/watchers/session-limit.sh" 2>/dev/null
EXIT_CODE=$?
assert_eq "exits 0" "0" "$EXIT_CODE"
STATE_CONTENT=$(cat "$STATE_FILE")
assert_eq "state unchanged" "{}" "$STATE_CONTENT"

echo ""

# Test 2: tmux server up, no Claude panes
echo "Test 2: No Claude panes, state file empty"
reset_test
echo "no_panes" > "$MOCK_DIR/tmux_behavior"
MOCK_NOW=1700000000 run_watcher
STATE_CONTENT=$(cat "$STATE_FILE")
assert_eq "state is empty object" "{}" "$STATE_CONTENT"

echo ""

# Test 3: Claude pane, no banner
echo "Test 3: Claude pane present but no limit banner"
reset_test
echo "one_claude_pane" > "$MOCK_DIR/tmux_behavior"
echo '{"%1": {"detected_at": 1699999000, "reset_at": 1700000000, "attempted_at": null, "lockout_id": "test"}}' > "$STATE_FILE"
printf "Claude Code\n> working on something...\n" > "$MOCK_DIR/pane_output"
MOCK_NOW=1700000000 run_watcher
STATE_CONTENT=$(cat "$STATE_FILE")
assert_not_contains "pane entry removed" '"%1"' "$STATE_CONTENT"

echo ""

# Test 4: Banner detected, reset in future
echo "Test 4: Banner detected, reset in future"
reset_test
echo "one_claude_pane" > "$MOCK_DIR/tmux_behavior"
printf "You have hit your 5-hour usage limit. Your limit resets at 3:00 PM.\nPlease wait...\n" > "$MOCK_DIR/pane_output"
echo "200" > "$MOCK_DIR/curl_http"

RESET_HOUR_EPOCH=$(date -d "$(date '+%Y-%m-%d') 15:00:00" +%s 2>/dev/null || echo "1700010000")
MOCK_NOW=$((RESET_HOUR_EPOCH - 3600))
MOCK_NOW=$MOCK_NOW run_watcher

SENDKEYS_COUNT=$(count_lines "$SENDKEYS_LOG")
CURL_COUNT=$(count_lines "$CURL_LOG")
assert_eq "no send-keys" "0" "$SENDKEYS_COUNT"
assert_eq "no curl" "0" "$CURL_COUNT"
assert_file_exists "state file written" "$STATE_FILE"

echo ""

# Test 5: Banner detected, reset passed
echo "Test 5: Banner detected, reset has passed"
reset_test
echo "one_claude_pane" > "$MOCK_DIR/tmux_behavior"
printf "You have hit your 5-hour usage limit. Your limit resets at 3:00 PM.\nPlease wait...\n" > "$MOCK_DIR/pane_output"
echo "200" > "$MOCK_DIR/curl_http"
echo "test-token" > "$DATA_DIR/.token"

RESET_HOUR_EPOCH=$(date -d "$(date '+%Y-%m-%d') 15:00:00" +%s 2>/dev/null || echo "1700010000")
MOCK_NOW=$((RESET_HOUR_EPOCH + 60))
MOCK_NOW=$MOCK_NOW run_watcher

SENDKEYS_CONTENT=$(cat "$SENDKEYS_LOG" 2>/dev/null || echo "")
CURL_CONTENT=$(cat "$CURL_LOG" 2>/dev/null || echo "")
assert_contains "send-keys fired" "Enter" "$SENDKEYS_CONTENT"
assert_contains "curl POST fired" "continue" "$CURL_CONTENT"

STATE_CONTENT=$(cat "$STATE_FILE")
assert_contains "attempted_at is set" "attempted_at" "$STATE_CONTENT"
assert_not_contains "attempted_at is not null" '"attempted_at": null' "$STATE_CONTENT"

echo ""

# Test 6: Re-run after attempt (idempotent)
echo "Test 6: Re-run after attempt is no-op"
rm -f "$SENDKEYS_LOG" "$CURL_LOG"

MOCK_NOW=$((RESET_HOUR_EPOCH + 120))
MOCK_NOW=$MOCK_NOW run_watcher

SENDKEYS_COUNT=$(count_lines "$SENDKEYS_LOG")
CURL_COUNT=$(count_lines "$CURL_LOG")
assert_eq "no additional send-keys" "0" "$SENDKEYS_COUNT"
assert_eq "no additional curl" "0" "$CURL_COUNT"

echo ""

# Test 7: New lockout (different reset_at) fires again
echo "Test 7: New lockout with different reset_at fires again"
reset_test
echo "one_claude_pane" > "$MOCK_DIR/tmux_behavior"
echo "200" > "$MOCK_DIR/curl_http"
echo "test-token" > "$DATA_DIR/.token"

FIRST_RESET=$(date -d "$(date '+%Y-%m-%d') 12:00:00" +%s 2>/dev/null || echo "1700000000")
MOCK_NOW=$((FIRST_RESET + 60))
printf "You have hit your 5-hour usage limit. Your limit resets at 12:00 PM.\nPlease wait...\n" > "$MOCK_DIR/pane_output"
MOCK_NOW=$MOCK_NOW run_watcher
rm -f "$SENDKEYS_LOG" "$CURL_LOG"

SECOND_RESET=$(date -d "$(date '+%Y-%m-%d') 17:00:00" +%s 2>/dev/null || echo "1700018000")
MOCK_NOW=$((SECOND_RESET + 60))
printf "You have hit your 5-hour usage limit. Your limit resets at 5:00 PM.\nPlease wait...\n" > "$MOCK_DIR/pane_output"
MOCK_NOW=$MOCK_NOW run_watcher

SENDKEYS_CONTENT=$(cat "$SENDKEYS_LOG" 2>/dev/null || echo "")
CURL_CONTENT=$(cat "$CURL_LOG" 2>/dev/null || echo "")
assert_contains "send-keys fired for new lockout" "Enter" "$SENDKEYS_CONTENT"
assert_contains "curl POST fired for new lockout" "continue" "$CURL_CONTENT"

echo ""

# Test 8: Reset passed but token missing
echo "Test 8: Reset passed, token missing"
reset_test
echo "one_claude_pane" > "$MOCK_DIR/tmux_behavior"
rm -f "$DATA_DIR/.token"

RESET_EPOCH=$(date -d "$(date '+%Y-%m-%d') 14:00:00" +%s 2>/dev/null || echo "1700010000")
MOCK_NOW=$((RESET_EPOCH + 60))
printf "You have hit your 5-hour usage limit. Your limit resets at 2:00 PM.\nPlease wait...\n" > "$MOCK_DIR/pane_output"
MOCK_NOW=$MOCK_NOW run_watcher

SENDKEYS_CONTENT=$(cat "$SENDKEYS_LOG" 2>/dev/null || echo "")
CURL_COUNT=$(count_lines "$CURL_LOG")
assert_contains "send-keys still fires" "Enter" "$SENDKEYS_CONTENT"
assert_eq "no curl (no token)" "0" "$CURL_COUNT"

STATE_CONTENT=$(cat "$STATE_FILE")
assert_not_contains "attempted_at set despite no token" '"attempted_at": null' "$STATE_CONTENT"

echo ""

# Test 9: Channel returns 500
echo "Test 9: Channel returns 500"
reset_test
echo "one_claude_pane" > "$MOCK_DIR/tmux_behavior"
echo "500" > "$MOCK_DIR/curl_http"
echo "test-token" > "$DATA_DIR/.token"

RESET_EPOCH=$(date -d "$(date '+%Y-%m-%d') 14:00:00" +%s 2>/dev/null || echo "1700010000")
MOCK_NOW=$((RESET_EPOCH + 60))
printf "You have hit your 5-hour usage limit. Your limit resets at 2:00 PM.\nPlease wait...\n" > "$MOCK_DIR/pane_output"
MOCK_NOW=$MOCK_NOW run_watcher

SENDKEYS_CONTENT=$(cat "$SENDKEYS_LOG" 2>/dev/null || echo "")
CURL_CONTENT=$(cat "$CURL_LOG" 2>/dev/null || echo "")
assert_contains "send-keys fires" "Enter" "$SENDKEYS_CONTENT"
assert_contains "curl was attempted" "continue" "$CURL_CONTENT"

STATE_CONTENT=$(cat "$STATE_FILE")
assert_not_contains "attempted_at set despite 500" '"attempted_at": null' "$STATE_CONTENT"

LOG_CONTENT=$(cat "$DATA_DIR/watcher.log" 2>/dev/null || echo "")
assert_contains "warning logged" "WARN" "$LOG_CONTENT"

echo ""

# Test 10: Two Claude panes both locked
echo "Test 10: Two Claude panes both locked"
reset_test
echo "two_claude_panes" > "$MOCK_DIR/tmux_behavior"
echo "200" > "$MOCK_DIR/curl_http"
echo "test-token" > "$DATA_DIR/.token"

RESET_EPOCH=$(date -d "$(date '+%Y-%m-%d') 14:00:00" +%s 2>/dev/null || echo "1700010000")
MOCK_NOW=$((RESET_EPOCH + 60))
printf "You have hit your 5-hour usage limit. Your limit resets at 2:00 PM.\nPlease wait...\n" > "$MOCK_DIR/pane_output"
MOCK_NOW=$MOCK_NOW run_watcher

SENDKEYS_CONTENT=$(cat "$SENDKEYS_LOG" 2>/dev/null || echo "")
SENDKEYS_COUNT=$(count_lines "$SENDKEYS_LOG")
CURL_COUNT=$(count_lines "$CURL_LOG")
assert_eq "two send-keys calls" "2" "$SENDKEYS_COUNT"
assert_eq "two curl calls" "2" "$CURL_COUNT"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
