#!/bin/bash
# Install the agent sleep guard as a per-user LaunchAgent.
set -euo pipefail

LABEL=com.keepawake.agents
DEST="$HOME/.claude"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SRC="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$DEST" "$HOME/Library/LaunchAgents"
install -m 755 "$SRC/keep-awake.sh" "$DEST/keep-awake.sh"
[ -f "$DEST/keep-awake.conf" ] || install -m 644 "$SRC/keep-awake.conf.example" "$DEST/keep-awake.conf"
sed "s#__HOME__#$HOME#g" "$SRC/$LABEL.plist" > "$PLIST"
plutil -lint "$PLIST" >/dev/null

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$PLIST"
launchctl print "gui/$UID/$LABEL" | grep -E "state =|pid ="
echo "installed. edit $DEST/keep-awake.conf then: launchctl kickstart -k gui/$UID/$LABEL"
