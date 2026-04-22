#!/bin/bash

# This script should do the following:
# 
# 1. Read the amount of disk space left on the file system
# 2. If it is more than 10 GB different from that saved in status.md, trigger a cleanup.
#    If not, it's not worth cleaning up, return.
# 3. Otherwise, determine whether it is a large file that needs to be removed or several
#    folders with large files
# 4. If it's a large file (e.g., a text file with > 10 GB), delete it
# 5. If there are, for instance, several folders each with 2 GB, eliminate the oldest folders
#    so that the total log size is < 10 GB.
# 6. Update context/ with whatever context should be sent to the current claude session
#    enumerating which logs were deleted, and why.
#    also include an instruction saying to avoid saving more than 10 GB of logs at a time
# Notes
# - logs are often saved in /tmp/claude-100/-home-user-current-project-path/claude-session-id/...

