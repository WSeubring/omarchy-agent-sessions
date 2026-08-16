#!/usr/bin/env bash
# Link this checkout into the Omarchy shell as a bar widget.
#
# The plugin id carries the owner's username, which is how Omarchy separates
# user plugins from the packaged ones, so the link is named after whoever runs
# this rather than after mine.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# --pi also drops the pi reporter extension into ~/.pi/agent/extensions/, which
# is what lets a plain-terminal pi report working/idle instead of merely being
# seen. It writes into pi's config, so it is opt-in.
with_pi=false
args=()
for arg in "$@"; do
  case $arg in
    --pi) with_pi=true ;;
    *) args+=("$arg") ;;
  esac
done

plugin_id="${args[0]:-${USER}.sessions}"
target="$HOME/.config/omarchy/plugins/$plugin_id"

mkdir -p "$HOME/.config/omarchy/plugins"

if [[ -e $target && ! -L $target ]]; then
  echo "refusing to replace $target: it is a real directory, not a link" >&2
  exit 1
fi

ln -sfn "$repo" "$target"
echo "linked $target -> $repo"

if $with_pi; then
  pi_dir="$HOME/.pi/agent/extensions"
  if [[ -d $pi_dir ]]; then
    cp "$repo/integrations/pi/agent-sessions-state.ts" "$pi_dir/"
    echo "installed the pi reporter into $pi_dir (delete the file to undo)"
  else
    echo "skipping --pi: $pi_dir does not exist" >&2
  fi
fi

if command -v omarchy >/dev/null 2>&1; then
  omarchy bar put "$plugin_id" --before omarchy.tray >/dev/null 2>&1 ||
    echo "add it to the bar yourself: omarchy bar put $plugin_id"
  # A bar widget's QML is instantiated once; the running instance survives a
  # plugin reload, so a fresh checkout needs the shell restarted.
  omarchy restart shell >/dev/null 2>&1 || true
  echo "widget is on the bar; run 'omarchy restart shell' after editing QML"
fi
