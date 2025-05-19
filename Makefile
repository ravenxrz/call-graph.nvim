TESTS_INIT=tests/minimal_init.lua
TESTS_DIR=tests/

.PHONY: test

test:
	@echo "Starting tests..."
	@nvim \
		--headless \
		--noplugin \
		-u ${TESTS_INIT} \
		-c "lua vim.g.debug_plenary = true" \
		-c "lua print('Loading Plenary...')" \
		-c "PlenaryBustedDirectory ${TESTS_DIR} { minimal_init = '${TESTS_INIT}', sequential = true, timeout = 10000 }"
	@echo "Tests completed, exit code: $$?"
