-- plugin.lua
local M = {
  opts = {
    reuse_buf = false,
    log_level = "info",
    hl_delay_ms = 200,
    auto_toggle_hl = true,
    in_call_max_depth = 4,
    ref_call_max_depth = 4,
    export_mermaid_graph = false,
  },
}
local Caller = require("call_graph.caller")
local log = require("call_graph.utils.log")

local function create_user_cmd()
  vim.api.nvim_create_user_command("CallGraphI", function()
    local opts = vim.deepcopy(M.opts)
    if args ~= nil and args.args ~= "" then
      local a = args.args
      assert(tonumber(a), "arg must be a number")
      opts.in_call_max_depth = tonumber(a)
    end
    Caller.generate_call_graph(M.opts, Caller.CallType.INCOMING_CALL)
  end, { desc = "Generate call graph using incoming call", nargs = "?" })

  vim.api.nvim_create_user_command("CallGraphR", function(args)
    local opts = vim.deepcopy(M.opts)
    if args ~= nil and args.args ~= "" then
      local a = args.args
      assert(tonumber(a), "arg must be a number")
      opts.ref_call_max_depth = tonumber(a)
    end
    Caller.generate_call_graph(opts, Caller.CallType.REFERENCE_CALL)
  end, { desc = "Generate call graph using reference call", nargs = "?" })

  vim.api.nvim_create_user_command("CallGraphO", function()
    local opts = vim.deepcopy(M.opts)
    Caller.generate_call_graph(opts, Caller.CallType.OUTCOMING_CALL)
  end, { desc = "Generate call graph using outcoming call" })

  vim.api.nvim_create_user_command("CallGraphToggleReuseBuf", function()
    M.opts.reuse_buf = not M.opts.reuse_buf
    local switch = "on"
    if not M.opts.reuse_buf then
      switch = "off"
    end
    vim.notify(string.format("Call graph reuse buf is %s", switch), vim.log.levels.INFO)
  end, { desc = "Toggle reuse buf of call graph" })

  vim.api.nvim_create_user_command("CallGraphLog", function()
    vim.cmd(":e " .. log.config.filepath)
  end, { desc = "Open call graph log file" })

  vim.api.nvim_create_user_command("CallGraphOpenMermaidGraph", function()
    Caller.open_mermaid_file()
  end, { desc = "Open call graph mermaid file" })
end

local function setup_hl()
  vim.api.nvim_set_hl(0, "CallGraphLine", { link = "Search" })
end

function M.is_reuse_buf()
  return M.opts.reuse_buf
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
