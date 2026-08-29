# mac-agent-keepawake

A small macOS daemon that stops your Mac sleeping in the middle of a long-running
AI agent tool call — without keeping it awake when the agent is just sitting idle.

Works with Claude Code, Codex, Qwen Code, Kilo, OpenCode, Antigravity (`agy`), and
anything else you add to a one-line config.

---

## The problem

macOS decides you are idle from keyboard and mouse input. **CPU work does not
count.** A terminal churning at 100% is, as far as the power manager is concerned,
doing nothing.

Agent CLIs work around this by holding a power assertion while they run. Claude
Code holds `caffeinate -i -t 300` — a five-minute assertion, renewed between
turns. That is fine for a conversation, and wrong for a long tool call: the agent
enters a ten-minute command, never returns to the renewal point, and the assertion
expires underneath it.

Real trace from `pmset -g log`:

```
14:34:12   agent starts a 10-minute polling command
14:34:58   the 5-minute assertion expires; nothing renews it
14:35:04   Mac enters Idle Sleep, mid-command
14:45:08   machine woken by hand — the suspended command immediately
           reports "Command timed out after 10m 0s"
```

Ten minutes of work lost, and the session had to be nursed back by hand.

Upstream tracking for Claude Code specifically:
[anthropics/claude-code#81832](https://github.com/anthropics/claude-code/issues/81832)
— the inhibitor SIGKILLs its `caffeinate` before spawning the replacement, so
assertions briefly hit zero every 240 s. This tool is a stopgap, not a substitute
for that fix.

The naive fix — wrapping the agent in `caffeinate` for its whole lifetime — trades
one bug for a worse one: your Mac then stays awake for as long as a terminal is
*open*, not as long as it is *working*. On a laptop that is a dead battery.

## What this does

One background daemon watches every agent session on the machine and holds a
sleep assertion **only while a tool is actually executing**. When every session is
idle at a prompt, it holds nothing and your Mac sleeps on its normal timer.

- One daemon total, not one per session. Cost is the same for 1 session or 50.
- Covers every terminal, tmux pane, and GUI launch. No shell wrapper, no aliases,
  nothing to remember to type.
- Starts at login, restarts if it dies, and needs no attention afterwards.

## Install

```sh
git clone https://github.com/jammysunshine/mac-agent-keepawake.git
cd mac-agent-keepawake
./install.sh
```

This installs `~/.claude/keep-awake.sh`, writes `~/.claude/keep-awake.conf` if you
do not already have one, and loads `com.keepawake.agents` as a per-user
LaunchAgent. Nothing runs as root and nothing is installed system-wide.

You should see:

```
state = running
pid = 12345
```

## Verify it works

Check the daemon is up:

```sh
launchctl print gui/$UID/com.keepawake.agents | grep -E "state =|pid ="
```

While an agent is running a long command, it should have a `caffeinate` child:

```sh
pgrep -P "$(pgrep -f keep-awake.sh | head -1)" | xargs ps -o pid,comm= -p
```

And the system should report the assertion:

```sh
pmset -g assertions | grep PreventUserIdleSystemSleep
```

`1` while a tool is running, `0` within about 30 seconds of everything going idle.

## Configure

`~/.claude/keep-awake.conf` holds a single extended regex, matched against process
names:

```
^(claude|codex|qwen|kilo|opencode|agy)$
```

Add whatever you use, then restart:

```sh
launchctl kickstart -k gui/$UID/com.keepawake.agents
```

Two environment knobs, set in the plist if you want them:

| Variable | Default | Meaning                                     |
|----------|---------|---------------------------------------------|
| `POLL`   | `15`    | seconds between checks                      |
| `GRACE`  | `2`     | consecutive idle polls before releasing     |

## How it decides "busy"

Two signals, either of which counts, both requiring an agent ancestor:

1. **a shell with a child** — a tool command is executing. An idle agent's shell
   has no children, so the child is the signal.
2. **the agent's own `caffeinate`** — the agent considers itself busy.

Signal 2 matters more than it looks. Model inference, response streaming and
context compaction spawn no child process at all, so signal 1 alone reads a
hard-working session as idle and lets the machine sleep underneath it. Mirroring
the agent's own assertion also covers the window where its relay kills one
`caffeinate` before spawning the next.

The check walks **up** from shells rather than down from agents. This matters for
GUI agents: an Electron-based tool always has GPU, renderer and plugin helper
children, and a naive "does the agent have children" test would read it as
permanently busy and pin your machine awake for as long as the IDE is open.

Implementation is one `ps` piped into one `awk` per poll — which is why session
count does not affect cost.

## Cost

Measured over 60 seconds of running:

| Metric        | Value          |
|---------------|----------------|
| CPU time      | 0.01 s         |
| Memory (RSS)  | 2.2 MB         |
| Processes     | 1 (+1 while holding) |

Roughly 0.6 seconds of CPU per hour. Orders of magnitude below your display.

## Limits

- **Closing the lid on battery still sleeps.** No power assertion overrides that.
- Detection is process-tree based. An agent that executes tools without spawning a
  shell will not be seen as busy.
- The hold is released two polls after work stops, so a burst of very short
  commands may see the assertion drop briefly between them. The agent's own
  short-lived assertion covers that window.
- macOS only. It depends on `caffeinate`, `launchctl` and `pmset`.

## Troubleshooting

**Daemon is not running**

```sh
launchctl print gui/$UID/com.keepawake.agents
cat /tmp/agent-keepawake.err
```

**Mac still sleeps during a tool call.** Check your agent's process name is in the
config and matches exactly:

```sh
ps -eo comm= | grep -iE "claude|codex|your-agent"
```

**Mac never sleeps.** Something is holding an assertion. Find out what:

```sh
pmset -g assertions
```

If it is this daemon while everything is idle, your agent likely keeps a shell with
a long-lived child — an integrated terminal running a dev server, for example.
That is indistinguishable from work by design.

**Check your sleep timers** — a very short idle timer makes any gap in coverage
immediately visible:

```sh
pmset -g custom | grep -E "^ sleep|displaysleep"
```

## Uninstall

```sh
./uninstall.sh
```

Unloads and removes the daemon, keeping your config file.

## Licence

MIT — see [LICENSE](LICENSE).
