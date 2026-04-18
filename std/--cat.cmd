# Clear 'cmd_script' to prevent execution against ourself if no args were provided.
cmd_script= cmd_eval 'cat "$cmd_script"' "$@"
