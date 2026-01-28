function cmd {
  CMD_ROOTS='testdata/root1:testdata/root2:testdata/spaced root' ./cmd "$@"
}

function test_can_run {
  local out # must declare 'local' before assignment for exit code to propagate...
  out=$(cmd 2>&1)
  assertEquals 1 $?
  assertContains "$out" 'cmd is a tool'
}

function test_can_run_hello {
  # Runs 'root1/hello.cmd'.
  local out
  out=$(cmd hello 2>&1)
  assertEquals 0 $?
  assertEquals 'Hello, world!' "$out"
}

function test_can_run_nested_hello {
  # Runs 'root1/hello.cmd'.
  local out
  out=$(cmd nested/hello 2>&1)
  assertEquals 0 $?
  assertEquals 'Hello, nested world!' "$out"
  out=$(cmd nested hello 2>&1)
  assertEquals 1 $?
  assertEquals 'cmd: command "nested" not found' "$out"
}

function test_can_run_echo {
  # Runs 'root2/echo.cmd'.
  local out
  out=$(cmd echo hello echo 2>&1)
  assertEquals 0 $?
  assertEquals 'hello echo' "$out"
}

function test_cannot_run_nonexistent {
  local out
  out=$(cmd nonexistent 2>&1)
  assertEquals 1 $?
  assertEquals 'cmd: command "nonexistent" not found' "$out"
}

function test_cannot_run_ambiguous {
  local out
  out=$(CMD_ROOTS=testdata/root1:testdata/root1/nested ./cmd hello 2>&1)
  assertEquals 2 $?
  assertEquals 'cmd: ambiguous command (matched: testdata/root1/hello.cmd, testdata/root1/nested/hello.cmd)' "$out"
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
  out=$(cmd --eval 'echo cmd_root=$cmd_root cmd_script=$cmd_script cmd_dir=$cmd_dir' hello 2>/dev/null)
  assertEquals 0 $?
  assertEquals 'cmd_root=testdata/root1 cmd_script=testdata/root1/hello.cmd cmd_dir=testdata/root1' "$out"
  out=$(cmd --eval 'echo cmd_root=$cmd_root cmd_script=$cmd_script cmd_dir=$cmd_dir' nested/hello 2>/dev/null)
  assertEquals 0 $?
  assertEquals 'cmd_root=testdata/root1 cmd_script=testdata/root1/nested/hello.cmd cmd_dir=testdata/root1/nested' "$out"
}

function test_eval_echo_args {
  local out
  out=$(cmd --eval 'echo $@' hello a b c 2>/dev/null)
  assertEquals 0 $?
  assertEquals 'a b c' "$out"
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
  assertEquals 4 $?
  assertContains "$out" "unexpected EOF while looking for matching \`'"
  assertContains "$out" 'eval of expression'
  assertContains "$out" 'failed with exit code' # code 1 in Bash 3 and 4, code 2 in Bash 5
}

function test_eval_return_vs_exit {
  local out
  # Return from eval propagates immediately, bypassing custom error reporting.
  out=$(cmd --eval 'return 42' hello 2>&1)
  assertEquals 4 $?
  assertContains "$out" 'eval of expression'
  assertContains "$out" 'failed with exit code 42'
  # Hard exit from eval propagates immediately, bypassing custom error reporting.
  out=$(cmd --eval 'exit 42' hello 2>&1)
  assertEquals 42 $?
  assertEquals $'# [testdata/root1/hello.cmd]\n> exit 42' "$out" # process killed right away
  # Like above, just without "hello".
  out=$(cmd --eval 'return 42' 2>&1)
  assertEquals 4 $?
  assertContains "$out" 'eval of expression'
  assertContains "$out" 'failed with exit code 42'
  # Hard exit from eval propagates immediately, bypassing custom error reporting.
  out=$(cmd --eval 'exit 42' 2>&1)
  assertEquals 42 $?
  assertEquals $'> exit 42' "$out" # process killed right away
}

function test_cannot_eval_ambiguous {
  local out
  out=$(CMD_ROOTS=testdata/root1:testdata/root1/nested ./cmd --eval 'echo goodbye' hello 2>&1)
  assertEquals 2 $?
  assertEquals 'cmd: ambiguous command (matched: testdata/root1/hello.cmd, testdata/root1/nested/hello.cmd)' "$out"
}

function test_eval_without_command {
  # Run "eval" outside the context of a command.
  # Use case: access internal utility without having to create a .cmd file.
  local out
  out=$(cmd --eval 'cmd_split ,' <<< 'a,b,c' 2>&1)
  assertEquals 0 $?
  assertEquals $'> cmd_split ,\na\nb\nc' "$out"
  out=$(cmd --eval 'echo "$@"' -- x y z 2>&1)
  assertEquals 0 $?
  assertEquals $'> echo "$@"\nx y z' "$out"
}

function test_eval_can_assign_exit_code {
  local out
  out=$(cmd --eval 'cmd_exit_code=42' 2>&1)
  assertEquals 4 $?
  assertContains "$out" 'cmd: eval of expression'
  assertContains "$out" 'failed with exit code 42'
  out=$(cmd --eval 'cmd_exit_code=42; return 69' 2>&1)
  assertEquals 4 $?
  assertContains "$out" 'eval of expression'
  assertContains "$out" 'failed with exit code 69'
}

function test_eval_can_access_own_expression {
  # Internal, unstable, but incorrigibly, externally observable due to Bash scoping.
  local out
  out=$(cmd --eval 'echo $__cmd_eval_expr' 2>/dev/null)
  assertEquals 0 $?
  assertNotNull "$out"
}

function test_cannot_eval_without_expr {
  local out
  out=$(cmd --eval 2>&1)
  assertEquals 6 $?
  assertEquals 'cmd: no expression provided' "$out"
  out=$(cmd --eval= 2>&1)
  assertEquals 4 $?
  assertContains "$out" 'command not found'
  assertContains "$out" 'cmd: eval of expression'
  assertContains "$out" 'failed with exit code 127'
  out=$(cmd --eval '' 2>&1)
  assertEquals 4 $?
  assertContains "$out" 'command not found'
  assertContains "$out" 'cmd: eval of expression'
  assertContains "$out" 'failed with exit code 127'
  out=$(cmd --eval='' 2>&1)
  assertEquals 4 $?
  assertContains "$out" 'command not found'
  assertContains "$out" 'cmd: eval of expression'
  assertContains "$out" 'failed with exit code 127'
  out=$(cmd --eval '' hello 2>&1)
  assertEquals 4 $?
  assertContains "$out" 'command not found'
  assertContains "$out" 'cmd: eval of expression'
  assertContains "$out" 'failed with exit code 127'
}

function test_eval_requires_command_when_using_dependent_var {
  local out
  out=$(cmd --eval 'echo "$cmd_script"' 2>&1)
  assertEquals 5 $?
  assertEquals "cmd: command required" "$out"
  out=$(cmd --eval 'echo "$cmd_dir"' 2>&1)
  assertEquals 5 $?
  assertEquals "cmd: command required" "$out"
}

function test_stdin {
  # Runs command both using script and eval with stdin passed from cmd.
  local out
  out=$((echo the quick; echo lazy dog) | cmd wc 2>&1)
  assertEquals 0 $?
  assertEquals '2 4 19' "$(echo $out)" # let unquoted echo collapse whitespace to eliminate platform differences of `wc`
  out=$((echo the quick; echo lazy dog) | cmd --eval wc hello 2>/dev/null)
  assertEquals 0 $?
  assertEquals '2 4 19' "$(echo $out)"
  out=$((echo the quick; echo lazy dog) | cmd --eval=wc hello 2>/dev/null)
  assertEquals 0 $?
  assertEquals '2 4 19' "$(echo $out)"
}

function test_including {
  local out
  out=$(cmd including)
  assertEquals 0 $?
  assertEquals $'Hello from included!\nHello with love!\nHello from including!\nHello with prompts!\nHello, world!\nHello, world!' "$out"
}

function test_include_variable {
  local out
  # local variable 'cmd_script_included' leaks from 'cmd_include' into included script, but isn't in scope after include returns.
  out=$(CMD_ROOTS=./testdata/test_include_variable ./cmd including)
  assertEquals 0 $?
  assertEquals $'including.cmd (before include): cmd_script_included=\nincluded.cmd: cmd_script_included=./testdata/test_include_variable/included.cmd\nincluding.cmd (after include): cmd_script_included=' "$out"
}

function test_which {
  local out
  out=$(cmd --which hello 2>&1)
  assertEquals 0 $?
  assertEquals 'testdata/root1/hello.cmd' "$out"
  out=$(cmd --which 2>&1)
  assertEquals 5 $?
  assertEquals 'cmd: command required' "$out"
}

function test_cat {
  local out
  out=$(cmd --cat nested/hello 2>&1)
  assertEquals 0 $?
  assertEquals "echo 'Hello, nested world!'" "$out"
  out=$(cmd --cat 2>&1)
  assertEquals 5 $?
  assertEquals 'cmd: command required' "$out"
}

function test_shell {
  local out
  # Evaluate in shell: print cmd, then include other command by relative path.
  out=$((echo 'echo $cmd_script'; echo 'cmd_include nested/hello') | cmd --shell hello 2>/dev/null)
  assertEquals 0 $?
  assertEquals $'testdata/root1/hello.cmd\nHello, nested world!' "$out"
  # Same as above, but also verify log on stderr.
  out=$((echo 'echo $cmd_script'; echo 'cmd_include nested/hello') | cmd --shell hello 2>&1)
  assertEquals 0 $?
  assertEquals $'# [testdata/root1/hello.cmd]\ntestdata/root1/hello.cmd\nHello, nested world!' "$out"
  # Run other command by custom root (shows that values persist from one line to the next).
  out=$((echo 'CMD_ROOTS="testdata/root1/nested"'; echo 'cmd_run hello') | cmd --shell hello 2>/dev/null)
  assertEquals 0 $?
  assertEquals $'Hello, nested world!' "$out"
}

function test_shell_without_command {
  local out
  out=$((echo '.') | cmd --shell 2>&1)
  assertEquals 1 $?
  assertContains "$out" 'cmd_script: unbound variable'
  out=$((echo 'cmd_script=testdata/root1/hello.cmd'; echo '.') | cmd --shell 2>/dev/null)
  assertEquals 0 $?
  assertEquals 'Hello, world!' "$out"
}

function test_shell_in_shell {
  local out
  # Create new shell for 'nested/hello' from inside the shell for 'hello' using 'cmd_shell'.
  # Then show that '$cmd_dir' is evaluated from within the inner shell.
  out=$((echo 'cmd_shell nested/hello'; echo 'echo $cmd_dir') | cmd --shell hello 2>/dev/null)
  assertEquals 0 $?
  assertEquals 'testdata/root1/nested' "$out"
}

function test_list {
  local out
  out=$(cmd --list 2>&1)
  assertEquals 0 $?
  assertEquals $'# testdata/root1\nhello\nnested/hello\n# testdata/root2\necho\nwc\n# testdata/spaced root\nincluding' "$out"
}

# ---

function oneTimeSetUp {
  ${__SHUNIT_CMD_ECHO_ESC} "${__shunit_ansi_cyan}Running tests in bash version ${BASH_VERSION}${__shunit_ansi_none}"
}

. ./lib/shunit2
