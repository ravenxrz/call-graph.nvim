TESTS_INIT=tests/minimal_init.lua
TESTS_DIR=tests/

.PHONY: test

test:
	@echo "启动测试..."
	@nvim \
		--headless \
		--noplugin \
		-u ${TESTS_INIT} \
		-c "lua vim.g.debug_plenary = true" \
		-c "lua print('加载Plenary...')" \
		-c "PlenaryBustedDirectory ${TESTS_DIR} { minimal_init = '${TESTS_INIT}', sequential = true, timeout = 10000 }"
	@echo "测试执行完成，退出码：$$?"
