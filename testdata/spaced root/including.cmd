function hello_from {
    echo "Hello from $1!"
}

cmd_include ../included  # include using relative path (omitting '.cmd') - doesn't take CMD_ROOTS into account

hello_from including     # call function defined above
hello_with prompts       # call function defined in 'included.cmd'

cmd_run hello            # includes/runs 'root1/hello.cmd' (note that it belongs to another root)
hello_world              # call function defined in 'hello.cmd' (was also called by script itself)
