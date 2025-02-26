-- caller.lua
local ICallGraphData = require("call_graph.data.incoming_call_graph_data")
local RCallGraphData = require("call_graph.data.ref_call_graph_data")
local CallGraphView = require("call_graph.view.graph_view")
local MermaidGraph = require("call_graph.view.mermaid_graph")
local log = require("call_graph.utils.log")

local Caller = {
  ---@enum CallType
  CallType = {
    _NO_CALl = 0,
    INCOMING_CALL = 1,
    REFERENCE_CALL = 2
  }
}
Caller.__index = Caller

-- 用于存储之前生成的 caller 实例
local g_callers = {}
local last_call_type = Caller.CallType._NO_CALl

function Caller.new_incoming_call(hl_delay_ms, toogle_hl, max_depth)
  local o = setmetatable({}, Caller)
  o.data = ICallGraphData:new(max_depth)
  o.view = CallGraphView:new(hl_delay_ms, toogle_hl)
  return o
end

function Caller.new_ref_call(hl_delay_ms, toogle_hl, max_depth)
  local o = setmetatable({}, Caller)
  o.data = RCallGraphData:new(max_depth)
  o.view = CallGraphView:new(hl_delay_ms, toogle_hl)
  return o
end

---@param opts talbe
---             - hl_delay_ms number
---             - auto_toggle_hl boolean
---             - reuse_buf boolean
---@param call_type CallType, default is INCOMING_CALL
function Caller.generate_call_graph(opts, call_type)
  local function get_or_create_caller(new_func)
    local caller
    if not opts.reuse_buf or #g_callers == 0 or last_call_type ~= call_type then
      last_call_type = call_type
      g_callers = {}
      if call_type == Caller.CallType.REFERENCE_CALL then
        caller = new_func(opts.hl_delay_ms, opts.auto_toggle_hl, opts.ref_call_max_depth)
      else
        caller = new_func(opts.hl_delay_ms, opts.auto_toggle_hl, opts.in_call_max_depth)
      end
      if opts.reuse_buf then
        table.insert(g_callers, caller)
      end
    else
      caller = g_callers[#g_callers]
    end
    return caller
  end

  local caller
  if call_type == Caller.CallType.INCOMING_CALL then
    caller = get_or_create_caller(Caller.new_incoming_call)
  else
    if call_type == Caller.CallType.REFERENCE_CALL then
      caller = get_or_create_caller(Caller.new_ref_call)
    else
      vim.notify(string.format("unsupported call type", call_type), vim.log.levels.ERROR)
      return
    end
  end
  log.debug("caller info:", vim.inspect(caller))

  local function on_graph_generated(root_node, nodes, edges)
    caller.view:draw(root_node, nodes, edges)
    if opts.export_mermaid_graph then
      MermaidGraph.export(root_node, ".calL_grap.mermaid")
    end
    print("[CallGraph] graph generated")
  end
  caller.data:generate_call_graph(on_graph_generated, opts.reuse_buf)
end

return Caller
