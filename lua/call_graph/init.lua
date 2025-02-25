-- plugin.lua
local M = {
  opts = {
    reuse_buf = false,
    log_level = "info",
    hl_delay_ms = 200,
    auto_toggle_hl = true,
    ref_call_max_depth = 4,
    export_mermaid_graph = false
  }
}
local Caller = require("call_graph.caller")
local log = require("call_graph.utils.log")


local function create_user_cmd()
  vim.api.nvim_create_user_command(
    "CallGraphI",
    function()
      Caller.generate_call_graph(M.opts, Caller.CallType.INCOMING_CALL)
    end,
    { desc = "Generate call graph using incoming call" }
  )
  vim.api.nvim_create_user_command(
    "CallGraphR",
    function()
      Caller.generate_call_graph(M.opts, Caller.CallType.REFERENCE_CALL)
    end,
    { desc = "Generate call graph using reference call" }
  )

  vim.api.nvim_create_user_command("CallGraphToggleReuseBuf", function()
    M.opts.reuse_buf = not M.opts.reuse_buf
    local switch = "on"
    if not M.opts.reuse_buf then
      switch = "off"
    end
    vim.notify(string.format("Call graph reuse buf is %s", switch), vim.log.levels.INFO)
  end, { desc = "Toggle reuse buf of call graph" })

  -- TODO(zhangxingrui): support auto highlighting switch
  -- vim.api.nvim_create_user_command("CallGraphToggleAutoHighlight", function()
  --   M.opts.auto_toggle_hl = not M.opts.auto_toggle_hl
  --   local switch = "on"
  --   if not M.opts.auto_toggle_hl then
  --     switch = "off"
  --   end
  --   vim.notify(string.format("Call graph auto hl is %s", switch), vim.log.levels.INFO)
  -- end, { desc = "Toggle highlighting of call graph" })

  vim.api.nvim_create_user_command("CallGraphLog",
    function()
      vim.cmd(":e " .. log.config.filepath)
    end
    , { desc = "Open call graph log file" })
end

local function setup_hl()
  vim.api.nvim_set_hl(0, "CallGraphLine", { link = "Search" })
end


function M.setup(opts)
  -- setup opts
  if opts ~= nil and type(opts) == "table" then
    for k, v in pairs(opts) do
      M.opts[k] = v
    end
  end
  -- setup logs
  log.setup({ append = false, level = M.opts.log_level })
  setup_hl()
  create_user_cmd()
end

return M
