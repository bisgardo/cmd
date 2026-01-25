.PHONY: test fetch-shunit2 test-local test-bash3 test-bash4 test-bash5

test: test-local test-bash3 test-bash4 test-bash5

fetch-shunit2:
	wget https://raw.githubusercontent.com/kward/shunit2/refs/tags/v2.1.8/shunit2 -O ./lib/shunit2

test-local:
	@bash ./test.sh -- $(TEST)

test-bash3: # Hardcoding Bash v3.2.57 specifically because that's the version that Macs are stuck on.
	@docker run --volume="$(CURDIR):/tmp" --workdir="/tmp" bash:3.2.57 ./test.sh -- $(TEST)
	@echo

test-bash4:
	@docker run --volume="$(CURDIR):/tmp" --workdir="/tmp" bash:4 ./test.sh -- $(TEST)
	@echo

test-bash5:
	@docker run --volume="$(CURDIR):/tmp" --workdir="/tmp" bash:5 ./test.sh -- $(TEST)
	@echo
