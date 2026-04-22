#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
PASS=0
FAIL=0

MOCK_DIR=$(mktemp -d)
trap 'rm -rf "$MOCK_DIR"' EXIT

mkdir -p "$MOCK_DIR/data" "$MOCK_DIR/context" "$MOCK_DIR/checks"

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

assert_file_not_empty() {
    local desc="$1" path="$2"
    if [ -s "$path" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (file empty or missing: $path)"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Check Script Tests ==="
echo ""

# --- disk.sh tests ---
echo "Test: disk.sh creates baseline on first run"
# We can't easily mock df, so we just verify it runs and creates the baseline
ORIG_HOME="$HOME"
export HOME="$MOCK_DIR"
mkdir -p "$MOCK_DIR/.local/share/claude-cleanup/data"
mkdir -p "$MOCK_DIR/.local/share/claude-cleanup/context"

bash "$BASE_DIR/checks/disk.sh" 2>/dev/null || true
assert_file_exists "disk baseline created" "$MOCK_DIR/.local/share/claude-cleanup/data/disk-baseline"

BASELINE=$(cat "$MOCK_DIR/.local/share/claude-cleanup/data/disk-baseline")
assert_eq "baseline is a number" "true" "$(echo "$BASELINE" | grep -qE '^[0-9]+$' && echo true || echo false)"

echo ""
echo "Test: disk.sh produces no context when delta < 10 GB"
bash "$BASE_DIR/checks/disk.sh" 2>/dev/null || true
DISK_CONTEXT=$(cat "$MOCK_DIR/.local/share/claude-cleanup/context/disk.md" 2>/dev/null || echo "")
assert_eq "no context when stable" "" "$DISK_CONTEXT"

echo ""

# --- ros2.sh tests ---
echo "Test: ros2.sh creates process file on first run"
bash "$BASE_DIR/checks/ros2.sh" 2>/dev/null || true
assert_file_exists "ros2 processes file created" "$MOCK_DIR/.local/share/claude-cleanup/data/ros2-processes"

echo ""
echo "Test: ros2.sh produces no context on second run if processes unchanged"
bash "$BASE_DIR/checks/ros2.sh" 2>/dev/null || true
ROS2_CONTEXT=$(cat "$MOCK_DIR/.local/share/claude-cleanup/context/ros2.md" 2>/dev/null || echo "")
# If there are actually stale ros2 processes, context will be non-empty — that's correct behavior
# If no ros2 processes, context should be empty
if ! ps aux | grep -qE '[r]os2|[r]os_'; then
    assert_eq "no context when no ros2 processes" "" "$ROS2_CONTEXT"
else
    echo "  SKIP: ROS2 processes are running, context may be non-empty (expected)"
fi

export HOME="$ORIG_HOME"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
