-- plugin.lua
local M = {
  opts = {
    log_level = "info",
    hl_delay_ms = 200,
    auto_toggle_hl = true,
    in_call_max_depth = 4,
    ref_call_max_depth = 4,
    export_mermaid_graph = false,
    max_history_size = 20, -- Maximum number of graphs to keep in history
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

  vim.api.nvim_create_user_command("CallGraphLog", function()
    vim.cmd(":e " .. log.config.filepath)
  end, { desc = "Open call graph log file" })

  vim.api.nvim_create_user_command("CallGraphOpenMermaidGraph", function()
    Caller.open_mermaid_file()
  end, { desc = "Open call graph mermaid file" })

  vim.api.nvim_create_user_command("CallGraphOpenLastestGraph", function()
    Caller.open_latest_graph()
  end, { desc = "Open the most recently generated call graph" })

  vim.api.nvim_create_user_command("CallGraphHistory", function()
    Caller.show_graph_history()
  end, { desc = "Show and select from call graph history" })

  vim.api.nvim_create_user_command("CallGraphMarkNode", function()
    Caller.mark_node_under_cursor()
  end, { desc = "Mark/unmark the node under cursor (automatically starts mark mode if not active)" })

  vim.api.nvim_create_user_command("CallGraphMarkEnd", function()
    Caller.end_mark_mode_and_generate_subgraph()
  end, { desc = "End marking and generate subgraph from marked nodes" })
end

local function setup_hl()
  vim.api.nvim_set_hl(0, "CallGraphLine", { link = "Search" })
  vim.api.nvim_set_hl(0, "CallGraphMarkedNode", { link = "Visual" })
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
