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
  local path_from_including="$1"
  # Reject path components '' and '.' (includes absolute paths).
  # This is the same check as in _cmd_echo_unique_run_script except that we don't reject '..'.
  case "/$path_from_including/" in
    *//*|*/./*)
      cmd_log "$cmd_command: invalid include path \"$path_from_including\""
      return 7
      ;;
  esac
  local cmd_included_file="$cmd_dir/$path_from_including$CMD_SUFFIX"
  shift
  # Note that both 'path_from_including' and 'cmd_included_file' leak into the included file.
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

# RESOLVER #

CMD_SUFFIX='.cmd'

function _cmd_echo_root_run_script {
  # args: root path_from_root, cmd_args...
  local root="$1"
  local path_from_root="$2"
  if shift 2; then
    local cmd_file="$root/$path_from_root$CMD_SUFFIX"
    if [ -e "$cmd_file" ]; then
      # Outputs script of the form `cmd_root=... cmd_file=root/p1/p2.cmd $func [args]`.
      echo "cmd_root=$(cmd_escape "$root") cmd_file=$(cmd_escape "$cmd_file") \$func $(cmd_escape "$@")"
    fi
  fi
}

# RUN #

function _cmd_echo_run_scripts {
  # args: path_from_root, cmd_args...
  # input: sequence of roots (consumed by 'cmd_split').
  local root
  cmd_split ':' |
    while read -r root; do
      _cmd_echo_root_run_script "$root" "$@"
    done
}

function _cmd_echo_unique_run_script {
  # args: path_from_root, cmd_args...
  # input: sequence of roots (consumed by '_cmd_echo_run_scripts').
  local path_from_root="$1"
  # Require path to be "simple" (relative and strictly descending) as we're conceptually navigating a command tree, not the filesystem.
  # This is the same check as in cmd_include except that we also reject '..'.
  case "/$path_from_root/" in
    *//*|*/./*|*/../*)
      cmd_log "$cmd_command: invalid command path \"$path_from_root\""
      return 7
      ;;
  esac
  local run_scripts=()
  local r
  while read -r r; do run_scripts+=("$r"); done <<< "$(_cmd_echo_run_scripts "$@")"
  if [ -z "$run_scripts" ]; then
    cmd_log "$cmd_command: command \"$path_from_root\" not found"
    return 1
  fi
  if [ "${#run_scripts[@]}" -gt 1 ]; then
    local files_joined=$(for r in "${run_scripts[@]}"; do func=__cmd_echo_file eval "$r"; done | cmd_join ', ')
    cmd_log "$cmd_command: ambiguous command (matched: $files_joined)"
    return 2
  fi
  echo "$run_scripts" # single-element-array
}

function __cmd_echo_file {
  # caller: _cmd_echo_unique_run_script (via $run_scripts[])
  # scope: cmd_root, cmd_file
  echo $cmd_file
}

function cmd_eval {
  # args: __cmd_eval_expr, path_from_root, cmd_args...
  local __cmd_eval_expr="$1"
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
}

function __cmd_eval {
  # args: cmd_args...
  # scope: __cmd_eval_expr, cmd_root, cmd_file, ...
  if [ "${cmd_file-}" ]; then
    # Convenience: expose $cmd_dir to script/expr in eval below.
    local cmd_dir="$(dirname "$cmd_file")"
  elif [[ "$__cmd_eval_expr" =~ '$cmd_file'|'$cmd_dir' ]]; then
    # Reject any expression that includes the substrings "$cmd_file" or "$cmd_dir" if it doesn't have a value.
    cmd_log "$cmd_command: command required"
    return 5
  fi
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
  # scope: cmd_file?
  if [ "${cmd_file-}" ]; then
    cmd_log "# [$cmd_file]"
  fi
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
  # scope: cmd_file?, ...
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
  # scope: cmd_file?, ...
  _cmd_log_file
  local expr
  while read -erp "$CMD_SHELL_PROMPT" expr; do
    if [ "$expr" = '.' ]; then
      if [ "${cmd_file-}" ]; then
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
    cmd_eval 'echo "$cmd_file"' "$@"
    ;;
  --cat)
    shift
    cmd_eval 'cat "$cmd_file"' "$@"
    ;;
  --edit)
    shift
    cmd_eval 'vim "$cmd_file"' "$@"
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
