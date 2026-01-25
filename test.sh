function cmd {
  CMD_ROOTS=testdata/root1:testdata/root2 ./cmd "$@"
}

function test_can_run {
  local out # must declare 'local' before assignment for exit code to propagate...
  out=$(cmd 2>&1)
  assertEquals 1 $?
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
  # Runs `'/".cmd` with some args that also contain quotes - insane, but we won't even let shit like this crash us!
  local out
  out=$(CMD_ROOTS="testdata/'" ./cmd '"' "Guns N' Roses" 'Terry "Geezer" Butler' 2>&1)
  assertEquals 0 $?
  assertEquals "I'm quoting Guns N' Roses, Terry \"Geezer\" Butler!" "$out"
}

function test_eval_env {
  local out
  out=$(cmd --eval 'echo cmd_root=$cmd_root cmd_script=$cmd_script' hello 2>/dev/null)
  assertEquals 0 $?
  assertEquals "cmd_root=testdata/root1 cmd_script=testdata/root1/hello.cmd" "$out"
}

function test_eval_echo_args {
  local out
  out=$(cmd --eval 'echo $@' hello a b c 2>/dev/null)
  assertEquals 0 $?
  assertEquals "a b c" "$out"
}

function test_eval_quoted {
  local out
  out=$(cmd --eval "echo 'x\"y'" hello 2>/dev/null)
  assertEquals 0 $?
  assertEquals 'x"y' "$out"
  out=$(cmd --eval="echo 'x\"y'" hello 2>/dev/null)
  assertEquals 0 $?
  assertEquals 'x"y' "$out"
}

function test_eval_quoted_unmatched {
  local out
  out=$(cmd --eval ec\'ho hello 2>&1)
  assertEquals 2 $? # exit code from bash: "incorrect use of builtin"
  assertContains "$out" "unexpected EOF while looking for matching \`'"
}

function test_stdin {
  local out
  out=$((echo the quick; echo lazy dog) | cmd wc 2>&1)
  assertEquals 0 $?
  assertEquals "        2         4        19" "$out"
  out=$((echo the quick; echo lazy dog) | cmd --eval wc hello 2>/dev/null)
  assertEquals 0 $?
  assertEquals "        2         4        19" "$out"
  out=$((echo the quick; echo lazy dog) | cmd --eval=wc hello 2>/dev/null)
  assertEquals 0 $?
  assertEquals "        2         4        19" "$out"
}

# ---

function oneTimeSetUp {
  ${__SHUNIT_CMD_ECHO_ESC} "${__shunit_ansi_cyan}Running tests in bash version ${BASH_VERSION}${__shunit_ansi_none}"
}

. ./lib/shunit2
