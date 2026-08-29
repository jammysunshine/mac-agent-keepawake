#!/bin/bash
# Single system-wide sleep guard for agent CLIs (claude, codex, gemini, ...).
#
# Why: an agent's own keep-awake (Claude Code uses `caffeinate -i -t 300`) is
# renewed between turns only, so it lapses during any tool call longer than
# ~4 minutes and the Mac sleeps mid-command. This holds one assertion whenever
# ANY agent session is executing a tool, and nothing when they are all idle.
#
# One daemon covers every session in every terminal, tmux pane, or GUI launch.
# Cost is one `ps` per poll regardless of how many sessions are open.

POLL=${POLL:-15}
GRACE=${GRACE:-2}          # consecutive idle polls before releasing
CONF="$HOME/.claude/keep-awake.conf"
AGENTS='^(claude|codex|gemini|qwen|kilo|cursor-agent|aider|opencode|crush)$'
[ -r "$CONF" ] && AGENTS=$(grep -v '^[[:space:]]*#' "$CONF" | grep . | head -1)

hold=""; idle=0

# Busy when a shell descended from an agent process has a child, i.e. a tool
# command is actually executing. Walking up from shells (rather than down from
# agents) keeps GUI agents safe: an Electron app like Antigravity always has
# helper children, which would otherwise read as permanently busy.
busy() {
  ps -eo pid=,ppid=,comm= | awk -v agents="$AGENTS" '
    { pid=$1; pp=$2; c=$0
      sub(/^[[:space:]]*[0-9]+[[:space:]]+[0-9]+[[:space:]]+/, "", c)
      sub(/.*\//, "", c); sub(/^-/, "", c)
      parent[pid]=pp; name[pid]=c; kids[pp]++ }
    END {
      for (p in name) {
        if (name[p] !~ /^(zsh|bash|sh|fish|dash|ksh)$/) continue
        if (kids[p] == 0) continue
        a = parent[p]
        for (d = 0; d < 40 && a != "" && a != "0" && a != "1"; d++) {
          if (name[a] ~ agents) { print "busy"; exit }
          a = parent[a]
        }
      }
    }' | grep -q busy
}

release() { [ -n "$hold" ] && kill "$hold" 2>/dev/null; hold=""; }
trap 'release; exit 0' TERM INT EXIT

while :; do
  if busy; then
    idle=0
    if [ -z "$hold" ] || ! kill -0 "$hold" 2>/dev/null; then
      caffeinate -ims & hold=$!
    fi
  else
    idle=$((idle + 1))
    [ "$idle" -ge "$GRACE" ] && release
  fi
  sleep "$POLL"
done
