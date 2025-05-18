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
  SUBGRAPH_CALL = 4, -- New call type for subgraphs
}

Caller.__index = Caller

local g_caller = nil
local last_call_type = Caller.CallType._NO_CALl
local mermaid_path = ".call_graph.mermaid"

-- Graph history management
local graph_history = {}
local max_history_size = 20

-- Mark mode state
local is_mark_mode_active = false
local marked_node_ids = {} -- Stores nodeid of marked nodes
local current_graph_nodes_for_marking = nil -- Stores the 'nodes' table of the current graph
local current_graph_edges_for_marking = nil -- Stores the 'edges' table of the current graph
local current_graph_view_for_marking = nil -- Stores the view of the current graph being marked

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
    elseif entry.call_type == Caller.CallType.SUBGRAPH_CALL then
      call_type_str = "Subgraph" -- Display name for subgraph
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
    log.debug("graph generated, ", vim.inspect(nodes))
    caller.view:draw(root_node, nodes, edges)
    local buf_id = caller.view.buf.bufid
    vim.notify("[CallGraph] graph generated", vim.log.levels.INFO)
    
    -- Store graph data for potential marking mode
    -- This might be problematic if multiple graphs are generated without entering mark mode
    -- current_graph_nodes_for_marking = nodes 
    -- current_graph_edges_for_marking = edges
    -- current_graph_view_for_marking = caller.view

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

-- Mark Mode Functions
function Caller.start_mark_mode()
  if not g_caller or not g_caller.view or not g_caller.view.buf or not vim.api.nvim_buf_is_valid(g_caller.view.buf.bufid) then
    vim.notify("[CallGraph] No active call graph to mark.", vim.log.levels.WARN)
    return
  end

  -- Check if the current buffer is the one managed by g_caller.view
  if vim.api.nvim_get_current_buf() ~= g_caller.view.buf.bufid then
     vim.notify("[CallGraph] Mark mode must be started from an active call graph window.", vim.log.levels.WARN)
     return
  end

  is_mark_mode_active = true
  marked_node_ids = {}
  
  log.debug("[CG-DEBUG] Starting mark mode")
  log.debug("[CG-DEBUG] Getting graph data from view")
  
  if g_caller.view.get_drawn_graph_data then
      local graph_data = g_caller.view:get_drawn_graph_data()
      log.debug("[CG-DEBUG] Got graph data from view:")
      log.debug("[CG-DEBUG] Nodes: ", vim.inspect(graph_data.nodes))
      log.debug("[CG-DEBUG] Edges: ", vim.inspect(graph_data.edges))
      
      current_graph_nodes_for_marking = graph_data.nodes
      current_graph_edges_for_marking = graph_data.edges
  else
      log.warn("[CG-DEBUG] GraphView does not have get_drawn_graph_data. Attempting to use data from g_caller.data")
      -- Access fields from BaseCallGraphData structure if view method is missing
      if g_caller.data and g_caller.data.nodes_map and g_caller.data.edges_list then
          current_graph_nodes_for_marking = g_caller.data.nodes_map
          current_graph_edges_for_marking = g_caller.data.edges_list
          
          log.debug("[CG-DEBUG] Got graph data from g_caller.data:")
          log.debug("[CG-DEBUG] Nodes: ", vim.inspect(current_graph_nodes_for_marking))
          log.debug("[CG-DEBUG] Edges: ", vim.inspect(current_graph_edges_for_marking))
      else
          vim.notify("[CallGraph] Could not retrieve current graph data for marking from g_caller.data.", vim.log.levels.ERROR)
          is_mark_mode_active = false
          return
      end
  end
  current_graph_view_for_marking = g_caller.view

  vim.notify("[CallGraph] Mark mode started. Use CallGraphMarkNode to select nodes.", vim.log.levels.INFO)
  -- Clear any previous markings from a potentially stale state (if any)
  if current_graph_view_for_marking and current_graph_view_for_marking.clear_marked_node_highlights then
    current_graph_view_for_marking:clear_marked_node_highlights()
  end
end

function Caller.mark_node_under_cursor()
  -- 如果不在 mark 模式，自动进入
  if not is_mark_mode_active then
    if not g_caller or not g_caller.view or not g_caller.view.buf or not vim.api.nvim_buf_is_valid(g_caller.view.buf.bufid) then
      vim.notify("[CallGraph] No active call graph to mark.", vim.log.levels.WARN)
      return
    end

    -- Check if the current buffer is the one managed by g_caller.view
    if vim.api.nvim_get_current_buf() ~= g_caller.view.buf.bufid then
      vim.notify("[CallGraph] Mark mode must be started from an active call graph window.", vim.log.levels.WARN)
      return
    end

    is_mark_mode_active = true
    marked_node_ids = {}
    
    if g_caller.view.get_drawn_graph_data then
      local graph_data = g_caller.view:get_drawn_graph_data()
      current_graph_nodes_for_marking = graph_data.nodes
      current_graph_edges_for_marking = graph_data.edges
    else
      log.warn("[CallGraph] GraphView does not have get_drawn_graph_data. Attempting to use data from g_caller.data")
      if g_caller.data and g_caller.data.nodes_map and g_caller.data.edges_list then
        current_graph_nodes_for_marking = g_caller.data.nodes_map
        current_graph_edges_for_marking = g_caller.data.edges_list
      else
        vim.notify("[CallGraph] Could not retrieve current graph data for marking from g_caller.data.", vim.log.levels.ERROR)
        is_mark_mode_active = false
        return
      end
    end
    current_graph_view_for_marking = g_caller.view

    vim.notify("[CallGraph] Mark mode started. Use CallGraphMarkNode to select nodes.", vim.log.levels.INFO)
    -- Clear any previous markings from a potentially stale state (if any)
    if current_graph_view_for_marking and current_graph_view_for_marking.clear_marked_node_highlights then
      current_graph_view_for_marking:clear_marked_node_highlights()
    end
  end

  if not current_graph_view_for_marking or vim.api.nvim_get_current_buf() ~= current_graph_view_for_marking.buf.bufid then
    vim.notify("[CallGraph] Not in the correct call graph window for marking.", vim.log.levels.WARN)
    is_mark_mode_active = false -- Exit mark mode if context is lost
    marked_node_ids = {}
    return
  end
  
  if not current_graph_view_for_marking.get_node_at_cursor then
    vim.notify("[CallGraph] Internal error: Cannot get node at cursor (view function missing).", vim.log.levels.ERROR)
    return
  end

  local node = current_graph_view_for_marking:get_node_at_cursor()

  if node and node.nodeid then
    -- 检查是否已经标记过
    local already_marked = false
    for i, id in ipairs(marked_node_ids) do
      if id == node.nodeid then
        table.remove(marked_node_ids, i)
        already_marked = true
        break
      end
    end

    if not already_marked then
      -- 如果是第一次标记，直接添加
      if #marked_node_ids == 0 then
        table.insert(marked_node_ids, node.nodeid)
        vim.notify(string.format("[CallGraph] Root node '%s' (ID: %d) marked.", node.text, node.nodeid), vim.log.levels.INFO)
      else
        -- 允许与任意已标记节点直接连接的节点被标记
        local can_mark = false
        for _, marked_id in ipairs(marked_node_ids) do
          local marked_node = current_graph_nodes_for_marking[marked_id]
          -- 检查是否有直接连接（无论方向）
          for _, edge in ipairs(marked_node.outcoming_edges) do
            if edge.to_node.nodeid == node.nodeid then
              can_mark = true
              break
            end
          end
          for _, edge in ipairs(marked_node.incoming_edges) do
            if edge.from_node.nodeid == node.nodeid then
              can_mark = true
              break
            end
          end
          -- 反向：新节点的出/入边也要检查
          for _, edge in ipairs(node.outcoming_edges) do
            if edge.to_node.nodeid == marked_id then
              can_mark = true
              break
            end
          end
          for _, edge in ipairs(node.incoming_edges) do
            if edge.from_node.nodeid == marked_id then
              can_mark = true
              break
            end
          end
          if can_mark then break end
        end
        if can_mark then
          table.insert(marked_node_ids, node.nodeid)
          vim.notify(string.format("[CallGraph] Node '%s' (ID: %d) marked.", node.text, node.nodeid), vim.log.levels.INFO)
        else
          vim.notify(string.format("[CallGraph] Cannot mark node '%s' (ID: %d). It must be directly connected to any marked node.", node.text, node.nodeid), vim.log.levels.WARN)
        end
      end
    else
      vim.notify(string.format("[CallGraph] Node '%s' (ID: %d) unmarked.", node.text, node.nodeid), vim.log.levels.INFO)
    end

    if current_graph_view_for_marking.apply_marked_node_highlights then
      current_graph_view_for_marking:apply_marked_node_highlights(marked_node_ids)
    else
      vim.notify("[CallGraph] Internal error: Cannot apply highlights (view function missing).", vim.log.levels.ERROR)
    end
  else
    vim.notify("[CallGraph] No node found at cursor.", vim.log.levels.WARN)
  end
end

function Caller.end_mark_mode_and_generate_subgraph()
  if not is_mark_mode_active then
    log.warn("Mark mode is not active")
    return
  end

  -- 获取当前视图
  local current_view = current_graph_view_for_marking
  if not current_view then
    log.warn("No active view found")
    return
  end

  -- 获取当前图的节点和边数据
  local nodes = current_graph_nodes_for_marking
  local edges = current_graph_edges_for_marking

  if not nodes or not edges then
    log.warn("Failed to get graph data")
    return
  end

  -- 获取已标记的节点ID
  local marked_node_ids_array = {}
  for _, node_id in ipairs(marked_node_ids) do
    table.insert(marked_node_ids_array, node_id)
  end

  if #marked_node_ids_array < 2 then
    vim.notify("请至少标记两个节点", vim.log.levels.WARN)
    return
  end

  -- 生成子图
  local subgraph = generate_subgraph(marked_node_ids_array, nodes, edges)
  if not subgraph then
    vim.notify("生成子图失败", vim.log.levels.ERROR)
    return
  end

  -- 创建新视图并绘制子图
  local new_view = CallGraphView:new()
  -- 设置 nodes_map
  new_view.nodes = subgraph.nodes_map
  -- 使用 nodes_list 中的第一个节点作为根节点
  local root_node = subgraph.nodes_list[1]
  new_view:draw(root_node, false)

  -- 更新全局视图
  g_caller.view = new_view

  -- 清理标记状态
  is_mark_mode_active = false
  marked_node_ids = {}
  current_graph_nodes_for_marking = nil
  current_graph_edges_for_marking = nil
  current_graph_view_for_marking = nil
end

-- 简化子图生成函数
function generate_subgraph(marked_node_ids, nodes, edges)
  log.debug("[CG-DEBUG] Generating subgraph for marked nodes: ", vim.inspect(marked_node_ids))
  log.debug("[CG-DEBUG] Original nodes: ", vim.inspect(nodes))
  log.debug("[CG-DEBUG] Original edges: ", vim.inspect(edges))

  if not marked_node_ids or not nodes or not edges then
    log.warn("Invalid input parameters")
    return nil
  end

  -- 收集子图的节点和边
  local subgraph_nodes = {}
  local subgraph_nodes_map = {}
  local subgraph_edges = {}

  -- 添加标记的节点，并构建 nodeid->node 的 map
  for _, node_id in ipairs(marked_node_ids) do
    if nodes[node_id] then
      -- 深度复制节点，确保不修改原始数据
      local node_copy = vim.deepcopy(nodes[node_id])
      -- 重置边的引用
      node_copy.incoming_edges = {}
      node_copy.outcoming_edges = {}
      subgraph_nodes_map[node_id] = node_copy
      table.insert(subgraph_nodes, node_copy)
    end
  end

  -- 添加连接标记节点的边，并修正新节点的 in/out edges
  for _, edge in ipairs(edges) do
    local from_id = edge.from_node.nodeid
    local to_id = edge.to_node.nodeid
    if subgraph_nodes_map[from_id] and subgraph_nodes_map[to_id] then
      -- 重新构建新边，from/to 指向新_nodes
      local Edge = require("call_graph.class.edge")
      local new_edge = Edge:new(subgraph_nodes_map[from_id], subgraph_nodes_map[to_id], nil, {})
      table.insert(subgraph_nodes_map[from_id].outcoming_edges, new_edge)
      table.insert(subgraph_nodes_map[to_id].incoming_edges, new_edge)
      table.insert(subgraph_edges, new_edge)
    end
  end

  log.debug("[CG-DEBUG] Generated subgraph nodes: ", vim.inspect(subgraph_nodes))
  log.debug("[CG-DEBUG] Generated subgraph edges: ", vim.inspect(subgraph_edges))

  return {
    nodes_map = subgraph_nodes_map,
    nodes_list = subgraph_nodes,
    edges = subgraph_edges
  }
end

Caller.generate_subgraph = generate_subgraph

return Caller
