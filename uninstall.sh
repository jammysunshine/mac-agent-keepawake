#!/bin/bash
LABEL=com.keepawake.agents
launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist" "$HOME/.claude/keep-awake.sh"
echo "removed (kept ~/.claude/keep-awake.conf)"
