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

cmd_list
