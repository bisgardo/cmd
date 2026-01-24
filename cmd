#!/usr/bin/env bash

set -euo pipefail

_cmd_name="$(basename "$0")"

# UTILITIES #

function cmd_log {
  # args: strings_to_log
	>&2 echo "$@"
}

function cmd_quote {
  # args: strings_to_quote
	local p=
	for v in "$@"; do
		printf "$p%q" "$v"
		p=' '
	done
	echo
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

function cmd_join {
  # args: delim
  # input: strings_to_join...
  local delim="$1"
  local res=
  while read -r str; do
    if [ "$res" ]; then
      res+="$delim"
    fi
    res+="$str"
  done
  echo -e "$res"
}

# RESOLVER #

CMD_SUFFIX=.cmd

function _cmd_echo_root_run_script {
  # args: root path_from_root, cmd_args...
  local root="$1"
  local path_from_root="$2"
  if shift 2; then
    local cmd_path="$root/$path_from_root$CMD_SUFFIX"
    if [ -e "$cmd_path" ]; then
      # Outputs script of the form `root=... script=root/p1/p2.cmd $func [args]`.
      # TODO: What if cmd_args contain quotes??
      echo "root=$(cmd_quote "$root") script=$(cmd_quote "$cmd_path")" \$func "$@"
    fi
  fi
}

# RUN #

function _cmd_echo_run_scripts {
  # args: path_from_root, cmd_args...
  # input: sequence of roots (consumed by 'cmd_split').
  cmd_split ':' |
    while read -r root; do
      _cmd_echo_root_run_script "$root" "$@"
    done
}

function _cmd_resolve_unique_run_script {
  # args: path_from_root, cmd_args...
  # input: sequence of roots (consumed by '_cmd_echo_run_scripts').
  local run_scripts=()
  local r
  while read -r r; do run_scripts+=("$r"); done <<< "$(_cmd_echo_run_scripts "$@")"
	if [ -z "$run_scripts" ]; then
		cmd_log "$_cmd_name: command \"$1\" not found"
		return 1
	fi
	if [ "${#run_scripts[@]}" -gt 1 ]; then
	  function __echo_script {
	    # scope: root, script
	    echo $script
	  }
	  local scripts_joined=$(for r in "${run_scripts[@]}"; do func=__echo_script eval "$r"; done | cmd_join ', ')
	  unset __echo_script
	  cmd_log "$_cmd_name: ambiguous command (matched: $scripts_joined)"
	  return 2
  fi
  echo "$run_scripts" # single-element-array
}

function cmd_run {
  # args: path_from_root, cmd_args...
  local run_script # must declare local first as it otherwise eats the called function's return value
  run_script=$(_cmd_resolve_unique_run_script "$@" <<< "$CMD_ROOTS")
  function __source_script {
    # args: cmd_args...
    # scope: root, script
    source "$script" "$@"
  }
  func=__source_script eval "$run_script"
  unset __source_script
}

if [ "$#" -eq 0 ]; then
  cmd_log "cmd is a tool for finding and running commands."
  cmd_log "Usage: cmd <command> [args]"
  cmd_log "Runs <root>/<command>.cmd, where <root> is a member of the set configured in env var CMD_ROOTS as ':'-separated paths."
else
  cmd_run "$@"
fi
