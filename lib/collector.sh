#!/usr/bin/env bash
# Helpers shared by the collectors. Source it, do not run it.

# ~/Development/foo/bar reads as foo/bar; the home directory reads as ~.
shorten_dir() {
  local dir=$1
  dir=${dir/#$HOME\/Development\//}
  [[ $dir == "$HOME" ]] && { printf '~'; return; }
  printf '%s' "${dir/#$HOME\//~/}"
}

# The pid of a process is only interesting while it still exists: every source
# here can outlive the CLI that wrote it.
alive() {
  [[ -n ${1:-} ]] && kill -0 "$1" 2>/dev/null
}

# Working directory of a running process, straight from procfs.
cwd_of() {
  readlink -f "/proc/${1}/cwd" 2>/dev/null
}

# An agent with no status of its own is judged by its transcript: a file written
# in the last few seconds means a turn is running. It cannot see a permission
# prompt, so such agents never report "blocked" — that needs a real status
# source (the Claude session record, or herdr).
state_from_mtime() {
  local file=$1 working_window=${2:-20} done_window=${3:-300} now age
  [[ -f $file ]] || { printf 'idle'; return; }
  now=$(date +%s)
  age=$((now - $(stat -c %Y "$file" 2>/dev/null || echo 0)))
  if ((age <= working_window)); then printf 'working'
  elif ((age <= done_window)); then printf 'done'
  else printf 'idle'; fi
}

age_of_file() {
  local file=$1 now
  [[ -f $file ]] || { printf '0'; return; }
  now=$(date +%s)
  printf '%s' $((now - $(stat -c %Y "$file" 2>/dev/null || echo "$now")))
}

# Newest file matching a glob, or empty. Callers pass an expanded list.
newest() {
  local newest="" f
  for f in "$@"; do
    [[ -f $f ]] || continue
    [[ -z $newest || $f -nt $newest ]] && newest=$f
  done
  printf '%s' "$newest"
}
