local ICallGraphData = require("call_graph.data.incoming_call_graph_data")
local RCallGraphData = require("call_graph.data.ref_call_graph_data")
local CallGraphView = require("call_graph.view.graph_view")
local MermaidGraph = require("call_graph.view.mermaid_graph")
local log = require("call_graph.utils.log")

local Caller = {}

---@enum CallType
Caller.CallType = {
  _NO_CALl = 0,
  INCOMING_CALL = 1,
  REFERENCE_CALL = 2,
}

Caller.__index = Caller

local g_caller = nil
local last_call_type = Caller.CallType._NO_CALl
local last_buf_id = -1
local mermaid_path = ".call_graph.mermaid"

--- Creates a new caller instance.
---@param data ICallGraphData|RCallGraphData The call graph data object.
---@param view CallGraphView The call graph view object.
---@return Caller The new caller instance.
local function create_caller(data, view)
  local o = setmetatable({}, Caller)
  o.data = data
  o.view = view
  return o
end

function Caller.new_incoming_call(hl_delay_ms, toogle_hl, max_depth)
  local data = ICallGraphData:new(max_depth)
  local view = CallGraphView:new(hl_delay_ms, toogle_hl)
  return create_caller(data, view)
end

function Caller.new_ref_call(hl_delay_ms, toogle_hl, max_depth)
  local data = RCallGraphData:new(max_depth)
  local view = CallGraphView:new(hl_delay_ms, toogle_hl)
  return create_caller(data, view)
end

function Caller.open_mermaid_file()
  vim.cmd(":e " .. mermaid_path)
end

--- Generates a call graph.
---@param opts table
---             - hl_delay_ms number
---             - auto_toggle_hl boolean
---             - reuse_buf boolean
---             - in_call_max_depth number
---             - ref_call_max_depth number
---             - export_mermaid_graph boolean
---@param call_type CallType, default is INCOMING_CALL
function Caller.generate_call_graph(opts, call_type)
  call_type = call_type or Caller.CallType.INCOMING_CALL

  local caller = Caller.get_caller(opts, call_type)

  if not caller then
    vim.notify(string.format("unsupported call type: %s", call_type), vim.log.levels.ERROR)
    return
  end

  log.debug("caller info:", vim.inspect(caller))

  local function on_graph_generated(root_node)
    last_buf_id = caller.view:draw(root_node, opts.reuse_buf)

    if opts.export_mermaid_graph then
      MermaidGraph.export(root_node, mermaid_path)
    end

    print("[CallGraph] graph generated")
  end

  caller.data:generate_call_graph(on_graph_generated, opts.reuse_buf)
end

--- Gets or creates a caller instance based on the given options and call type.
---@param opts table
---             - hl_delay_ms number
---             - auto_toggle_hl boolean
---             - reuse_buf boolean
---             - in_call_max_depth number
---             - ref_call_max_depth number
---@param call_type CallType
---@return Caller
function Caller.get_caller(opts, call_type)
  if opts.reuse_buf and g_caller and last_call_type == call_type then
    return g_caller
  else
    local view = nil
    if opts.reuse_buf and g_caller then
      view = g_caller.view
      if last_buf_id ~= -1 then
        view:reuse_buf(last_buf_id)
      end
    end
    -- Create a new caller
    local caller = Caller.create_new_caller(opts, call_type)
    if view then
      caller.view = view -- restore view state
    end

    g_caller = caller
    last_call_type = call_type
    return caller
  end
end

--- Creates a new caller instance based on the call type.
---@param opts table
---             - hl_delay_ms number
---             - auto_toggle_hl boolean
---             - in_call_max_depth number
---             - ref_call_max_depth number
---@param call_type CallType
---@return Caller
function Caller.create_new_caller(opts, call_type)
  local hl_delay_ms = opts.hl_delay_ms
  local auto_toggle_hl = opts.auto_toggle_hl

  if call_type == Caller.CallType.INCOMING_CALL then
    local max_depth = opts.in_call_max_depth
    return Caller.new_incoming_call(hl_delay_ms, auto_toggle_hl, max_depth)
  elseif call_type == Caller.CallType.REFERENCE_CALL then
    local max_depth = opts.ref_call_max_depth
    return Caller.new_ref_call(hl_delay_ms, auto_toggle_hl, max_depth)
  else
    return nil
  end
end

return Caller
