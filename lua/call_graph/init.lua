-- plugin.lua
local M = {
  opts = {
    reuse_buf = false,
    log_level = "info",
    hl_delay_ms =  200
  }
}
local log = require("call_graph.utils.log")
local incoming_caller = nil

local function create_user_cmd()
  vim.api.nvim_create_user_command(
    "CallGraph",
    function()
      if not M.opts.reuse_buf then
        require("call_graph.caller"):new(M.opts.hl_delay_ms):generate_call_graph()
      else
        if incoming_caller == nil then
          incoming_caller = require("call_graph.caller"):new(M.opts.hl_delay_ms)
        end
        incoming_caller = incoming_caller:reset_graph()
        incoming_caller:generate_call_graph()
      end
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

function M.setup(opts)
  -- setup logs
  if opts ~= nil and type(opts) == "table" then
    for k, v in pairs(opts) do
      M.opts[k] = v
    end
  end
  -- setup logs
  log.setup({ append = false, level = M.opts.log_level })
  -- create_hl_group
  create_hl_group()

  M.incoming_caller = require("call_graph.caller"):new()

  -- create the command
  create_user_cmd()
end

return M
