#!/bin/bash

# This script should simply update context/ros2.md with instructions for claude
# to double-check that there aren't any old ros2 nodes or processes that are not
# currently being used. It is generating a reminder
# Run ps aux | grep <something> so that claude has some ideas of what to look for.
# Claude should be told in particular to look at ros nodes that are "old" / have been running
# since the last session (are present in the data folder)

# Finally, all current ros2 nodes' names / PIDs / some identifying information should be saved to the data folder, so that they can be checked against
# the next time this script runs.