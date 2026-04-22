# Updates the current open repo's claude settings with a hook.
# This file should be ran in each individual repo to use this tool. That is,
# one would run from ~/Documents/my-repo/, > python ~/.local/share/claude-cleanup/add-repo.py

# Read the current .claude/settings.local.json file and parse it.
# Find the hooks element
# Add a new hook, SessionStart
# matcher: ""
# hooks: [ { "type": "command", "command": "bash ~/.local/share/claude-cleanup/bin/session-start.sh"}]

# Add a second hook, SessionEnd
# Use the same settings as for SessionStart, but the script is named session-end.sh

# Include error checking. For instance, if .claude doesn't exist, make the folder first.
# If there are no hooks, add parts to the json to fill this in
# If add-repo has been run previously then these hooks may already exist.
# If they do exist, don't change them and tell the user that they already existed.
# (If for some reason one existed previously and the other did not, add the one new
# one and inform the user)

# Save the updated json file and gracefully exist.