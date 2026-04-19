#!/usr/bin/env bash

set -euo pipefail

CMD_ROOTS="${CMD_ROOTS-.}" # must have at most 255 elements
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
  local cmd_include_path="$1"
  _cmd_validate_include_path "$cmd_include_path" || return
  local cmd_included_file="$cmd_dir/$cmd_include_path$CMD_SUFFIX"
  shift
  # Note that both 'cmd_include_path' and 'cmd_included_file' leak into the included file.
  # Though not necessarily particularly useful, they could be handy for detecting that the file is being included
  # and/or infer where it was included from (e.g. for debugging).
  source "$cmd_included_file"
}

function cmd_ask {
  # args: var [prompt]
  # Output ("reply") the contents of var `$var`, or if it's unset, prompts the user for the contents.
  local var="$1"
  local prompt="${2-"$var:"}"
  if [ -z "${!var+x}" ]; then
    local r
    read -erp "$prompt " r
    echo "$r"
  else
    echo "${!var}"
  fi
}

function cmd_confirm {
  # args: [prompt]
  # Offer the user the chance to interrupt the script (with SIGINT) unless CMD_CONFIRM is set.
  # Any user intput is discarded.
  local prompt="${1-"Press ENTER to continue or ^C to cancel"}"
  cmd_ask CMD_CONFIRM "$prompt" >/dev/null
}

# VALIDATION #

function _cmd_validate_path_from_root {
  # args: path_from_root
  local path_from_root="$1"
  if [ -z "$path_from_root" ]; then
    cmd_log "$cmd_command: command required"
    return 5
  fi
  # Require path to be "simple" (relative and strictly descending) as we're conceptually navigating a command tree, not the filesystem.
  # This is the same check as in _cmd_validate_include_path except that we also reject '..'.
  case "/$path_from_root/" in
    *//*|*/./*|*/../*)
      cmd_log "$cmd_command: invalid command path \"$path_from_root\""
      return 7
      ;;
  esac
}

function _cmd_validate_include_path {
  # args: include_path
  # Reject path components '' and '.' (includes absolute paths).
  # This is the same check as in _cmd_validate_path_from_root except that we don't reject '..'.
  local include_path="$1"
  case "/$include_path/" in
    *//*|*/./*)
      cmd_log "$cmd_command: invalid include path \"$include_path\""
      return 7
      ;;
  esac
}

# RESOLVER #

CMD_SUFFIX='.cmd'

function _cmd_echo_root_run_script {
  # args: root path_from_root, cmd_args...
  local root="$1"
  local path_from_root="$2"
  if shift 2; then
    echo "cmd_root=$(cmd_escape "$root") cmd_file=$(cmd_escape "$root/$path_from_root$CMD_SUFFIX") \$func $(cmd_escape "$@")"
  fi
}

function _cmd_filter_run_scripts_by_existence {
  # input: sequence of run scripts
  # output: run scripts corresponding to files that exist (one per line)
  # Returns number of output lines - not error code! - silently assuming that to be at most 255.
  local run_script f res=0
  while read -r run_script; do
    f="$(func='__cmd_echo_var cmd_file' eval "$run_script")"
    if [ -e "$f" ]; then
      echo "$run_script"
      res=$((res+1))
    fi
  done
  return $res
}

function _cmd_echo_unique_run_script {
  # args: path_from_root
  # input: sequence of run scripts
  local path_from_root="$1"
  local run_scripts count=0
  run_scripts=$(_cmd_filter_run_scripts_by_existence) || count=$?
  case "$count" in
    0)
      cmd_log "$cmd_command: command \"$path_from_root\" not found"
      return 1
      ;;
    1)
      echo "$run_scripts"
      ;;
    *)
      local files_joined="$(func='__cmd_echo_var cmd_file' eval "$run_scripts" | cmd_join ', ')"
      cmd_log "$cmd_command: ambiguous command (matched: $files_joined)"
      return 2
      ;;
  esac
}

# RUN #

function cmd_eval {
  # args: __cmd_eval_expr, [path_from_root], [cmd_args...]
  local __cmd_eval_expr="$1"
  shift
  local cmd_file=
  if [ "$#" -eq 0 ]; then
    __cmd_eval
  elif [ "$1" = '--' ]; then
    # Allow passing argument to eval expr by starting with '--'.
    shift
    __cmd_eval "$@"
  else
    local path_from_root="$1"
    shift
    _cmd_validate_path_from_root "$path_from_root" || return
    local roots unique_run_script
    _cmd_roots_to_array "$CMD_ROOTS" roots
    unique_run_script="$(
      for r in "${roots[@]}"; do
        _cmd_echo_root_run_script "$r" "$path_from_root" "$@"
      done |
      _cmd_echo_unique_run_script "$path_from_root"
    )"
    func=__cmd_eval eval "$unique_run_script"
  fi
}

function _cmd_roots_to_array {
  # args: array, roots (not extracting vars to avoid collisions with input var)
  IFS=":" read -ra "$2" <<< "$1"
}

function __cmd_eval {
  # args: cmd_args...
  # scope: __cmd_eval_expr, cmd_root, cmd_file, ...
  local cmd_dir="$(dirname "$cmd_file")" # provides cmd_dir to __cmd_eval_expr
  # Wrapping 'eval' in __cmd_eval_wrap to let 'return' stmts in $__cmd_eval_expr make that func return instead of this one.
  # Note that `||` disables errexit (-e) within the evaluated expression.
  local cmd_exit_code=0
  __cmd_eval_wrap "$@" || cmd_exit_code=$?
  if [ "$cmd_exit_code" -ne 0 ]; then
    cmd_log "$cmd_command: eval of expression \`$__cmd_eval_expr\` failed with exit code $cmd_exit_code"
    return 4
  fi
}

function __cmd_eval_wrap {
  # args: cmd_args...
  # scope: __cmd_eval_expr, cmd_root, cmd_file, ...
  # Eval user-provided expression. Everything in scope is inherited, including args (accessible as "$@").
  eval "$__cmd_eval_expr"
}

function _cmd_log_file {
  # scope: cmd_file
  if [ "$cmd_file" ]; then cmd_log "# [$cmd_file]"; fi
}

function cmd_eval_logged {
  # args: __cmd_eval_expr, path_from_root, cmd_args...
  local __cmd_eval_expr="${1:-''}" # default to *quoted* empty string if it was empty or unset
  if shift; then
    # Prevent logging to $__cmd_eval_expr
    cmd_eval "__cmd_eval_log $(cmd_escape "$__cmd_eval_expr") && $__cmd_eval_expr" "$@"
  else
    cmd_log "$cmd_command: no expression provided"
    return 6
  fi
}

function __cmd_eval_log {
  # caller: cmd_eval_logged (via cmd_eval)
  # args: __cmd_eval_expr
  # scope: cmd_file, ...
  local __cmd_eval_expr="$1"
  _cmd_log_file
  cmd_log "> $__cmd_eval_expr"
}

function cmd_list {
  local root file
  cmd_split ':' <<< "$CMD_ROOTS" |
    while read -r root; do
      cmd_log "# $root"
      find "${root}" -name "*$CMD_SUFFIX" |
       while read -r file; do
         local file_without_root="${file#$root/}"
         echo "${file_without_root%$CMD_SUFFIX}"
       done |
       sort
    done
}

CMD_SHELL_PROMPT='> '
CMD_SHELL_PROMPT_EXPANDED="${CMD_SHELL_PROMPT//?/ }$CMD_SHELL_PROMPT" # prompt replaced by spaces followed by prompt

function cmd_shell {
  # args: path_from_root, cmd_args...
  # __cmd_eval_wrap doesn't automatically propagate args to commands.
  cmd_eval '__cmd_shell "$@"' "$@"
}

function __cmd_shell {
  # caller: cmd_shell (via cmd_eval)
  # scope: cmd_file, ...
  _cmd_log_file
  local expr
  while read -erp "$CMD_SHELL_PROMPT" expr; do
    if [ "$expr" = '.' ]; then
      if [ "$cmd_file" ]; then
        # Shortcut for loading the command.
        expr='source $cmd_file'
        cmd_log "$CMD_SHELL_PROMPT_EXPANDED$expr"
      else
        cmd_log "$cmd_command: no command file in scope"
        continue
      fi
    fi
    # Although `set -e` is set globally, eval failures don't crash the script here for reasons explained in __cmd_eval.
    # Reading nonexistent variables still do - we should probably fix that at some point.
    eval "$expr"
  done
}

function cmd_run {
  cmd_eval 'source "$cmd_file"' "$@"
}

function cmd_edit_or_create {
  # args: path_from_root
  local path_from_root="$1"
  _cmd_validate_path_from_root "$path_from_root" || return
  # TODO: If no path provided, list all and allow user to select which one to edit? Or does is that an autocompletion thing?
  local roots run_scripts
  _cmd_roots_to_array "$CMD_ROOTS" roots
  run_scripts="$(for r in "${roots[@]}"; do _cmd_echo_root_run_script "$r" "$path_from_root"; done)"

  # Would be nice to be able to have _cmd_filter_run_scripts_by_existence populate array in the style of `read`.
  # Unfortunately you cannot do that in ancient Bash without unforgivable hacks.
  # Also, "lists" (as in multi-line strings) may be eval'd all in one go!
  local run_scripts_existing count=0
  run_scripts_existing="$(_cmd_filter_run_scripts_by_existence <<< "$run_scripts")" || count=$?
  case "$count" in
    0)
      # no matches: create
      cmd_log "$cmd_command: command \"$path_from_root\" not found"
      cmd_log "$cmd_command: select root in which to create it or ^C to cancel"
      local PS3="Root: " root
      select root in "${roots[@]}"; do
        if [ "$root" ]; then break; fi
      done
      # Could filter $run_scripts by root, but now that we have root, it's easier to just regenerate the run script.
      local run_script="$(_cmd_echo_root_run_script "$root" "$path_from_root")"
      func=__cmd_create eval "$run_script"
      ;;
    1)
      # unique match: edit
      func=__cmd_edit eval "$run_scripts_existing"
      ;;
    *)
      # ambiguous match: error
      local files_joined="$(func='__cmd_echo_var cmd_file' eval "$run_scripts_existing" | cmd_join ', ')"
      cmd_log "$cmd_command: ambiguous command (matched: $files_joined)"
      return 2
      ;;
  esac
}

function __cmd_create {
  # caller: cmd_edit_or_create
  # scope: cmd_file, ...
  mkdir -p "$(dirname "$cmd_file")"
  cmd_template >> "$cmd_file"
  cmd_log "$cmd_command: appended template to file \"$cmd_file\""
  __cmd_edit
}

function __cmd_edit {
  # caller: cmd_edit_or_create
  # scope: cmd_file, ...
  cmd_log "$cmd_command: editing file \"$cmd_file\""
  vim "$cmd_file"
}

function cmd_template {
  echo "${CMD_TEMPLATE-"

# This script is intended to be run by cmd (https://github.com/bisgardo/cmd).
#
# Variables in scope:
#   \$@         - additional CLI arguments
#   \$cmd_root  - root directory (an entry of CMD_ROOTS)
#   \$cmd_file  - absolute path to this file
#   \$cmd_dir   - directory containing this file
#
# Functions in scope:
#   cmd_log <msg...>             - log to stderr
#   cmd_split <delim>            - split stdin into lines by delim
#   cmd_join <delim>             - join stdin lines by the delim
#   cmd_ask <var> [prompt]       - print contents of var if set, otherwise prompt user (doesn\'t modify var)
#   cmd_confirm [prompt]         - wait for user input unless \$CMD_CONFIRM is set
#   cmd_include <path> [args...] - source a .cmd file by relative command path
"}"
}

function __cmd_echo_var {
  # input: var
  echo "${!1}"
}

if [ "$#" -eq 0 ]; then
  cmd_log "cmd is a tool for finding and running commands."
  cmd_log "Usage: $cmd_command <command> [args]"
  cmd_log "Runs <root>/<command>.cmd, where <root> is a member of the set configured in env var CMD_ROOTS as ':'-separated paths."
  exit 1
fi
__cmd_opt="$1"
case "$__cmd_opt" in
  --eval*)
    # Evaluate the provided expression.
    # If a command path is provided, the resolved file is exposed to the expression as 'cmd_file', but not sourced automatically.
    __cmd_eval_expr=${__cmd_opt#--eval=} # contains expr if it was glued using '=', otherwise $__cmd_opt.
    shift # consume '--eval', whether expr is glued or not
    if [ "$__cmd_eval_expr" = "$__cmd_opt" ]; then
      cmd_eval_logged "$@" # expr was not glued
    else
      cmd_eval_logged "$__cmd_eval_expr" "$@" # unglue expr
    fi
    ;;
  --which)
    shift
    cmd_eval 'echo "$cmd_file"' "$@" '' # additional empty arg forces cmd_eval to look up command
    ;;
  --cat)
    shift
    cmd_eval 'cat "$cmd_file"' "$@" '' # additional empty arg forces cmd_eval to look up command
    ;;
  --edit)
    shift
    cmd_edit_or_create "$@" ''
    ;;
  --shell)
    shift
    cmd_shell "$@"
    ;;
  --list)
    cmd_list
    ;;
  *)
    cmd_run "$@"
    ;;
esac
