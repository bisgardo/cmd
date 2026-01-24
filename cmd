#!/usr/bin/env bash

set -euo pipefail

# UTILITIES #

function cmd_log {
	>&2 echo "$@"
}

function cmd_split {
  # args: delim
  # input: string_to_split
  local delim="$1"
	local part
	while read -rd "$delim" part; do
		echo "$part"
	done
	echo "$part"
}

# RESOLVER #

CMD_SUFFIX=.cmd

function _cmd_make_run_script_by_root {
  # args: root path [args...]
  local root="$1"
  local path_from_root="$2"
  shift 2

  local cmd_path="$root/$path_from_root$CMD_SUFFIX"
  if [ -e "$cmd_path" ]; then
    # Outputs script like `root=... root/p1/p2.cmd [args]`.
    echo "root=$root $cmd_path" "$@"
  fi
}

# RUN

function _cmd_resolve_run_scripts {
  cmd_split ':' <<< "$CMD_ROOTS" |
    while read -r root; do
      _cmd_make_run_script_by_root "$root" "$@"
    done
}

if [ "$#" -eq 0 ]; then
  cmd_log "cmd is a tool for finding and running commands."
  cmd_log "Usage: cmd <command> [args]"
  cmd_log "Searches for <command>.cmd within a set of root specified by env var CMD_ROOTS and runs it."
else
  eval "$(_cmd_resolve_run_scripts "$@")"
fi
