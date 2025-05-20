TESTS_INIT=tests/minimal_init.lua
TESTS_DIR=tests/
TEST_FILES_DIR=tests/call_graph

.PHONY: test

test:
	@set -e; \
	for test_file in $$(find ${TEST_FILES_DIR} -name "*_spec.lua" -type f); do \
		nvim \
			--headless \
			--noplugin \
			-u ${TESTS_INIT} \
			-c "lua  local success = pcall(function() require('plenary.busted').run('$$test_file', { minimal_init = '${TESTS_INIT}' }) end); vim.cmd('quit!'); os.exit(success and 0 or 1)"; \
		if [ $$? -ne 0 ]; then \
			echo "Test failed: $$test_file"; \
			exit 1; \
		fi; \
	done

