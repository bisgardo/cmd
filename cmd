#!/usr/bin/env bash

set -euo pipefail

CMD_ROOTS="${CMD_ROOTS-.}"
cmd_command="$(basename $0)"

# UTILITIES #

function cmd_log {
  # args: strings_to_log
  >&2 echo "$@"
}

function cmd_escape {
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

function cmd_include {
  local path="$1"
  source "$cmd_dir/$path$CMD_SUFFIX"
}

# RESOLVER #

CMD_SUFFIX='.cmd'

function _cmd_echo_root_run_script {
  # args: root path_from_root, cmd_args...
  local root="$1"
  local path_from_root="$2"
  if shift 2; then
    # TODO: Accept that cmd_path may leave root dir or prevent it. Add a test either way.
    local cmd_path="$root/$path_from_root$CMD_SUFFIX"
    if [ -e "$cmd_path" ]; then
      # Outputs script of the form `cmd_root=... cmd_script=root/p1/p2.cmd $func [args]`.
      echo "cmd_root=$(cmd_escape "$root") cmd_script=$(cmd_escape "$cmd_path") \$func $(cmd_escape "$@")"
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

function _cmd_echo_unique_run_script {
  # args: path_from_root, cmd_args...
  # input: sequence of roots (consumed by '_cmd_echo_run_scripts').
  local run_scripts=()
  local r
  while read -r r; do run_scripts+=("$r"); done <<< "$(_cmd_echo_run_scripts "$@")"
  if [ -z "$run_scripts" ]; then
    cmd_log "$cmd_command: command \"$1\" not found"
    return 1
  fi
  if [ "${#run_scripts[@]}" -gt 1 ]; then
    function __cmd_echo_script {
      # scope: cmd_root, cmd_script
      echo $cmd_script
    }
    local scripts_joined=$(for r in "${run_scripts[@]}"; do func=__cmd_echo_script eval "$r"; done | cmd_join ', ')
    unset __cmd_echo_script
    cmd_log "$cmd_command: ambiguous command (matched: $scripts_joined)"
    return 2
  fi
  echo "$run_scripts" # single-element-array
}

function cmd_eval {
  # args: eval_expr, path_from_root, cmd_args...
  function __cmd_eval {
    # args: cmd_args...
    # scope: eval_expr, cmd_root, cmd_script, ...
    if [ "${cmd_script-}" ]; then
      # Convenience: expose $cmd_dir to script/expr in eval below.
      local cmd_dir="$(dirname "$cmd_script")"
    elif [[ "$eval_expr" =~ '$cmd_script'|'$cmd_dir' ]]; then
      # Reject any expression that includes the substrings "$cmd_script" or "$cmd_dir" if it doesn't have a value.
      cmd_log "$cmd_command: command required"
      return 5
    fi
    # Eval user-provided expression. Everything in scope is inherited, including args (available as "$@").
    local x=0; eval "$eval_expr" || x=$?
    if [ "$x" -ne 0 ]; then
      cmd_log "$cmd_command: eval of expression \`$eval_expr\` failed with exit code $x"
      return 4
    fi
  }
  local eval_expr="$1"
  shift
  if [ "$#" -eq 0 ]; then
    __cmd_eval
  elif [ "$1" = '--' ]; then
    # Allow passing argument to eval expr by starting with '--'.
    shift
    __cmd_eval "$@"
  else
    local run_script # must declare local first as it otherwise eats the called function's return value
    run_script=$(_cmd_echo_unique_run_script "$@" <<< "$CMD_ROOTS")
    func=__cmd_eval eval "$run_script"
  fi
  unset __cmd_eval
}

function cmd_eval_logged {
  # args: eval_expr, path_from_root, cmd_args...
  function __cmd_eval_log {
    # args: eval_expr
    # scope: cmd_script, ...
    local eval_expr="$1"
    if [ "${cmd_script-}" ]; then
      cmd_log "# [$cmd_script]"
    fi
    cmd_log "> $eval_expr"
  }
  local eval_expr="${1:-''}" # default to *quoted* empty string if it was empty or unset
  if shift; then
    cmd_eval "__cmd_eval_log $(cmd_escape "$eval_expr") && $eval_expr" "$@"
    unset __cmd_eval_log
  else
    cmd_log "$cmd_command: no expression provided"
    return 6
  fi
}

function cmd_list {
  cmd_split ':' <<< "$CMD_ROOTS" |
    while read -r root; do
      cmd_log "# $root"
      find "${root}" -name "*$CMD_SUFFIX" |
       while read -r script; do
         local script_without_root="${script#$root/}"
         echo "${script_without_root%$CMD_SUFFIX}"
       done |
       sort
    done
}

function cmd_run {
  cmd_eval 'source "$cmd_script"' "$@"
}

if [ "$#" -eq 0 ]; then
  cmd_log "cmd is a tool for finding and running commands."
  cmd_log "Usage: $cmd_command <command> [args]"
  cmd_log "Runs <root>/<command>.cmd, where <root> is a member of the set configured in env var CMD_ROOTS as ':'-separated paths."
  exit 1
fi
opt="$1"
case "$opt" in
  --eval*)
    # Instead of evaluating the resolved script (cmd_script), evaluate the provided expression.
    eval_expr=${opt#--eval=} # contains expr if it was glued using '=', otherwise $opt.
    shift # consume '--eval', whether expr is glued or not
    if [ "$eval_expr" = "$opt" ]; then
      cmd_eval_logged "$@" # expr was not glued
    else
      cmd_eval_logged "$eval_expr" "$@" # unglue expr
    fi
    ;;
  --which)
    shift
    cmd_eval 'echo "$cmd_script"' "$@"
    ;;
  --cat)
    shift
    cmd_eval 'cat "$cmd_script"' "$@"
    ;;
  --edit)
    shift
    cmd_eval 'vim "$cmd_script"' "$@"
    ;;
  --list)
    cmd_list
    ;;
  *)
    cmd_run "$@"
    ;;
esac
