-- plugin.lua
local M = {
  opts = {
    reuse_buf = false,
    log_level = "info",
    hl_delay_ms = 200,
    auto_toggle_hl = true
  },
  _auto_toggle_hl = true
}
local log = require("call_graph.utils.log")
local incoming_callers = {}

local function get_len(t)
  local len = 0
  for _, _ in pairs(t) do
    len = len + 1
  end
  return len
end

local function create_user_cmd()
  vim.api.nvim_create_user_command(
    "CallGraph",
    function()
      local function gen_graph_done_cb(bufnr, ctx)
        local caller = ctx
        incoming_callers[tostring(bufnr)] = caller
      end
      local caller
      if not M.opts.reuse_buf then
        caller = require("call_graph.caller"):new(M.opts.hl_delay_ms, M._auto_toggle_hl)
      else
        if get_len(incoming_callers) == 0 then
          caller = require("call_graph.caller"):new(M.opts.hl_delay_ms, M._auto_toggle_hl)
        else
          for _, c in pairs(incoming_callers) do
            caller = c
          end
          caller = caller:reset_graph() -- reset graph will keep hl_delay_ms and auto_toggle_hl attr
        end
      end
      caller.gen_graph_done = {
        cb = gen_graph_done_cb,
        cb_ctx = caller
      }
      caller:generate_call_graph()
    end,
    { desc = "Generate call graph for current buffer" }
  )

  vim.api.nvim_create_user_command("CallGraphToggleAutoHighlight", function()
    M._auto_toggle_hl = not M._auto_toggle_hl
    local switch = "on"
    if not M._auto_toggle_hl then
      switch = "off"
    end
    vim.notify(string.format("Call graph auto highlighting is %s", switch), vim.log.levels.INFO)
    for _, caller in pairs(incoming_callers) do
      caller:set_auto_toggle_hl(M._auto_toggle_hl)
    end
  end, { desc = "Toggle highlighting of call graph" })

  vim.api.nvim_create_user_command("CallGraphLog",
    function()
      vim.cmd(":e " .. log.config.filepath)
    end
    , { desc = "Open call graph log file" })
end

local function buf_del_cb(bufnr)
  log.debug("del buf", bufnr)
  incoming_callers[tostring(bufnr)] = nil -- remove caller
end

local function setup_hl()
  M._auto_toggle_hl = M.opts.auto_toggle_hl
  vim.api.nvim_command('highlight MyHighlight guifg=#ff0000 guibg=#000000 gui=bold')
end

local function setup_autocmd()
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, { -- 同时监听 BufDelete 和 BufWipeout 事件
    callback = function(event)
      buf_del_cb(event.buf)
    end,
  })
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
  -- create_hl_group
  setup_hl()
  -- create the command
  create_user_cmd()
  setup_autocmd()
end

return M
