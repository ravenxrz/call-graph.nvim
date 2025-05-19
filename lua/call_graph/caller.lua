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
-- 获取项目根目录的函数
local function get_project_root()
  -- 尝试使用git获取项目根路径
  local handle = io.popen("git rev-parse --show-toplevel 2>/dev/null")
  if handle then
    local result = handle:read("*a")
    handle:close()
    result = result:gsub("%s+$", "") -- 移除尾部空白
    if result and result ~= "" then
      return result
    end
  end
  
  -- 回退到当前工作目录
  return vim.fn.getcwd()
end

-- 动态获取历史文件路径，确保每个项目都有自己的历史文件
local function get_history_file_path()
  local project_root = get_project_root()
  return project_root .. "/.call_graph_history.json"
end

-- 历史文件路径现在是函数而非静态变量
local history_file_path = get_history_file_path

-- Mark mode state
local is_mark_mode_active = false
local marked_node_ids = {} -- Stores nodeid of marked nodes
local current_graph_nodes_for_marking = nil -- Stores the 'nodes' table of the current graph
local current_graph_edges_for_marking = nil -- Stores the 'edges' table of the current graph
local current_graph_view_for_marking = nil -- Stores the view of the current graph being marked

--- 保存调用图历史到文件
local function save_history_to_file()
  -- 获取项目特定的历史文件路径
  local file_path = history_file_path()
  
  -- 创建要保存的数据结构（只保存必要信息，不包括临时的 buf_id）
  local data_to_save = {}
  for _, entry in ipairs(graph_history) do
    local history_item = {
      root_node_name = entry.root_node_name,
      call_type = entry.call_type,
      timestamp = entry.timestamp
    }
    
    -- 处理常规图形（通过pos_params重新生成）
    if entry.pos_params then
      history_item.pos_params = entry.pos_params
    end
    
    -- 处理子图（保存完整结构，但需要处理循环引用）
    if entry.call_type == Caller.CallType.SUBGRAPH_CALL and entry.subgraph then
      -- 深度复制子图结构，以便我们可以安全地修改它而不影响原始数据
      local subgraph_copy = vim.deepcopy(entry.subgraph)
      
      -- 创建节点索引表，用于后续重建引用
      local node_indices = {}
      
      -- 将nodes_map转换为字符串键以避免稀疏数组问题
      local string_keyed_nodes_map = {}
      for id, node in pairs(subgraph_copy.nodes_map or {}) do
        local str_id = tostring(id)
        string_keyed_nodes_map[str_id] = node
        node_indices[node] = str_id -- 使用字符串ID
      end
      subgraph_copy.nodes_map = string_keyed_nodes_map
      
      -- 处理节点的边引用（移除循环引用）
      for _, node in pairs(subgraph_copy.nodes_map) do
        -- 存储边的ID引用而不是直接对象引用
        local incoming_edge_ids = {}
        for _, edge in ipairs(node.incoming_edges or {}) do
          table.insert(incoming_edge_ids, edge.edgeid)
        end
        node.incoming_edge_ids = incoming_edge_ids
        node.incoming_edges = nil
        
        local outcoming_edge_ids = {}
        for _, edge in ipairs(node.outcoming_edges or {}) do
          table.insert(outcoming_edge_ids, edge.edgeid)
        end
        node.outcoming_edge_ids = outcoming_edge_ids
        node.outcoming_edges = nil
      end
      
      -- 处理边的节点引用（用ID替换对象引用）
      for i, edge in ipairs(subgraph_copy.edges or {}) do
        if edge.from_node and node_indices[edge.from_node] then
          edge.from_node_id = node_indices[edge.from_node]
          edge.from_node = nil
        end
        
        if edge.to_node and node_indices[edge.to_node] then
          edge.to_node_id = node_indices[edge.to_node]
          edge.to_node = nil
        end
      end
      
      -- 处理根节点引用
      if subgraph_copy.root_node and node_indices[subgraph_copy.root_node] then
        subgraph_copy.root_node_id = node_indices[subgraph_copy.root_node]
        subgraph_copy.root_node = nil
      end
      
      history_item.subgraph = subgraph_copy
    end
    
    -- 只保存有位置参数或子图数据的条目
    if entry.pos_params or (entry.call_type == Caller.CallType.SUBGRAPH_CALL and entry.subgraph) then
      table.insert(data_to_save, history_item)
    end
  end
  
  -- 将数据编码为 JSON
  local ok, json_str = pcall(vim.json.encode, data_to_save)
  if not ok then
    vim.notify("[CallGraph] Failed to encode history data: " .. (json_str or "unknown error"), vim.log.levels.ERROR)
    return
  end
  
  -- 写入文件
  local file = io.open(file_path, "w")
  if not file then
    vim.notify("[CallGraph] Failed to open history file for writing: " .. file_path, vim.log.levels.ERROR)
    return
  end
  
  file:write(json_str)
  file:close()
  log.debug("[CallGraph] History saved to: " .. file_path)
end

--- 从文件加载历史记录
local function load_history_from_file()
  -- 获取项目特定的历史文件路径
  local file_path = history_file_path()
  
  -- 检查文件是否存在
  local file = io.open(file_path, "r")
  if not file then
    log.debug("[CallGraph] No history file found at: " .. file_path)
    return
  end
  
  -- 读取文件内容
  local content = file:read("*all")
  file:close()
  
  if content == "" then
    log.debug("[CallGraph] History file is empty")
    return
  end
  
  -- 解析 JSON
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= "table" then
    vim.notify("[CallGraph] Failed to parse history file: " .. (data or "unknown error"), vim.log.levels.WARN)
    return
  end
  
  -- 将加载的数据转换为历史记录格式（初始化 buf_id 为无效值）
  graph_history = {}
  for _, entry in ipairs(data) do
    if entry.root_node_name and entry.call_type then
      local history_item = {
        buf_id = -1,  -- 初始化为无效值，在生成图时会更新
        root_node_name = entry.root_node_name,
        call_type = entry.call_type,
        timestamp = entry.timestamp or os.time()
      }
      
      -- 加载常规图的位置参数
      if entry.pos_params then
        history_item.pos_params = entry.pos_params
      end
      
      -- 加载子图结构并重建对象引用关系
      if entry.call_type == Caller.CallType.SUBGRAPH_CALL and entry.subgraph then
        local subgraph = entry.subgraph
        
        -- 首先确保所有边都有一个edgeid
        for i, edge in ipairs(subgraph.edges or {}) do
          if not edge.edgeid then
            edge.edgeid = i  -- 如果没有edgeid，使用索引作为edgeid
          end
        end
        
        -- 创建边ID到边对象的映射
        local edge_map = {}
        for _, edge in ipairs(subgraph.edges or {}) do
          edge_map[edge.edgeid] = edge
        end
        
        -- 重建边和节点之间的引用
        for id, node in pairs(subgraph.nodes_map or {}) do
          -- 确保 node 是表类型
          if type(node) == "table" then
            -- 重建入边引用
            node.incoming_edges = {}
            -- 安全地获取入边ID列表
            local incoming_edge_ids = node.incoming_edge_ids or {}
            if type(incoming_edge_ids) == "table" then
              for _, edge_id in ipairs(incoming_edge_ids) do
                if edge_map[edge_id] then
                  table.insert(node.incoming_edges, edge_map[edge_id])
                end
              end
            end
            node.incoming_edge_ids = nil
            
            -- 重建出边引用
            node.outcoming_edges = {}
            -- 安全地获取出边ID列表
            local outcoming_edge_ids = node.outcoming_edge_ids or {}
            if type(outcoming_edge_ids) == "table" then  
              for _, edge_id in ipairs(outcoming_edge_ids) do
                if edge_map[edge_id] then
                  table.insert(node.outcoming_edges, edge_map[edge_id])
                end
              end
            end
            node.outcoming_edge_ids = nil
          else
            -- 如果节点不是表类型，创建一个空的节点结构
            log.warn("[CallGraph] Node with ID " .. tostring(id) .. " is not a table type: " .. type(node))
            subgraph.nodes_map[id] = {
              nodeid = id,
              text = "Invalid Node " .. tostring(id),
              incoming_edges = {},
              outcoming_edges = {}
            }
          end
        end
        
        -- 重建边对节点的引用
        for _, edge in ipairs(subgraph.edges or {}) do
          if edge.from_node_id and subgraph.nodes_map then
            -- 处理字符串键（从save_history_to_file函数中生成的）
            local from_id = edge.from_node_id
            edge.from_node = subgraph.nodes_map[from_id]
            edge.from_node_id = nil
          end
          
          if edge.to_node_id and subgraph.nodes_map then
            -- 处理字符串键（从save_history_to_file函数中生成的）
            local to_id = edge.to_node_id
            edge.to_node = subgraph.nodes_map[to_id]
            edge.to_node_id = nil
          end
        end
        
        -- 重建根节点引用
        if subgraph.root_node_id and subgraph.nodes_map then
          -- 处理字符串键（从save_history_to_file函数中生成的）
          local root_id = subgraph.root_node_id
          subgraph.root_node = subgraph.nodes_map[root_id]
          subgraph.root_node_id = nil
        end
        
        -- 如果需要，将节点映射转回数字键以保持与代码其余部分的兼容性
        local numeric_nodes_map = {}
        for str_id, node in pairs(subgraph.nodes_map) do
          local num_id = tonumber(str_id)
          if num_id then
            numeric_nodes_map[num_id] = node
          else
            numeric_nodes_map[str_id] = node -- 保留非数字键
          end
        end
        subgraph.nodes_map = numeric_nodes_map
        
        history_item.subgraph = subgraph
      end
      
      -- 只添加有用的条目（有位置参数或子图）
      if history_item.pos_params or (entry.call_type == Caller.CallType.SUBGRAPH_CALL and history_item.subgraph) then
        table.insert(graph_history, history_item)
      end
    end
  end
  
  log.debug("[CallGraph] Loaded " .. #graph_history .. " history entries")
end

--- Add a graph to history
---@param buf_id number The buffer ID of the graph
---@param root_node_name string The name of the root node
---@param call_type CallType The type of call graph
---@param root_node table The actual root node object containing position parameters
local function add_to_history(buf_id, root_node_name, call_type, root_node)
  -- 确保 root_node 和必要的调用位置信息存在
  local pos_params = nil
  if root_node and root_node.usr_data and root_node.usr_data.attr and root_node.usr_data.attr.pos_params then
    pos_params = vim.deepcopy(root_node.usr_data.attr.pos_params)
  end

  -- 检查是否已存在相同的root_node或相同文件位置的记录
  local existing_index = nil
  for i, entry in ipairs(graph_history) do
    -- 检查是否有相同位置参数的记录
    if entry.pos_params and pos_params and 
       entry.pos_params.textDocument.uri == pos_params.textDocument.uri and
       entry.pos_params.position.line == pos_params.position.line and
       entry.pos_params.position.character == pos_params.position.character then
      existing_index = i
      break
    end
    
    -- 如果没找到相同位置但找到相同的root_node_name和call_type，也认为是相同记录
    if entry.root_node_name == root_node_name and entry.call_type == call_type then
      existing_index = i
      break
    end
  end

  if existing_index then
    -- 已存在记录，更新buf_id和时间戳，并移动到列表最前面
    local existing_entry = table.remove(graph_history, existing_index)
    existing_entry.buf_id = buf_id
    existing_entry.timestamp = os.time()
    -- 如果新的pos_params更完整，则更新
    if pos_params and (not existing_entry.pos_params or vim.tbl_isempty(existing_entry.pos_params)) then
      existing_entry.pos_params = pos_params
    end
    table.insert(graph_history, 1, existing_entry)
    log.debug("[CallGraph] Updated existing history entry for: " .. root_node_name)
  else
    -- 创建新的历史记录
    local history_entry = {
      buf_id = buf_id,
      root_node_name = root_node_name,
      call_type = call_type,
      timestamp = os.time(),
      pos_params = pos_params  -- 存储位置参数，用于重新生成图
    }
    
    table.insert(graph_history, 1, history_entry)
    
    -- Trim history if it exceeds max size
    if #graph_history > max_history_size then
      -- Remove the oldest entry (last in the array)
      table.remove(graph_history, #graph_history)
    end
  end
  
  -- 保存历史到文件
  save_history_to_file()
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
    -- 尝试重新生成图
    Caller.regenerate_graph_from_history(latest)
  end
end

--- Show graph history and let user select
function Caller.show_graph_history()
  if #graph_history == 0 then
    -- 尝试从文件加载历史
    load_history_from_file()
    
    if #graph_history == 0 then
      vim.notify("[CallGraph] No graph history available", vim.log.levels.WARN)
      return
    end
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
      call_type_str = "Subgraph"
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
        -- 尝试重新生成图
        Caller.regenerate_graph_from_history(entry)
      end
    end
  end)
end

--- 从历史记录重新生成调用图
---@param history_entry table 历史记录条目
function Caller.regenerate_graph_from_history(history_entry)
  -- 对于子图，直接从保存的子图结构重新生成
  if history_entry.call_type == Caller.CallType.SUBGRAPH_CALL and history_entry.subgraph then
    local subgraph = history_entry.subgraph
    
    -- 确保子图结构完整
    if not subgraph.root_node then
      vim.notify("[CallGraph] 无法重新生成子图：缺少根节点", vim.log.levels.ERROR)
      return
    end
    
    -- 创建新视图并绘制子图
    local new_view = CallGraphView:new()
    
    -- 确定是否通过入边遍历
    local traverse_by_incoming = subgraph.root_node and subgraph.root_node.incoming_edges and #(subgraph.root_node.incoming_edges) > 0
    
    -- 使用子图的根节点作为绘图起点
    new_view:draw(subgraph.root_node, traverse_by_incoming)
    
    -- 更新全局视图
    g_caller = create_caller(nil, new_view)
    last_call_type = Caller.CallType.SUBGRAPH_CALL
    
    -- 更新历史记录中的buf_id
    history_entry.buf_id = new_view.buf.bufid
    
    vim.notify("[CallGraph] 子图已从历史记录重新加载", vim.log.levels.INFO)
    return
  end
  
  -- 对于常规图，使用pos_params重新生成
  if not history_entry or not history_entry.pos_params then
    vim.notify("[CallGraph] Cannot regenerate graph: missing position data", vim.log.levels.ERROR)
    return
  end
  
  -- 保存当前文件路径和位置
  local current_buf = vim.api.nvim_get_current_buf()
  local current_win = vim.api.nvim_get_current_win()
  local current_pos = vim.api.nvim_win_get_cursor(current_win)
  
  -- 打开目标文件
  local uri = history_entry.pos_params.textDocument.uri
  local file_path = vim.uri_to_fname(uri)
  local success = pcall(vim.cmd, "edit " .. file_path)
  
  if not success then
    vim.notify("[CallGraph] Failed to open file: " .. file_path, vim.log.levels.ERROR)
    return
  end
  
  -- 移动光标到目标位置
  local pos = history_entry.pos_params.position
  vim.api.nvim_win_set_cursor(0, {pos.line + 1, pos.character})
  
  -- 使用相应的命令生成调用图
  local opts = vim.deepcopy(require("call_graph").opts)
  local function on_generated_callback(buf_id, root_node_name)
    -- 更新历史记录中的 buf_id
    for i, entry in ipairs(graph_history) do
      if entry == history_entry then
        graph_history[i].buf_id = buf_id
        break
      end
    end
  end
  
  -- 根据调用图类型生成
  Caller.generate_call_graph(opts, history_entry.call_type, on_generated_callback)
  
  -- 注意：我们不需要恢复原始位置，因为生成的调用图会成为焦点
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
    -- 确定是否通过入边遍历
    local traverse_by_incoming = root_node and root_node.incoming_edges and #(root_node.incoming_edges) > 0
    caller.view:draw(root_node, traverse_by_incoming)
    local buf_id = caller.view.buf.bufid
    vim.notify("[CallGraph] graph generated", vim.log.levels.INFO)
    
    local root_node_name = root_node and root_node.text or "UnknownRoot"
    -- 传递完整的root_node，以便保存位置信息
    add_to_history(buf_id, root_node_name, call_type, root_node)
    
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

  -- 清除原图中的高亮显示
  if current_view.clear_marked_node_highlights then
    current_view:clear_marked_node_highlights()
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
  
  -- 确定是否通过入边遍历
  local traverse_by_incoming = subgraph.root_node and subgraph.root_node.incoming_edges and #(subgraph.root_node.incoming_edges) > 0
  
  -- 使用子图的根节点作为绘图起点
  new_view:draw(subgraph.root_node, traverse_by_incoming)

  -- 更新全局视图
  g_caller.view = new_view

  -- 将子图添加到历史记录
  if subgraph.root_node and new_view.buf and new_view.buf.bufid and vim.api.nvim_buf_is_valid(new_view.buf.bufid) then
    local root_node_name = subgraph.root_node.text or "Subgraph"
    
    -- 深度复制子图结构，确保安全处理
    local subgraph_copy = vim.deepcopy(subgraph)
    
    -- 验证子图结构的完整性
    if not subgraph_copy.nodes_map or not subgraph_copy.edges or not subgraph_copy.root_node then
      log.warn("子图结构不完整，无法添加到历史记录")
      vim.notify("[CallGraph] 子图结构不完整，无法保存到历史记录", vim.log.levels.WARN)
      return
    end
    
    -- 确保nodes_map中所有节点ID都是有效的
    local fixed_nodes_map = {}
    for id, node in pairs(subgraph_copy.nodes_map) do
      if type(node) == "table" then
        fixed_nodes_map[id] = node
      else
        log.warn("跳过非表类型的节点: " .. tostring(id))
      end
    end
    subgraph_copy.nodes_map = fixed_nodes_map
    
    -- 创建一个包含整个子图的历史记录条目
    local history_entry = {
      buf_id = new_view.buf.bufid,
      root_node_name = root_node_name,
      call_type = Caller.CallType.SUBGRAPH_CALL,
      timestamp = os.time(),
      subgraph = subgraph_copy
    }
    
    -- 插入到历史记录的开头
    table.insert(graph_history, 1, history_entry)
    
    -- 如果超出最大历史记录数，移除最老的
    if #graph_history > max_history_size then
      table.remove(graph_history, #graph_history)
    end
    
    -- 保存历史到文件
    save_history_to_file()
    
    -- 导出mermaid图表，确保用户可以查看最新的图表
    local opts = require("call_graph").opts
    if opts.export_mermaid_graph then
      MermaidGraph.export(subgraph.root_node, mermaid_path)
    end
    
    vim.notify("[CallGraph] 子图已生成并添加到历史记录", vim.log.levels.INFO)
  end

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
  local root_node = nil

  -- 添加标记的节点，并构建 nodeid->node 的 map
  for _, node_id in ipairs(marked_node_ids) do
    if nodes[node_id] then
      -- 深度复制节点，确保不修改原始数据
      local node_copy = vim.deepcopy(nodes[node_id])
      -- 重置边的引用
      node_copy.incoming_edges = {}
      node_copy.outcoming_edges = {}
      -- 确保 usr_data 被正确复制
      if nodes[node_id].usr_data then
        node_copy.usr_data = vim.deepcopy(nodes[node_id].usr_data)
      end
      -- 确保 pos_params 被正确复制
      if nodes[node_id].pos_params then
        node_copy.pos_params = vim.deepcopy(nodes[node_id].pos_params)
      end
      subgraph_nodes_map[node_id] = node_copy
      table.insert(subgraph_nodes, node_copy)
      
      -- 选择level最小的节点作为root_node，或使用第一个节点
      if not root_node or (node_copy.level and (not root_node.level or node_copy.level < root_node.level)) then
        root_node = node_copy
      end
    end
  end

  -- 添加连接标记节点的边，并修正新节点的 in/out edges
  for _, edge in ipairs(edges) do
    local from_id = edge.from_node.nodeid
    local to_id = edge.to_node.nodeid
    if subgraph_nodes_map[from_id] and subgraph_nodes_map[to_id] then
      -- 重新构建新边，from/to 指向新_nodes
      local Edge = require("call_graph.class.edge")
      -- 深度复制 pos_params 和 sub_edges
      local pos_params = edge.pos_params and vim.deepcopy(edge.pos_params) or nil
      local sub_edges = edge.sub_edges and vim.deepcopy(edge.sub_edges) or {}
      local new_edge = Edge:new(subgraph_nodes_map[from_id], subgraph_nodes_map[to_id], pos_params, sub_edges)
      table.insert(subgraph_nodes_map[from_id].outcoming_edges, new_edge)
      table.insert(subgraph_nodes_map[to_id].incoming_edges, new_edge)
      table.insert(subgraph_edges, new_edge)
    end
  end

  log.debug("[CG-DEBUG] Generated subgraph nodes: ", vim.inspect(subgraph_nodes))
  log.debug("[CG-DEBUG] Generated subgraph edges: ", vim.inspect(subgraph_edges))

  return {
    root_node = root_node, -- 返回一个选定的根节点
    nodes_map = subgraph_nodes_map,
    nodes_list = subgraph_nodes,
    edges = subgraph_edges
  }
end

Caller.generate_subgraph = generate_subgraph

-- 在初始化时加载历史记录
local function init()
  load_history_from_file()
end

-- 在模块加载时执行初始化
init()

-- 将 graph_history 更新的函数暴露出去，供测试使用
Caller._get_graph_history = function()
  return graph_history
end

Caller._set_max_history_size = function(size)
  max_history_size = size
  -- 如果当前历史记录超过了新的大小限制，则裁剪
  while #graph_history > max_history_size do
    table.remove(graph_history)
  end
end

-- 暴露 load_history_from_file 供测试使用
Caller.load_history_from_file = load_history_from_file

-- 暴露 add_to_history 供测试使用
Caller.add_to_history = add_to_history

-- 添加退出mark模式的函数
function Caller.exit_mark_mode()
  -- 如果不在mark模式，直接返回
  if not is_mark_mode_active then
    vim.notify("[CallGraph] 未处于标记模式", vim.log.levels.INFO)
    return
  end
  
  -- 获取当前视图
  local current_view = current_graph_view_for_marking
  if current_view and current_view.clear_marked_node_highlights then
    -- 清除高亮
    current_view:clear_marked_node_highlights()
  end
  
  -- 重置所有mark模式相关状态
  is_mark_mode_active = false
  marked_node_ids = {}
  current_graph_nodes_for_marking = nil
  current_graph_edges_for_marking = nil
  current_graph_view_for_marking = nil
  
  vim.notify("[CallGraph] 已退出标记模式", vim.log.levels.INFO)
end

return Caller
