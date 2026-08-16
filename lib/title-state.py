#!/usr/bin/env python3
"""Read an agent's state out of its terminal title.

Agents announce themselves in the window title (OSC 0/2) — Claude prefixes a
spinner while a turn runs, amp says "Plugin confirmation needed" when it wants
you. herdr already curates those patterns per agent, as `osc_title` rules in the
detection manifests it downloads, so this reuses them rather than inventing a
second set of heuristics.

    title-state.py <agent> <title>   ->   blocked|working|idle  (empty if unknown)

With no manifest for the agent, or no rule that matches, nothing is printed and
the caller decides what a running-but-unreadable agent should look like.
"""

import os
import re
import sys
import tomllib
from pathlib import Path

# Same lookup order herdr uses: a local override shadows the cached remote copy.
MANIFEST_DIRS = [
    Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "herdr" / "agent-detection",
    Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "herdr" / "agent-detection" / "local",
    Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "herdr" / "agent-detection" / "remote",
]


def manifest_for(agent: str):
    for directory in MANIFEST_DIRS:
        path = directory / f"{agent}.toml"
        if path.is_file():
            with path.open("rb") as handle:
                return tomllib.load(handle)
    return None


def to_python_regex(pattern: str) -> str:
    """Rust's regex crate spells a codepoint \\x{2800}; Python spells it \\U00002800."""
    return re.sub(r"\\x\{([0-9A-Fa-f]+)\}", lambda m: "\\U%08x" % int(m.group(1), 16), pattern)


def rule_matches(rule: dict, title: str) -> bool:
    contains = rule.get("contains") or []
    patterns = rule.get("regex") or []
    if not contains and not patterns:
        return False
    for needle in contains:
        if needle not in title:
            return False
    for pattern in patterns:
        try:
            if not re.search(to_python_regex(pattern), title):
                return False
        except re.error:
            return False
    return True


def state_for(agent: str, title: str) -> str:
    manifest = manifest_for(agent)
    if not manifest or not title:
        return ""
    rules = [r for r in manifest.get("rules", []) if r.get("region") == "osc_title"]
    # Highest priority first, exactly as herdr evaluates them.
    for rule in sorted(rules, key=lambda r: r.get("priority", 0), reverse=True):
        if rule.get("skip_state_update"):
            continue
        if rule_matches(rule, title):
            state = rule.get("state", "")
            return state if state in ("blocked", "working", "idle") else ""
    return ""


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(0)
    print(state_for(sys.argv[1], sys.argv[2]))
