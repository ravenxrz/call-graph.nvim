local plenary_dir = os.getenv("PLENARY_DIR") or "/tmp/plenary.nvim"
local is_not_a_directory = vim.fn.isdirectory(plenary_dir) == 0
if is_not_a_directory then
  vim.fn.system({ "git", "clone", "https://github.com/nvim-lua/plenary.nvim", plenary_dir })
end

print("正在初始化测试环境...")
vim.opt.rtp:append(".")
vim.opt.rtp:append(plenary_dir)

vim.cmd("runtime plugin/plenary.vim")
require("plenary.busted")

-- 添加JSON支持
if not vim.json then
  print("添加 JSON 支持...")
  vim.json = {
    encode = function(obj)
      return vim.fn.json_encode(obj)
    end,
    decode = function(json_str)
      return vim.fn.json_decode(json_str)
    end,
  }
end

-- 全局错误处理
vim.on_error = function(err)
  print("测试过程中捕获到错误: " .. tostring(err))
  print(debug.traceback())
end

-- 创建退出钩子，在测试结束时清理所有资源
local cleanup_group = vim.api.nvim_create_augroup("CallGraphTestCleanup", { clear = true })
vim.api.nvim_create_autocmd("VimLeavePre", {
  group = cleanup_group,
  callback = function()
    print("正在清理测试环境资源...")

    -- 清理所有自动命令组
    local autogroups = vim.api.nvim_get_autocmds({})
    for _, autocmd in ipairs(autogroups) do
      if autocmd.group and autocmd.group_name and autocmd.group_name ~= "CallGraphTestCleanup" then
        pcall(vim.api.nvim_del_augroup_by_name, autocmd.group_name)
      end
    end

    -- 清理所有缓冲区
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end

    -- 清除任何可能的全局状态
    if package.loaded["call_graph.utils.events"] then
      local events = require("call_graph.utils.events")
      if events.bufs then
        events.bufs = {}
      end
    end

    print("测试环境资源清理完成")
    vim.cmd("qa!") -- 强制退出 Neovim
  end,
  once = true,
})

print("测试初始化完成")
