# Agentic Cleanup

Prevents Claude Code from accumulating unbounded logs in `/tmp/claude-*` and
leaving stale ROS2 processes running between sessions. Automatically resumes
Claude after 5-hour usage-limit lockouts.

Uses Claude Code's Hooks (SessionStart/SessionEnd) and the experimental
Channels feature to push diagnostic context directly into the active Claude
session. Claude sees the alerts and can act on them without user intervention.

## Prerequisites

- **Bun** -- install with `curl -fsSL https://bun.sh/install | bash`
- **Claude Code v2.1.80+**
- **Channels enabled** -- Team and Enterprise users must have an admin enable
  channels at **claude.ai > Admin settings > Claude Code > Channels**, or set
  `channelsEnabled: true` in managed settings. Pro and Max users without an
  organization skip this step.
- **tmux** *(optional)* -- required for the session-limit watcher to
  auto-continue after 5-hour lockouts. Everything else works without it.

  ```
  sudo apt install tmux       # Debian / Ubuntu
  sudo dnf install tmux       # Fedora / RHEL
  sudo pacman -S tmux         # Arch / Manjaro
  brew install tmux           # macOS (Homebrew)
  ```

## Installation

Clone this repo and run the installer:

```bash
cd ai-log-management
bash install.sh
```

This installs to `~/.local/share/agentic-cleanup/`, creates the `data/` and
`context/` directories, runs `bun install` for the channel server
dependencies, installs a systemd user timer (or cron fallback) for the
session-limit watcher, and adds two shell aliases to `~/.bashrc` (or
`~/.zshrc`).

The installer will refuse to run if an active Claude session is using the
current installation (checks `data/timer.pid`).

## Per-repo setup

From the root of any project you want cleanup enabled in:

```bash
python3 ~/.local/share/agentic-cleanup/add-repo.py
```

This creates or updates two files in the target repo:

- `.claude/settings.local.json` -- adds SessionStart and SessionEnd hooks
  pointing to the cleanup scripts
- `.mcp.json` -- adds the `cleanup` MCP server entry pointing to the
  channel TypeScript file

Run this once per repo. The generated config points to the installed copy
at `~/.local/share/agentic-cleanup/`.

## Usage

The installer adds two aliases. After install, run `source ~/.bashrc` (or
open a new shell) to pick them up.

**`claude-autocontinue`** -- launches Claude inside a tmux session. The
session-limit watcher can detect lockouts and auto-continue. Use this if
you have tmux installed and want fully unattended operation:

```bash
claude-autocontinue
```

**`claude-autoclean`** -- launches Claude directly, without tmux. You get
all the checks, cleanup, and channel features, but the watcher can't
auto-continue after a 5-hour lockout (it has no way to read or send
keystrokes to a bare terminal):

```bash
claude-autoclean
```

Both aliases pass `--dangerously-skip-permissions` and
`--dangerously-load-development-channels server:cleanup`.

Once running, the system operates automatically:

1. SessionStart fires, runs initial checks, pushes context into the session.
2. Every 30 minutes, `tick.sh` re-runs checks and pushes updated context.
3. SessionEnd fires, runs final checks, pushes ROS2 cleanup instructions.
4. Every 3 hours (independent of the session), the watcher checks for
   5-hour lockouts and auto-continues if the reset time has passed.

## Architecture

```
claude --dangerously-load-development-channels server:cleanup
  |
  +-- MCP spawns channel server (Bun, localhost:8789)
  |
  +-- SessionStart hook --> session-start.sh
  |     +-- Runs all checks/ scripts immediately
  |     +-- POSTs initial context to channel --> pushed into Claude
  |     +-- Starts background timer (sleep 1800 loop)
  |     +-- Saves timer PID to data/timer.pid
  |
  +-- Every 30 min --> tick.sh
  |     +-- Runs all checks/ scripts
  |     +-- Concatenates updated context/ files
  |     +-- POSTs to channel --> pushed into Claude
  |     +-- Self-terminates after 3 consecutive failures
  |
  +-- SessionEnd hook --> session-end.sh
  |     +-- Kills background timer
  |     +-- Runs tick.sh one final time
  |     +-- Runs all cleanup/ scripts (ROS2 shutdown instructions)
  |     +-- POSTs final cleanup context to channel
  |
  +-- Every 3 hours (systemd timer, independent of session)
        +-- bin/watcher-runner.sh --> watchers/session-limit.sh
              +-- Scans tmux panes for Claude's 5-hour limit banner
              +-- After reset time passes: sends Enter, POSTs "continue"
```

The channel server is a one-way MCP server. Shell scripts detect problems,
write context files, and POST them to the channel's HTTP endpoint. The channel
forwards the content as a notification into the Claude session.

## What it checks

### Disk usage (`checks/disk.sh`)

Monitors available disk space on `/` against a per-session baseline. If
available space drops by more than 10 GB:

- Scans `/tmp/claude-<uid>/` for files larger than 10 GB and deletes them
- If the directory still exceeds 10 GB total, removes oldest subdirectories
  until it fits
- Writes a summary of actions taken to the context

### ROS2 process staleness (`checks/ros2.sh`)

Detects ROS2 processes (`ros2`, `ros_`, `ros.humble` patterns) that have
persisted across consecutive checks:

- Compares the current process list against the saved list from the previous
  check
- If any PIDs appear in both, flags them as potentially stale
- Queries `ros2 node list` for additional context when available
- Writes recommendations to kill stale processes with SIGINT, then SIGKILL

### Session-end ROS2 cleanup (`cleanup/ros-cleanup.sh`)

At session end, lists all running ROS2 processes and instructs Claude to kill
any that it started or that are no longer needed. Excludes the `ros2cli.daemon`
unless explicitly requested.

### Session-limit watcher (`watchers/session-limit.sh`)

A systemd user timer runs `bin/watcher-runner.sh` every 3 hours, independent
of any active Claude session. The bundled watcher:

1. Lists tmux panes running `claude`.
2. Captures each pane's recent output and looks for the 5-hour limit banner.
3. After the displayed reset time has passed, sends a bare Enter to the pane
   (`tmux send-keys`) and POSTs `continue` to the channel server.

The watcher gracefully no-ops when tmux isn't installed, no tmux server is
running, or no Claude panes exist. To check its status:

```
systemctl --user status agentic-cleanup-watcher.timer
# or, on cron systems:
crontab -l | grep AGENTIC_CLEANUP_WATCHER
```

## Uninstall

```bash
bash ~/.local/share/agentic-cleanup/uninstall.sh
```

This kills any running timer, stops the systemd watcher timer (or removes the
cron entry), removes the shell aliases from `~/.bashrc`/`~/.zshrc`, removes
`~/.local/share/agentic-cleanup/`, and prints a reminder about per-repo
cleanup.

You must manually remove the per-repo configuration from each project:

- Delete the `SessionStart` and `SessionEnd` hook entries from
  `.claude/settings.local.json`
- Delete the `cleanup` server entry from `.mcp.json`

## Security

The channel endpoint accepts arbitrary text and pushes it into the Claude
session. The following mitigations limit the attack surface:

- **Localhost-only**: The HTTP server binds to `127.0.0.1:8789`. No external
  network access.
- **Per-session auth token**: `session-start.sh` generates a fresh 32-character
  random token each session, stored at `data/.token` with mode 600. Every
  request must include `Authorization: Bearer <token>`. The server re-reads the
  token file on each request so rotation takes effect immediately.
- **Content size limit**: Payloads exceeding 64 KB are rejected (HTTP 413).
- **Channel instructions**: The MCP server's instructions tell Claude to treat
  incoming content as automated diagnostic data, not human input. This is
  defense-in-depth only.

## Testing

The test suite is in `tests/`. Run individual test scripts:

```bash
# Channel server integration (start server, test auth, verify responses)
bash tests/test-channel.sh

# Check script unit tests (disk and ROS2 checks with mocked data)
bash tests/test-checks.sh

# Session-limit watcher tests (mocked tmux/curl, all protocol cases)
bash tests/test-watchers.sh

# Install/uninstall lifecycle test
bash tests/test-install.sh
```

For a manual end-to-end test:

1. Run `bash install.sh`
2. `cd` into your project repo and run `python3 ~/.local/share/agentic-cleanup/add-repo.py`
3. Start Claude: `claude-autocontinue` (or `claude-autoclean` without tmux)
4. Verify the channel server is listening on port 8789
5. Confirm the SessionStart hook fires and initial context is pushed
6. Wait 30 minutes (or manually run `bash ~/.local/share/agentic-cleanup/bin/tick.sh`)
7. Exit Claude and verify cleanup context is pushed

## Adding your own scripts

The check and cleanup systems are designed to be extended. Drop a new `.sh`
script into `checks/` or `cleanup/` and it will be picked up automatically.

### Check scripts (`checks/`)

These run every 30 minutes via `tick.sh` and at session start/end. A check
script should:

1. Detect a condition (disk usage, stale processes, etc.)
2. Write context for Claude to `$HOME/.local/share/agentic-cleanup/context/<name>.md`
3. Write an empty file if there is nothing to report

The context file content is pushed into the active Claude session. Write it
as if you are briefing Claude: state what happened, what was done (if
anything), and what Claude should do next.

Runtime state (baselines, previous snapshots) goes in
`$HOME/.local/share/agentic-cleanup/data/`.

### Cleanup scripts (`cleanup/`)

These run only at session end, after the final `tick.sh`. Use them for
teardown instructions that should only happen when the user exits Claude.
Same convention: write context to `context/<name>.md`.

### Example

A minimal check script that warns Claude when a build output directory
exceeds 5 GB:

```bash
#!/bin/bash
set -euo pipefail

CONTEXT="$HOME/.local/share/agentic-cleanup/context/build-size.md"
BUILD_DIR="$HOME/Documents/my-project/build"

SIZE_KB=$(du -sk "$BUILD_DIR" 2>/dev/null | awk '{print $1}' || echo 0)
SIZE_GB=$((SIZE_KB / 1048576))

if [ "$SIZE_GB" -ge 5 ]; then
    echo "Build directory is ${SIZE_GB} GB. Consider running a clean build." > "$CONTEXT"
else
    : > "$CONTEXT"
fi
```

After adding a script, make it executable (`chmod +x`) and reinstall with
`bash install.sh`.

## File structure

```
agentic-cleanup/
  install.sh              Install to ~/.local/share/agentic-cleanup/
  uninstall.sh            Remove installation
  add-repo.py             Configure hooks + MCP for a target repo
  channel/
    package.json           Bun dependencies (@modelcontextprotocol/sdk)
    cleanup-channel.ts     One-way MCP channel server
  bin/
    session-start.sh       SessionStart hook handler
    session-end.sh         SessionEnd hook handler
    tick.sh                Periodic check runner
    watcher-runner.sh      Iterates watchers/*.sh (run by systemd/cron)
  checks/
    disk.sh                Disk usage check + automatic log cleanup
    ros2.sh                Stale ROS2 process detection
  cleanup/
    ros-cleanup.sh         Session-end ROS2 cleanup instructions
  watchers/
    session-limit.sh       Detect + continue after 5-hour session limit
  systemd/
    agentic-cleanup-watcher.service.in   Systemd service template
    agentic-cleanup-watcher.timer.in     3-hour timer template
  context/                 Generated context files (gitignored)
  data/                    Runtime state (gitignored)
  tests/
    test-channel.sh        Channel server integration test
    test-checks.sh         Check script unit tests
    test-install.sh        Install/uninstall lifecycle test
    test-watchers.sh       Session-limit watcher unit tests
```
