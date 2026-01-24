function test_can_run {
  ./cmd
}

# ---

function oneTimeSetUp {
  ${__SHUNIT_CMD_ECHO_ESC} "${__shunit_ansi_cyan}Running tests in bash version ${BASH_VERSION}${__shunit_ansi_none}"
}

. ./lib/shunit2
