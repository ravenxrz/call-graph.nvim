-- plugin.lua
local M = {}
local log = require("call_graph.utils.log")

local function create_user_cmd()
  vim.api.nvim_create_user_command(
    "CallGraph",
    function()
      local incoming_caller = require("call_graph.caller"):new()
      incoming_caller:generate_call_graph()
    end,
    { desc = "Generate call graph for current buffer" }
  )

  vim.api.nvim_create_user_command("CallGraphLog",
    function()
      vim.cmd(":e " .. log.config.filepath)
    end
    , { desc = "Open call graph log file" })
end

local function create_hl_group()
  vim.api.nvim_command('highlight MyHighlight guifg=#ff0000 guibg=#000000 gui=bold')
end

function M.setup()
  -- setup logs
  log.setup({ append = false, level = "info" })
  -- create_hl_group
  create_hl_group()
  -- create the command
  create_user_cmd()
end

return M
