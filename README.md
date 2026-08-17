# omarchy-agent-sessions

[![License: MIT](https://img.shields.io/github/license/WSeubring/omarchy-agent-sessions)](LICENSE)
![Scope: personal](https://img.shields.io/badge/scope-personal-blue)

Every coding-agent session running on this machine, in the [Omarchy](https://omarchy.org)
bar: what state it is in, which directory it runs in, and what it is working on.
The widget leaves the bar entirely when nothing is running.

Claude Code and pi work today; other agents are a collector away.

## Install

```bash
git clone https://github.com/WSeubring/omarchy-agent-sessions.git
cd omarchy-agent-sessions
./install.sh                 # links it as <user>.sessions and puts it on the bar
./install.sh --pi            # …and installs the pi reporter (see below)
```

The script links the checkout into `~/.config/omarchy/plugins/`, so edits are
live. A bar widget's QML is instantiated once, though: after changing a `.qml`
file, run `omarchy restart shell` — a plugin reload alone keeps the old
instance (and its stale IPC handlers) running.

## States

| State | Means |
|---|---|
| **blocked** | A permission prompt or a question is waiting on you |
| **working** | A turn is running |
| **done** | Just finished, not picked up yet |
| **idle** | Sitting at the prompt |

## Bar indicator styles

`omarchy bar set <user>.sessions indicatorStyle <style>`

| Style | Draws | Width | Trade-off |
|---|---|---|---|
| `groups` (default) | `󰚩 󰀦2 ◐3 󰄬1` | fixed, ~3 groups | Every state that can act on you, one number each. Idle is omitted unless it is all there is. |
| `dots` | `󰚩 󰀦󰀦◐◐󰄬○ +2` | grows with sessions | Per-session detail, but the glyphs blur together past a handful, hence `maxDots`. |
| `count` | `󰚩 5` / `󰚩 2!` | smallest with a number | Total only; blocked turns the whole label red. |
| `minimal` | `󰚩` | one glyph | State by colour alone: red blocked, bright working, dim otherwise. |

Working sessions turn the glyph (`◐◓◑◒`) so movement, not a number, says
something is live; a blocked session breathes the whole label between full and
45% opacity. Both are settings: `animateWorking`, `pulseBlocked`.

Panel rows carry a per-agent mark — `󰚩` for Claude, `π` for pi, and the first
two letters of the name for anything else. Override with the `agentGlyphs`
setting, e.g. `{"codex": "󰅩"}`.

## Interactions

- Bar icon: left = panel, middle = focus whatever needs you, right = refresh.
- Panel row: left = focus that session's terminal, middle = copy its cwd.
- Panel keys: `j`/`k` move, Enter focus, `c` copy cwd, `r` refresh, Esc close.
- IPC: `omarchy-shell <user>.sessions <open|close|toggle|refresh|status|label|next|focus>`.
  `next` focuses the first blocked session (else the first working one) and is
  the thing to bind to a key; `focus <name|pane|pid>` targets one directly.

Focusing walks up the process tree from the session pid until a pid matches a
Hyprland client, because the window belongs to the terminal rather than to the
agent. Hyprland parses dispatches as Lua now, so the call is
`hl.dsp.focus({ window = "address:…" })`; the pre-Lua string form still exits 0
while printing an error, which is why it is only a fallback.

## How sessions are discovered

`bin/agent-sessions` runs every executable in `bin/collectors/`, merges what
they return, and ranks it. Each collector prints a JSON array; nothing else in
the widget knows which agents exist.

| Collector | Source | Can see "blocked"? |
|---|---|---|
| `claude` | `~/.claude/sessions/<pid>.json`, the peer-session record the CLI maintains, plus the `ai-title` in the transcript | yes — the record has a real status |
| `herdr` | `herdr api snapshot`: every agent the [herdr](https://herdr.dev) multiplexer hosts, whatever kind | yes — herdr reports the same four states |
| `pi-state` | What the pi reporter extension writes to `~/.local/state/omarchy-agent-sessions/pi/` | yes — pi reports for itself |
| `processes` | Any known agent CLI running in a plain terminal: presence and cwd from procfs, title from the terminal window, state from herdr's `osc_title` rules applied to that title | only if the agent puts it in its title |

herdr itself learns an agent's state two ways, which is worth knowing when a
state looks wrong. Its fallback is screen scraping: per-agent rule manifests
(`~/.local/state/herdr/agent-detection/remote/<agent>.toml`, fetched from
herdr.dev) match the OSC title and regions of the visible buffer. pi's manifest
carries a single rule — the literal `Working...` — so scraping alone never
yields "blocked" for it. The accurate path is `herdr integration install <agent>`,
which drops a reporter into the agent itself (`~/.pi/agent/extensions/herdr-agent-state.ts`
for pi, `~/.claude/hooks/herdr-agent-state.sh` for Claude, plugins for opencode
and hermes). Those hook the agent's own lifecycle events and push
`pane.report_agent` over herdr's socket, so blocked/working/idle come from the
agent rather than from its pixels. `herdr integration status` shows what is
wired up.

Two sightings of one session (its own collector and the multiplexer hosting it)
merge into a single row, joined on pid, then session id, then pane. A `priority`
field decides who wins a contested field: an agent that keeps a real status
beats one inferred from a terminal title.

`AGENTS=claude,pi bin/agent-sessions` limits a run to named collectors.

### Adding an agent

Drop an executable in `bin/collectors/` that prints a JSON array. Only `agent`,
`state` and `title` are required:

```json
[{ "agent": "codex", "state": "working", "title": "port the parser",
   "cwd": "/home/me/src/app", "dir": "src/app", "pid": 1234,
   "ageSec": 12, "priority": 2, "host": "window" }]
```

`state` is one of `blocked | working | done | idle`. `priority` is the
tie-breaker described above (0 = authoritative). `lib/collector.sh` has the
shared helpers: `shorten_dir`, `alive`, `cwd_of`, `newest`, and
`state_from_mtime`, which is the fallback for agents that keep no status of
their own.

Most agents need no collector at all. `processes` already finds them: add
`<agent>:<process-name>` to `~/.config/omarchy/agent-sessions/processes.conf`
and the CLI shows up with its directory and title. Write a collector only when
an agent keeps state worth reading that neither its window title nor herdr
exposes.

The same binary sometimes runs as a background service rather than a session —
`claude --chrome-native-host`, the host behind the Chrome extension, sits in the
browser and would otherwise show up as a row titled after the current tab. Those
are matched by cmdline and dropped; `AGENT_SESSIONS_INCLUDE_HELPERS=1` shows
them again.

## Titles

Claude names its own sessions; most agents do not, so a row would read
`pi session`. Instead the first thing you said in that session goes to Haiku
once, through `bin/title-cache`, and the answer is cached by session for good —
one small call per session, ever. A cache miss never blocks: the row keeps its
fallback until the next refresh picks the title up. `AGENT_TITLES=0` turns it
off, `AGENT_TITLE_MODEL` picks a different model.

## The pi reporter

pi holds its state in memory: the terminal title never changes, and the
transcript on disk cannot separate a long tool call from a finished turn. So pi
reports for itself. `integrations/pi/agent-sessions-state.ts` hooks
`session_start`, `agent_start`, `agent_settled` and `project_trust`, and writes
one small JSON file per session — the same design as herdr's integration, minus
the multiplexer, which is what makes it work in a plain terminal.

Install with `./install.sh --pi`, or copy the file into
`~/.pi/agent/extensions/` yourself; delete it to undo. Without it, pi still
appears via the `processes` collector, just without a readable state.

The same pattern fits any agent with an extension API. Write the state file,
and `pi-state` is the model for the collector that reads it.

### Where state comes from, per situation

| Agent runs… | State from | Blocked? |
|---|---|---|
| Claude, anywhere | its own session record | yes |
| under herdr, integration installed | the in-agent reporter over herdr's socket | yes |
| under herdr, no integration | herdr's screen scraping | working/idle |
| pi with the reporter installed, anywhere | pi's own lifecycle events | yes, for trust prompts |
| plain terminal | window title + herdr's `osc_title` rules | only if the title says so |
| no window at all (detached, ssh) | nothing — presence only | no |

Nothing disappears outside herdr; what degrades is the state, and it degrades
to "running", never to a guess. Two ways to sharpen a specific agent: drop an
`osc_title` rule into `~/.config/herdr/agent-detection/<agent>.toml` (herdr
reads that override, and so does this widget), or have the agent report for
itself the way the pi reporter does. The title route only works if the agent
puts state in its title — measured against a live session, pi never does: it
stays `π - <dir>` through working, blocked and idle alike, which is why the
reporter exists.

## herdr-hosted sessions

A session started inside herdr hangs off `herdr server`, so the pid walk finds
no window — the agent may have no window anywhere, because the multiplexer keeps
running with nobody attached. Those rows are marked `󰆍 herd w1:p1`, and focusing
one:

1. `herdr agent focus <pane_id>` selects the pane inside the session.
2. If a herdr *client* is running, its terminal window gets focused.
3. Otherwise `omarchy-launch-terminal-herdr` attaches one, and the script waits
   for the window to map before focusing it and re-asserting the pane, since the
   client picks its own focus on attach.

## Demo fixture

Drop a `demo.json` next to this README (same shape the collectors emit) and
`bin/agent-sessions` serves it instead of the live sources — useful for
eyeballing a bar style against states that are not currently happening. Delete
it to go live.
