#!/usr/bin/env python3
# Run with: python3 ~/.local/share/agentic-cleanup/add-repo.py
"""Configure a repo to use agentic-cleanup hooks and channel."""

import json
import os
import sys
from pathlib import Path

CLEANUP_DIR = Path.home() / ".local" / "share" / "agentic-cleanup"
SESSION_START_CMD = f"bash {CLEANUP_DIR / 'bin' / 'session-start.sh'}"
SESSION_END_CMD = f"bash {CLEANUP_DIR / 'bin' / 'session-end.sh'}"
CHANNEL_TS = str(CLEANUP_DIR / "channel" / "cleanup-channel.ts")


def load_json(path: Path) -> dict:
    if path.exists():
        with open(path) as f:
            return json.load(f)
    return {}


def save_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


def is_our_hook(hook_group: dict, command_substr: str) -> bool:
    for h in hook_group.get("hooks", []):
        if h.get("type") == "command" and command_substr in h.get("command", ""):
            return True
    return False


def configure_hooks(settings_path: Path) -> list[str]:
    settings = load_json(settings_path)
    hooks = settings.setdefault("hooks", {})
    messages = []

    for event, cmd, script_name in [
        ("SessionStart", SESSION_START_CMD, "session-start.sh"),
        ("SessionEnd", SESSION_END_CMD, "session-end.sh"),
    ]:
        event_hooks = hooks.get(event, [])

        already_exists = any(
            is_our_hook(hg, "agentic-cleanup") for hg in event_hooks
        )
        if already_exists:
            messages.append(f"  {event}: already configured, skipping")
            continue

        new_entry = {
            "matcher": "",
            "hooks": [{"type": "command", "command": cmd}],
        }

        event_hooks.append(new_entry)
        hooks[event] = event_hooks
        messages.append(f"  {event}: configured → {script_name}")

    settings["hooks"] = hooks
    save_json(settings_path, settings)
    return messages


def configure_mcp(mcp_path: Path) -> list[str]:
    mcp = load_json(mcp_path)
    servers = mcp.setdefault("mcpServers", {})
    messages = []

    if "cleanup" in servers:
        messages.append("  MCP server 'cleanup': already configured, skipping")
    else:
        servers["cleanup"] = {
            "command": "bun",
            "args": [CHANNEL_TS],
        }
        messages.append("  MCP server 'cleanup': added")

    save_json(mcp_path, mcp)
    return messages


def main() -> None:
    if not CLEANUP_DIR.exists():
        print(f"Error: agentic-cleanup is not installed at {CLEANUP_DIR}")
        print("Run install.sh first.")
        sys.exit(1)

    repo_dir = Path.cwd()
    settings_path = repo_dir / ".claude" / "settings.local.json"
    mcp_path = repo_dir / ".mcp.json"

    print(f"Configuring agentic-cleanup for: {repo_dir}")
    print()

    print("Hooks (.claude/settings.local.json):")
    for msg in configure_hooks(settings_path):
        print(msg)
    print()

    print("Channel (.mcp.json):")
    for msg in configure_mcp(mcp_path):
        print(msg)
    print()

    print("Done! Start Claude with:")
    print("  claude --dangerously-load-development-channels server:cleanup")


if __name__ == "__main__":
    main()
