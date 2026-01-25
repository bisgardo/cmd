# cmd

CLI tool for resolving and running bash scripts with convenient utilities injected.

It works by defining a set of "root" directories that contain script files.
The script files must have extension `.cmd`, indicating that they aren't stand-alone, but might rely on injected utilities such as `cmd_log`.
The root set is configured as a `:`-separated list in the environment variable `CMD_ROOTS`.

## Usage

Consider the script file `fix.cmd` in folder `$HOME/cmds` which is included in `$CMD_ROOTS`, with contents:
```bash
cmd_log "fixed $@"
```

The command
```shell
cmd fix this and that
```
then invokes `$HOME/cmds/fix.cmd this and that`, outputting
```shell
fixed this and that
```

The command may also be nested in subfolders below the root. The command
```shell
cmd path/from/root args...
```
will then attempt to locate and run `path/from/root.cmd args...`, relative to some root.

The matched `.cmd` file must be unique; an error listing all matches will be reported otherwise.

## Install

Clone the repository

    git clone https://github.com/bisgardo/cmd.git

into some folder (can also just download `cmd`).

Let `<cmd-path>` be the path of the directory created by git.

Create a symbolic link from a dir that is already on `PATH`, to the directory `<cmd-path>` that contains the `cmd` executable, e.g.

    ln -s <cmd-path>/cmd ~/.local/bin/cmd

## Test

Unit tests are written using [shunit2](https://github.com/kward/shunit2) and are run directly using `./test.sh`,
which also contains the test cases.

The Makefile target `test` runs the tests locally
as well as against the latest versions of Bash version 3, 4, and 5, respectively (using Docker).

The Makefile variable `TEST` may be used to target a specific test (or space-separated list of tests).
For example, the command
```shell
make test TEST='test1 test2'
```
runs the tests named `test1` and `test2` locally and against all environments.

To run against only the Bash 3, for example, use target `test-bash3` instead of `test`.
Make also supports running an arbitrary list of targets if for some reason one wants to test against a subset of environments.
