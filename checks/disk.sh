#!/bin/bash
set -euo pipefail

BASE_DIR="$HOME/.local/share/agentic-cleanup"
DATA_DIR="$BASE_DIR/data"
CONTEXT_FILE="$BASE_DIR/context/disk.md"
BASELINE_FILE="$DATA_DIR/disk-baseline"
LOG_DIR="/tmp/claude-$(id -u)"
MAX_LOG_SIZE_GB=10

get_avail_gb() {
    df --output=avail / | tail -1 | awk '{printf "%.0f", $1 / 1048576}'
}

CURRENT_GB=$(get_avail_gb)

if [ ! -f "$BASELINE_FILE" ]; then
    echo "$CURRENT_GB" > "$BASELINE_FILE"
    : > "$CONTEXT_FILE"
    exit 0
fi

BASELINE_GB=$(tr -d '[:space:]' < "$BASELINE_FILE")
DELTA=$((BASELINE_GB - CURRENT_GB))

if [ "$DELTA" -lt 10 ]; then
    : > "$CONTEXT_FILE"
    echo "$CURRENT_GB" > "$BASELINE_FILE"
    exit 0
fi

DELETED_FILES=""
TOTAL_RECLAIMED=0

if [ -d "$LOG_DIR" ]; then
    while IFS= read -r file; do
        SIZE_BYTES=$(stat -c%s "$file" 2>/dev/null || echo 0)
        SIZE_GB=$((SIZE_BYTES / 1073741824))
        if [ "$SIZE_GB" -ge 10 ]; then
            rm -f "$file"
            DELETED_FILES="${DELETED_FILES}- Removed ${file} (${SIZE_GB} GB)\n"
            TOTAL_RECLAIMED=$((TOTAL_RECLAIMED + SIZE_GB))
        fi
    done < <(find "$LOG_DIR" -type f -size +10G 2>/dev/null)

    REMAINING_SIZE=$(du -sb "$LOG_DIR" 2>/dev/null | awk '{print $1}' || echo 0)
    REMAINING_GB=$((REMAINING_SIZE / 1073741824))

    if [ "$REMAINING_GB" -gt "$MAX_LOG_SIZE_GB" ]; then
        while IFS= read -r dir; do
            DIR_SIZE=$(du -sb "$dir" 2>/dev/null | awk '{print $1}' || echo 0)
            DIR_SIZE_GB=$((DIR_SIZE / 1073741824))
            rm -rf "$dir"
            DELETED_FILES="${DELETED_FILES}- Removed directory ${dir} (${DIR_SIZE_GB} GB)\n"
            TOTAL_RECLAIMED=$((TOTAL_RECLAIMED + DIR_SIZE_GB))

            REMAINING_SIZE=$(du -sb "$LOG_DIR" 2>/dev/null | awk '{print $1}' || echo 0)
            REMAINING_GB=$((REMAINING_SIZE / 1073741824))
            if [ "$REMAINING_GB" -le "$MAX_LOG_SIZE_GB" ]; then
                break
            fi
        done < <(find "$LOG_DIR" -mindepth 2 -maxdepth 2 -type d -printf '%T@ %p\n' 2>/dev/null | sort -n | awk '{print $2}')
    fi
fi

if [ -n "$DELETED_FILES" ]; then
    cat > "$CONTEXT_FILE" <<EOF
Disk usage alert: available space dropped by ${DELTA} GB since session start.
Automatic cleanup reclaimed approximately ${TOTAL_RECLAIMED} GB from ${LOG_DIR}.

Actions taken:
$(echo -e "$DELETED_FILES")
Current available disk space: $(get_avail_gb) GB.
Avoid saving more than ${MAX_LOG_SIZE_GB} GB of logs at a time.
EOF
else
    cat > "$CONTEXT_FILE" <<EOF
Disk usage alert: available space dropped by ${DELTA} GB since session start.
No large log files found in ${LOG_DIR} to clean automatically.
Current available disk space: ${CURRENT_GB} GB.
Check for large files elsewhere if disk pressure continues.
EOF
fi

echo "$CURRENT_GB" > "$BASELINE_FILE"
