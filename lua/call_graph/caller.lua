-- caller.lua
local CallGraphData = require("call_graph.graph_data")
local CallGraphView = require("call_graph.graph_view")

local Caller = {}
Caller.__index = Caller

-- 用于存储之前生成的 caller 实例
local incoming_callers = {}

function Caller:new(hl_delay_ms, toogle_hl)
  local o = setmetatable({}, Caller)
  o.data = CallGraphData:new()
  o.view = CallGraphView:new(hl_delay_ms, toogle_hl)
  return o
end

---@param opts talbe
---             - hl_delay_ms number
---             - auto_toggle_hl boolean
---             - reuse_buf boolean
function Caller.generate_call_graph(opts)
  local caller
  if not opts.reuse then
    caller = Caller:new(opts.hl_delay_ms, opts.auto_toggle_hl)
  else
    if #incoming_callers == 0 then
      caller = Caller:new(opts.hl_delay_ms, opts.auto_toggle_hl)
    else
      caller = incoming_callers[#incoming_callers]
      caller.view:clear_view()
      caller.view.set_hl_delay_ms(opts.hl_delay_ms)
      caller.view.set_auto_toggle_hl(opts.auto_toggle_hl)
    end
  end

  local function on_graph_generated(root_node, nodes, edges)
    print("[CallGraph] graph data generated")
    caller.view:draw(root_node, nodes, edges)
  end
  table.insert(incoming_callers, caller)
  caller.data:generate_call_graph(on_graph_generated)
end

return Caller
