// Report this pi session's state to omarchy-agent-sessions.
//
// pi keeps the state only in memory: its terminal title never changes, and its
// transcript on disk cannot tell a long tool call from a finished turn. So the
// session reports for itself, the same way herdr's own integration does —
// except this writes a small file instead of talking to a multiplexer socket,
// which is what makes it work in a plain terminal.
//
// Install: cp this file to ~/.pi/agent/extensions/ (pi loads every .ts there).
// Remove: delete it. Nothing else in pi is touched.
// @ts-nocheck

import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const STATE_DIR = path.join(
  process.env.XDG_STATE_HOME || path.join(os.homedir(), ".local", "state"),
  "omarchy-agent-sessions",
  "pi",
);
const STATE_FILE = path.join(STATE_DIR, `${process.pid}.json`);

type AgentState = "working" | "blocked" | "idle";

let sessionFile: string | undefined;
let blockedLabel: string | undefined;
// Set when a turn ends, so a session that just finished reads differently from
// one that has been sitting at the prompt since it opened.
let finishedAt: number | undefined;

function write(state: AgentState): void {
  try {
    fs.mkdirSync(STATE_DIR, { recursive: true });
    const payload = {
      pid: process.pid,
      state,
      cwd: process.cwd(),
      sessionFile,
      label: blockedLabel,
      finishedAt,
      updatedAt: Math.floor(Date.now() / 1000),
    };
    // Written whole and renamed into place: the reader polls, and half a file
    // is worse than a slightly stale one.
    const tmp = `${STATE_FILE}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(payload));
    fs.renameSync(tmp, STATE_FILE);
  } catch {
    // A session that cannot report is still a session; never break the agent.
  }
}

function clear(): void {
  try {
    fs.unlinkSync(STATE_FILE);
  } catch {
    // Already gone, or never written.
  }
}

export default function (pi) {
  // Only the interactive TUI has a session a human is waiting on; -p/rpc runs
  // are headless and would just litter the state directory.
  let active = false;

  pi.on("session_start", async (_event, ctx) => {
    if (ctx?.mode !== "tui") return;
    active = true;
    try {
      sessionFile = ctx?.sessionManager?.getSessionFile?.();
    } catch {
      sessionFile = undefined;
    }
    // A reload can install this mid-turn, so trust isIdle over assumption.
    write(ctx?.isIdle?.() === false ? "working" : "idle");
  });

  pi.on("agent_start", (_event, ctx) => {
    if (!active) return;
    try {
      sessionFile = ctx?.sessionManager?.getSessionFile?.() || sessionFile;
    } catch {
      // keep the previous value
    }
    write("working");
  });

  pi.on("agent_settled", (_event, ctx) => {
    if (!active || ctx?.isIdle?.() !== true) return;
    finishedAt = Math.floor(Date.now() / 1000);
    write("idle");
  });

  // The one thing pi genuinely blocks on out of the box.
  pi.on("project_trust", async (event, _ctx) => {
    if (!active) return;
    blockedLabel = `trust ${event?.cwd ?? "project"}?`;
    write("blocked");
    blockedLabel = undefined;
  });

  pi.on("session_shutdown", async () => {
    if (!active) return;
    clear();
  });

  // A crash skips session_shutdown; the collector prunes files whose pid is
  // gone, so a stale file is harmless rather than a ghost session.
  process.on("exit", clear);
}
