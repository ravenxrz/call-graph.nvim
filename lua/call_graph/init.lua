-- plugin.lua
local M = {}
local log = require("call_graph.utils.log")

local function create_user_cmd()
  vim.api.nvim_create_user_command(
    "CallGraph",
    function()
      require("call_graph.caller").generate_call_graph()
    end,
    { desc = "Generate call graph for current buffer" }
  )

  vim.api.nvim_create_user_command("CallGraphLog",
    function()
      vim.cmd(":e " .. log.config.filepath)
    end
    , { desc = "Open call graph log file" })
end

function M.setup()
  -- setup logs
  log.setup({ append = false, level = "debug" })
  -- create the command
  create_user_cmd()
end

return M
