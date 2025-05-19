local plenary_dir = os.getenv("PLENARY_DIR") or "/tmp/plenary.nvim"
local is_not_a_directory = vim.fn.isdirectory(plenary_dir) == 0
if is_not_a_directory then
  vim.fn.system({ "git", "clone", "https://github.com/nvim-lua/plenary.nvim", plenary_dir })
end

print("Initializing test environment...")
vim.opt.rtp:append(".")
vim.opt.rtp:append(plenary_dir)

vim.cmd("runtime plugin/plenary.vim")
require("plenary.busted")

-- Add JSON support
if not vim.json then
  print("Adding JSON support...")
  vim.json = {
    encode = function(obj)
      return vim.fn.json_encode(obj)
    end,
    decode = function(json_str)
      return vim.fn.json_decode(json_str)
    end,
  }
end

-- Global error handling
vim.on_error = function(err)
  print("Error caught during test: " .. tostring(err))
  print(debug.traceback())
end

-- Create exit hook to clean up all resources when testing ends
local cleanup_group = vim.api.nvim_create_augroup("CallGraphTestCleanup", { clear = true })
vim.api.nvim_create_autocmd("VimLeavePre", {
  group = cleanup_group,
  callback = function()
    print("Cleaning up test environment resources...")

    -- Clean up all autocommand groups
    local autogroups = vim.api.nvim_get_autocmds({})
    for _, autocmd in ipairs(autogroups) do
      if autocmd.group and autocmd.group_name and autocmd.group_name ~= "CallGraphTestCleanup" then
        pcall(vim.api.nvim_del_augroup_by_name, autocmd.group_name)
      end
    end

    -- Clean up all buffers
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end

    -- Clear any possible global state
    if package.loaded["call_graph.utils.events"] then
      local events = require("call_graph.utils.events")
      if events.bufs then
        events.bufs = {}
      end
    end

    print("Test environment cleanup completed")
    vim.cmd("qa!") -- Force quit Neovim
  end,
  once = true,
})

print("Test initialization completed")
