-- plugin.lua
local M = {}

function M._create_user_cmd()
  vim.api.nvim_create_user_command(
    "CallGraph",
    function()
      require("call_graph.caller").generate_call_graph()
    end,
    { desc = "Generate call graph for current buffer" }
  )
end

function M.setup()
  M._create_user_cmd()
end


M.setup()

return M
