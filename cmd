#!/usr/bin/env bash

set -euo pipefail

# UTILITIES #

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
  # args: root [path...] [args...]
  local root="$1"
  shift
  local dir="$root"
  for part in "$@"; do
    if ! [ -d "$dir" ]; then
      break
    fi
    # Ensure that all components in the path to the cmd are excluded from the final args.
    # This doesn't affect iteration.
    shift
    local cmd_file="$dir/$part$CMD_SUFFIX"
    if [ -e "$cmd_file" ]; then
      # Output script like `root=... root/p1/p2.cmd [args]`.
      echo "root=$root $cmd_file" "$@"
      return
    fi
    dir="$dir/$part"
  done
}

# RUN

function _cmd_resolve_run_scripts {
  cmd_split ':' <<< "$CMD_ROOTS" |
    while read -r root; do
      _cmd_make_run_script_by_root "$root" "$@"
    done
}

eval "$(_cmd_resolve_run_scripts "$@")"
