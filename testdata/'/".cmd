echo "I'm quoting $(for a in "$@"; do echo "$a"; done | cmd_join ", ")!"
