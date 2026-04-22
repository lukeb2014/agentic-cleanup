#!/bin/bash

# systemd-run --user --on-active=30m --unit=claude-disk-$PID
# Ingest the hook input
# Extract the session_id
# Check out the current claude code session's PID

# Use that so that tick.sh is ran every 30 minutes.
# This script should die on a SIGTERM or SIGKILL etc. signal, if the claude window crashes
# or similar.

# Finally, the current amount of hard drive space available on the system
# should be saved in data/ so that it can be checked each time by tick.sh
