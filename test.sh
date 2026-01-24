function cmd {
  CMD_ROOTS=testdata/root1:testdata/root2 ./cmd "$@"
}

function test_can_run {
  local out # must declare 'local' before assignment for exit code to propagate...
  out=$(cmd 2>&1)
  assertEquals 0 $?
  assertContains "$out" "cmd is a tool"
}

function test_can_run_hello {
  # Runs 'root1/hello.cmd'.
  local out
  out=$(cmd hello 2>&1)
  assertEquals 0 $?
  assertEquals "Hello, world!" "$out"
}

function test_can_run_nested_hello {
  # Runs 'root1/hello.cmd'.
  local out
  out=$(cmd nested/hello 2>&1)
  assertEquals 0 $?
  assertEquals "Hello, nested world!" "$out"
  out=$(cmd nested hello 2>&1)
  assertEquals 1 $?
  assertEquals "cmd: command \"nested\" not found" "$out"
}

function test_can_run_echo {
  # Runs 'root2/echo.cmd'.
  local out
  out=$(cmd echo hello echo 2>&1)
  assertEquals 0 $?
  assertEquals "hello echo" "$out"
}

function test_cannot_run_nonexistent {
  local out
  out=$(cmd nonexistent 2>&1)
  assertEquals 1 $?
  assertEquals "cmd: command \"nonexistent\" not found" "$out"
}

function test_cannot_run_ambiguous {
  local out
  out=$(CMD_ROOTS=testdata/root1:testdata/root1/nested ./cmd hello 2>&1)
  assertEquals 2 $?
  assertEquals "cmd: ambiguous command (matched: testdata/root1/hello.cmd, testdata/root1/nested/hello.cmd)" "$out"
}

function test_can_handle_quotes {
  # Runs `'/".cmd` - insane, but won't crash even on shit like this!
  out=$(CMD_ROOTS="testdata/'" ./cmd '"' 2>&1)
  assertEquals 0 $?
  assertEquals "I'm quoting!" "$out"
}

# ---

function oneTimeSetUp {
  ${__SHUNIT_CMD_ECHO_ESC} "${__shunit_ansi_cyan}Running tests in bash version ${BASH_VERSION}${__shunit_ansi_none}"
}

. ./lib/shunit2
