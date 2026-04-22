#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
CHANNEL_SCRIPT="$BASE_DIR/channel/cleanup-channel.ts"
DATA_DIR=$(mktemp -d)
TOKEN="test-token-abc123"
PORT=8789
PASS=0
FAIL=0

cleanup() {
    if [ -n "${SERVER_PID:-}" ]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    rm -rf "$DATA_DIR"
}
trap cleanup EXIT

echo "$TOKEN" > "$DATA_DIR/.token"
chmod 600 "$DATA_DIR/.token"

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected=$expected, got=$actual)"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Channel Server Tests ==="
echo ""

# Check if port is already in use
if curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$PORT --max-time 1 2>/dev/null | grep -q '200\|403\|405'; then
    echo "ERROR: Port $PORT is already in use. Cannot run tests."
    exit 1
fi

echo "Starting channel server..."
CLEANUP_DATA_DIR="$DATA_DIR" bun "$CHANNEL_SCRIPT" &>/dev/null &
SERVER_PID=$!
sleep 2

if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "ERROR: Channel server failed to start"
    exit 1
fi
echo "Server running (PID $SERVER_PID)"
echo ""

echo "Test: POST with valid token"
CODE=$(curl -s -o /dev/null -w '%{http_code}' \
    -X POST "http://127.0.0.1:$PORT?type=test" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: text/plain" \
    -d "test context message" \
    --max-time 5 2>/dev/null)
assert_eq "valid token returns 200" "200" "$CODE"

echo "Test: POST without token"
CODE=$(curl -s -o /dev/null -w '%{http_code}' \
    -X POST "http://127.0.0.1:$PORT" \
    -H "Content-Type: text/plain" \
    -d "unauthorized message" \
    --max-time 5 2>/dev/null)
assert_eq "missing token returns 403" "403" "$CODE"

echo "Test: POST with wrong token"
CODE=$(curl -s -o /dev/null -w '%{http_code}' \
    -X POST "http://127.0.0.1:$PORT" \
    -H "Authorization: Bearer wrong-token" \
    -H "Content-Type: text/plain" \
    -d "unauthorized message" \
    --max-time 5 2>/dev/null)
assert_eq "wrong token returns 403" "403" "$CODE"

echo "Test: GET request rejected"
CODE=$(curl -s -o /dev/null -w '%{http_code}' \
    "http://127.0.0.1:$PORT" \
    --max-time 5 2>/dev/null)
assert_eq "GET returns 405" "405" "$CODE"

echo "Test: empty body rejected"
CODE=$(curl -s -o /dev/null -w '%{http_code}' \
    -X POST "http://127.0.0.1:$PORT" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: text/plain" \
    -d "" \
    --max-time 5 2>/dev/null)
assert_eq "empty body returns 400" "400" "$CODE"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
