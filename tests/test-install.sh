#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
TARGET_DIR="$HOME/.local/share/agentic-cleanup"
PASS=0
FAIL=0

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

assert_dir_exists() {
    local desc="$1" path="$2"
    if [ -d "$path" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (dir not found: $path)"
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

assert_executable() {
    local desc="$1" path="$2"
    if [ -x "$path" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (not executable: $path)"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Install/Uninstall Tests ==="
echo ""

# Clean slate
rm -rf "$TARGET_DIR"

echo "Test: install.sh"
bash "$BASE_DIR/install.sh"
echo ""
assert_dir_exists "target directory created" "$TARGET_DIR"
assert_dir_exists "data directory created" "$TARGET_DIR/data"
assert_dir_exists "context directory created" "$TARGET_DIR/context"
assert_dir_exists "channel directory created" "$TARGET_DIR/channel"
assert_dir_exists "node_modules installed" "$TARGET_DIR/channel/node_modules"
assert_file_exists "session-start.sh copied" "$TARGET_DIR/bin/session-start.sh"
assert_file_exists "session-end.sh copied" "$TARGET_DIR/bin/session-end.sh"
assert_file_exists "tick.sh copied" "$TARGET_DIR/bin/tick.sh"
assert_file_exists "disk.sh copied" "$TARGET_DIR/checks/disk.sh"
assert_file_exists "ros2.sh copied" "$TARGET_DIR/checks/ros2.sh"
assert_file_exists "ros-cleanup.sh copied" "$TARGET_DIR/cleanup/ros-cleanup.sh"
assert_file_exists "cleanup-channel.ts copied" "$TARGET_DIR/channel/cleanup-channel.ts"
assert_file_exists "add-repo.py copied" "$TARGET_DIR/add-repo.py"
assert_executable "session-start.sh is executable" "$TARGET_DIR/bin/session-start.sh"
assert_executable "tick.sh is executable" "$TARGET_DIR/bin/tick.sh"
assert_executable "disk.sh is executable" "$TARGET_DIR/checks/disk.sh"

echo ""
echo "Test: install.sh is idempotent"
bash "$BASE_DIR/install.sh"
assert_dir_exists "target still exists after reinstall" "$TARGET_DIR"

echo ""
echo "Test: uninstall.sh"
bash "$BASE_DIR/uninstall.sh"
assert_eq "target directory removed" "false" "$([ -d "$TARGET_DIR" ] && echo true || echo false)"

echo ""
echo "Test: uninstall.sh is safe when already uninstalled"
bash "$BASE_DIR/uninstall.sh"
assert_eq "no error on double uninstall" "0" "$?"

# Reinstall for subsequent use
echo ""
echo "Reinstalling for further testing..."
bash "$BASE_DIR/install.sh" > /dev/null

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
