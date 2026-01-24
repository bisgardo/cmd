function cmd {
  CMD_ROOTS=testdata/root1:testdata/root2 ./cmd "$@"
}

function test_can_run_hello {
  # Runs 'root1/hello.cmd'.
  local out=$(cmd hello)
  assertEquals "Hello, world!" "$out"
}

function test_can_run_nested_hello {
  # Runs 'root1/hello.cmd'.
  local out1=$(cmd nested/hello)
  assertEquals "Hello, nested world!" "$out1"
  local out2=$(cmd nested hello)
  assertEquals "Hello, nested world!" "$out2"
}

function test_can_run_echo {
  # Runs 'root2/echo.cmd'.
  local out=$(cmd echo hello echo)
  assertEquals "hello echo" "$out"
}

# ---

function oneTimeSetUp {
  ${__SHUNIT_CMD_ECHO_ESC} "${__shunit_ansi_cyan}Running tests in bash version ${BASH_VERSION}${__shunit_ansi_none}"
}

. ./lib/shunit2
