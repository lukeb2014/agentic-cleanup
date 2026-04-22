#!/bin/bash

# Loop through each script in checks/*. Execute each one.
# The following is some dummy code
if [ $((NOW - LAST)) -ge 1800 ]; then
  echo "$NOW" > "$STAMP"
  ( run_expensive_cleanup_and_log_results & ) >/dev/null 2>&1
fi
# Each script executed should update the corresponding file in the context folder
# with context that should be injected into the current claude session using
# claude channels.
exit 0