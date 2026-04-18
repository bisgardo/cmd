CMD_SHELL_PROMPT='> '
CMD_SHELL_PROMPT_EXPANDED="${CMD_SHELL_PROMPT//?/ }$CMD_SHELL_PROMPT" # prompt replaced by spaces followed by prompt

function cmd_shell {
  cmd_eval '__cmd_shell "$@"' "$@"
}

function __cmd_shell {
  # caller: cmd_shell (via cmd_eval)
  # scope: cmd_script?, ...
  _cmd_log_script
  local expr
  while read -erp "$CMD_SHELL_PROMPT" expr; do
    if [ "$expr" = '.' ]; then
      if [ -z "${cmd_script-}" ]; then
        expr='echo No script in context'
      else
        # Shortcut for loading the command.
        expr='source $cmd_script'
        cmd_log "$CMD_SHELL_PROMPT_EXPANDED$expr"
      fi
    fi
    eval "$expr" || true
  done
}

function _cmd_log_script {
  # scope: cmd_script?
  if [ "${cmd_script-}" ]; then
    cmd_log "# [$cmd_script]"
  fi
}

# Clear 'cmd_script' to prevent execution against ourself if no args were provided.
cmd_script= cmd_shell "$@"
