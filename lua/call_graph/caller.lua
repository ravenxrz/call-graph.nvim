local ICallGraphData = require("call_graph.data.incoming_call_graph_data")
local RCallGraphData = require("call_graph.data.ref_call_graph_data")
local OutcomingCall = require("call_graph.data.outcoming_call_graph_data")
local CallGraphView = require("call_graph.view.graph_view")
local MermaidGraph = require("call_graph.view.mermaid_graph")
local log = require("call_graph.utils.log")

local Caller = {}

---@enum CallType
Caller.CallType = {
  _NO_CALl = 0,
  INCOMING_CALL = 1,
  REFERENCE_CALL = 2,
  OUTCOMING_CALL = 3,
}

Caller.__index = Caller

local g_caller = nil
local last_call_type = Caller.CallType._NO_CALl
local mermaid_path = ".call_graph.mermaid"

-- Graph history management
local graph_history = {}
local max_history_size = 20

--- Add a graph to history
---@param buf_id number The buffer ID of the graph
---@param root_node_name string The name of the root node
---@param call_type CallType The type of call graph
local function add_to_history(buf_id, root_node_name, call_type)
  table.insert(graph_history, 1, {
    buf_id = buf_id,
    root_node_name = root_node_name,
    call_type = call_type,
    timestamp = os.time()
  })
  
  -- Trim history if it exceeds max size
  if #graph_history > max_history_size then
    -- Remove the oldest entry (last in the array)
    table.remove(graph_history, #graph_history)
  end
end

--- Open the latest graph
function Caller.open_latest_graph()
  if #graph_history == 0 then
    vim.notify("[CallGraph] No graph history available", vim.log.levels.WARN)
    return
  end
  
  local latest = graph_history[1]
  if vim.api.nvim_buf_is_valid(latest.buf_id) then
    vim.cmd("buffer " .. latest.buf_id)
  else
    vim.notify("[CallGraph] Latest graph buffer is no longer valid", vim.log.levels.ERROR)
  end
end

--- Show graph history and let user select
function Caller.show_graph_history()
  if #graph_history == 0 then
    vim.notify("[CallGraph] No graph history available", vim.log.levels.WARN)
    return
  end

  local items = {}
  for i, entry in ipairs(graph_history) do
    local call_type_str = "Unknown"
    if entry.call_type == Caller.CallType.INCOMING_CALL then
      call_type_str = "Incoming"
    elseif entry.call_type == Caller.CallType.REFERENCE_CALL then
      call_type_str = "Reference"
    elseif entry.call_type == Caller.CallType.OUTCOMING_CALL then
      call_type_str = "Outcoming"
    end

    local time_str = os.date("%Y-%m-%d %H:%M:%S", entry.timestamp)
    table.insert(items, string.format("%d. [%s] %s (%s)", 
      i, call_type_str, entry.root_node_name, time_str))
  end

  vim.ui.select(items, {
    prompt = "Select a graph to open:",
    format_item = function(item) return item end,
  }, function(choice, idx)
    if idx then
      local entry = graph_history[idx]
      if vim.api.nvim_buf_is_valid(entry.buf_id) then
        vim.cmd("buffer " .. entry.buf_id)
      else
        vim.notify("[CallGraph] Selected graph buffer is no longer valid", vim.log.levels.ERROR)
      end
    end
  end)
end

--- Creates a new caller instance.
---@param data ICallGraphData|RCallGraphData|OutcomingCall The call graph data object.
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

function Caller.new_outcoming_call(hl_delay_ms, toogle_hl)
  local data = OutcomingCall:new()
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
---             - in_call_max_depth number
---             - ref_call_max_depth number
---             - export_mermaid_graph boolean
---@param call_type CallType, default is INCOMING_CALL
function Caller.generate_call_graph(opts, call_type, on_generated_callback)
  call_type = call_type or Caller.CallType.INCOMING_CALL
  local caller = Caller.get_caller(opts, call_type)
  if not caller then
    vim.notify(string.format("unsupported call type: %s", call_type), vim.log.levels.ERROR)
    return
  end

  log.debug("caller info:", vim.inspect(caller))

  local function on_graph_generated(root_node, nodes, edges)
    caller.view:draw(root_node, nodes, edges)
    local buf_id = caller.view.buf.bufid
    vim.notify("[CallGraph] graph generated", vim.log.levels.INFO)
    
    -- Add to history

    local root_node_name = root_node and root_node.text or "UnknownRoot"
    add_to_history(buf_id, root_node_name, call_type)
    
    -- Update mermaid file if export is enabled
    if opts.export_mermaid_graph then
      MermaidGraph.export(root_node, mermaid_path)
    end
    
    if on_generated_callback then
      on_generated_callback(buf_id, root_node_name)
    end
  end
  caller.data:generate_call_graph(on_graph_generated)
end

--- Gets or creates a caller instance based on the given options and call type.
---@param opts table
---             - hl_delay_ms number
---             - auto_toggle_hl boolean
---             - in_call_max_depth number
---             - ref_call_max_depth number
---@param call_type CallType
---@return Caller
function Caller.get_caller(opts, call_type)
  -- Create a new caller
  local caller = Caller.create_new_caller(opts, call_type)
  g_caller = caller
  last_call_type = call_type
  return caller
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
  elseif call_type == Caller.CallType.OUTCOMING_CALL then
    return Caller.new_outcoming_call(hl_delay_ms, auto_toggle_hl)
  else
    return nil
  end
end

return Caller
