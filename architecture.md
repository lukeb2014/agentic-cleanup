# Claude Automatic Cleanup

The purpose of this app is to prevent Claude Code from encountering common pitfalls with unbounded logging and complicated ros2 node management using Hooks and Channels.

## Online Documentation

[Hooks](https://code.claude.com/docs/en/hooks) are used to run scripts when specific events occur.
[Channels documentation](https://code.claude.com/docs/en/channels) are used to inject context into Claude while it is running.

## Architecture
The `session-start.sh` script runs a command to execute `tick.sh` every 30 minutes. `tick.sh` executes every script in `checks/`. These scripts perform cleanup and update corresponding markdown files in `context/`. Then, using a Claude Channel, all of the updated context is fed into the current Claude Code session. That way, Claude knows if old log files have been removed, or is given necessary reminders to clean up unused processes.
This is trigged by a Hook for `SessionStart`.

The `session-end.sh` script runs a command to execute `tick.sh` one last time AND all scripts in `cleanup/`. Thus, more context will be generated than just for `tick.sh`.
This is trigged by a Hook for `SessionEnd`.

So, Claude starts -> run `session-start.sh` -> Claude runs for 30 minutes -> `tick.sh` -> give Claude updated context (possibly empty) in a loop, User runs /exit -> `session-end.sh` -> give Claude final commands to clean up processes -> exit.

## Usage
Run `bash install.sh` to install this repository.
To enable usage of this in a specific repo, run `python ~/.local/share/claude-cleanup/add-repo.py` from said repo. 