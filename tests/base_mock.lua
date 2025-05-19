local M = {}

-- 用于追踪模拟函数调用的表
M.cmd_calls = {}
M.notify_calls = {}
M.select_calls = {}

-- 重置所有调用记录
function M.reset_calls()
  M.cmd_calls = {}
  M.notify_calls = {}
  M.select_calls = {}
end

-- 模拟 vim.cmd 函数
vim.cmd = function(command)
  table.insert(M.cmd_calls, command)
end

-- 模拟 vim.notify 函数
vim.notify = function(msg, level)
  table.insert(M.notify_calls, {
    msg = msg,
    level = level or vim.log.levels.INFO
  })
end

-- 模拟 vim.ui.select 函数
vim.ui = vim.ui or {}
vim.ui.select = function(items, opts, on_choice)
  table.insert(M.select_calls, {
    items = items,
    opts = opts
  })
  -- 默认选择第一个选项
  if on_choice and items and #items > 0 then
    on_choice(items[1], 1)
  end
end

-- 模拟 vim.api.nvim_buf_is_valid 函数
local original_buf_is_valid = vim.api.nvim_buf_is_valid
vim.api.nvim_buf_is_valid = function(bufnr)
  -- 对于测试中的特定缓冲区，返回已知结果
  if bufnr == 101 or bufnr == 202 then
    return true
  end
  -- 其他使用原始函数
  if original_buf_is_valid then
    return original_buf_is_valid(bufnr)
  end
  -- 默认对大于0的缓冲区返回true
  return bufnr > 0
end

-- 设置必要的 vim.log.levels
vim.log = vim.log or {}
vim.log.levels = vim.log.levels or {
  DEBUG = 0,
  INFO = 1,
  WARN = 2,
  ERROR = 3
}

return M 