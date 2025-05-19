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

-- Create a caller instance with the given data and view
local function create_caller(data, view)
  local caller = setmetatable({}, Caller)
  caller.view = view
  caller.data = data
  return caller
end

local g_caller = nil
local last_call_type = Caller.CallType._NO_CALl
local mermaid_path = ".call_graph.mermaid"

-- Graph history management
local graph_history = {}
local max_history_size = 20
-- Get project root directory function
local function get_project_root()
  -- Try to get project root path using git
  local handle = io.popen("git rev-parse --show-toplevel 2>/dev/null")
  if handle then
    local result = handle:read("*a")
    handle:close()
    result = result:gsub("%s+$", "") -- Remove trailing whitespace
    if result and result ~= "" then
      return result
    end
  end

  -- Fallback to current working directory
  return vim.fn.getcwd()
end

-- Dynamically get history file path, ensuring each project has its own history file
local function get_history_file_path()
  local project_root = get_project_root()
  return project_root .. "/.call_graph_history.json"
end

-- History file path is now a function instead of a static variable
local history_file_path = get_history_file_path

-- Store mapping between graph buffer ID and caller instance for easier updating of g_caller
-- This mapping is crucial for solving the following issues:
-- 1. When user switches from one graph to another, ensure g_caller correctly points to the instance for the current buffer
-- 2. After generating a subgraph from a full graph, if user manually switches back to the full graph, restore the full graph context
-- 3. Ensure mark_node_under_cursor works correctly in any active graph buffer
local buffer_caller_map = {}

-- Mark mode state
local is_mark_mode_active = false
local marked_node_ids = {} -- Stores nodeid of marked nodes
local current_graph_nodes_for_marking = nil -- Stores the 'nodes' table of the current graph
local current_graph_edges_for_marking = nil -- Stores the 'edges' table of the current graph
local current_graph_view_for_marking = nil -- Stores the view of the current graph being marked

--- Save history to file
local function save_history_to_file()
  -- Get project-specific history file path
  local file_path = history_file_path()

  -- Create data structure to save (only save necessary information, not including temporary buf_id)
  local data_to_save = {}
  for _, entry in ipairs(graph_history) do
    local history_item = {
      root_node_name = entry.root_node_name,
      call_type = entry.call_type,
      timestamp = entry.timestamp,
    }

    -- Handle regular graphs (regenerate through pos_params)
    if entry.pos_params then
      history_item.pos_params = entry.pos_params
    end

    -- Handle subgraphs (save full structure, but need to handle circular references)
    if entry.call_type == Caller.CallType.SUBGRAPH_CALL and entry.subgraph then
      -- Deep copy subgraph structure so we can safely modify it without affecting original data
      local subgraph_copy = vim.deepcopy(entry.subgraph)

      -- Create node index table for later reconstruction of references
      local node_indices = {}

      -- Convert nodes_map to string keyed map to avoid sparse array problems
      local string_keyed_nodes_map = {}
      for id, node in pairs(subgraph_copy.nodes_map or {}) do
        local str_id = tostring(id)
        string_keyed_nodes_map[str_id] = node
        node_indices[node] = str_id -- Use string ID
      end
      subgraph_copy.nodes_map = string_keyed_nodes_map

      -- Handle edge references (remove circular references)
      for _, node in pairs(subgraph_copy.nodes_map) do
        -- Store edge ID references instead of direct object references
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

      -- Handle node references (use ID instead of object references)
      for i, edge in ipairs(subgraph_copy.edges or {}) do
        if edge.from_node and node_indices[edge.from_node] then
          edge.from_node_id = node_indices[edge.from_node]
          edge.from_node = nil
        end

        if edge.to_node and node_indices[edge.to_node] then
          edge.to_node_id = node_indices[edge.to_node]
          edge.to_node = nil
        end

        -- Ensure sub_edges information is correctly saved
        if edge.sub_edges then
          local serialized_sub_edges = {}
          for _, sub_edge in ipairs(edge.sub_edges) do
            if type(sub_edge) == "table" then
              -- Only save basic attributes of sub_edges, no need for methods
              table.insert(serialized_sub_edges, {
                start_row = sub_edge.start_row,
                start_col = sub_edge.start_col,
                end_row = sub_edge.end_row,
                end_col = sub_edge.end_col,
                sub_edgeid = sub_edge.sub_edgeid,
              })
            end
          end
          edge.sub_edges = serialized_sub_edges
        end
      end

      -- Handle root node references
      if subgraph_copy.root_node and node_indices[subgraph_copy.root_node] then
        subgraph_copy.root_node_id = node_indices[subgraph_copy.root_node]
        subgraph_copy.root_node = nil
      end

      history_item.subgraph = subgraph_copy
    end

    -- Only save entries with position parameters or subgraph data
    if entry.pos_params or (entry.call_type == Caller.CallType.SUBGRAPH_CALL and entry.subgraph) then
      table.insert(data_to_save, history_item)
    end
  end

  -- Encode data to JSON
  local ok, json_str = pcall(vim.json.encode, data_to_save)
  if not ok then
    vim.notify("[CallGraph] Failed to encode history data: " .. (json_str or "unknown error"), vim.log.levels.ERROR)
    return
  end

  -- Write to file
  local file = io.open(file_path, "w")
  if not file then
    vim.notify("[CallGraph] Failed to open history file for writing: " .. file_path, vim.log.levels.ERROR)
    return
  end

  file:write(json_str)
  file:close()
  log.debug("[CallGraph] History saved to: " .. file_path)
end

--- Load history from file
local function load_history_from_file()
  -- Get project-specific history file path
  local file_path = history_file_path()

  -- Check if file exists
  local file = io.open(file_path, "r")
  if not file then
    log.debug("[CallGraph] No history file found at: " .. file_path)
    return
  end

  -- Read file content
  local content = file:read("*all")
  file:close()

  if content == "" then
    log.debug("[CallGraph] History file is empty")
    return
  end

  -- Debug output
  log.debug("[CallGraph] Loaded history file content length: " .. #content)

  -- Parse JSON
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= "table" then
    vim.notify("[CallGraph] Failed to parse history file: " .. (data or "unknown error"), vim.log.levels.WARN)
    log.warn("[CallGraph] JSON parse failed: " .. tostring(data))
    return
  end

  -- Debug output
  log.debug("[CallGraph] Parsed JSON data count: " .. #data)

  -- Convert loaded data to history record format (initialize buf_id as invalid)
  graph_history = {}
  for _, entry in ipairs(data) do
    if entry.root_node_name and entry.call_type then
      local history_item = {
        buf_id = -1, -- Initialize as invalid, will be updated when generating graph
        root_node_name = entry.root_node_name,
        call_type = entry.call_type,
        timestamp = entry.timestamp or os.time(),
      }

      -- Load position parameters for regular graphs
      if entry.pos_params then
        history_item.pos_params = entry.pos_params
      end

      -- Load subgraph structure and rebuild object references
      if entry.call_type == Caller.CallType.SUBGRAPH_CALL and entry.subgraph then
        local subgraph = entry.subgraph
        log.debug("[CallGraph] Processing subgraph data with " .. vim.tbl_count(subgraph.nodes_map or {}) .. " nodes")

        -- First ensure all edges have an edgeid
        for i, edge in ipairs(subgraph.edges or {}) do
          if not edge.edgeid then
            edge.edgeid = i -- If no edgeid, use index as edgeid
          end
        end

        -- Create mapping from edge ID to edge object
        local edge_map = {}
        for _, edge in ipairs(subgraph.edges or {}) do
          edge_map[edge.edgeid] = edge
        end

        -- Rebuild references between edges and nodes
        for id, node in pairs(subgraph.nodes_map or {}) do
          -- Ensure node is a table
          if type(node) == "table" then
            -- Rebuild incoming edge references
            node.incoming_edges = {}
            -- Safely get incoming edge ID list
            local incoming_edge_ids = node.incoming_edge_ids or {}
            if type(incoming_edge_ids) == "table" then
              for _, edge_id in ipairs(incoming_edge_ids) do
                if edge_map[edge_id] then
                  table.insert(node.incoming_edges, edge_map[edge_id])
                end
              end
            end
            node.incoming_edge_ids = nil

            -- Rebuild outgoing edge references
            node.outcoming_edges = {}
            -- Safely get outgoing edge ID list
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
            -- If node is not a table type, create an empty node structure
            log.warn("[CallGraph] Node with ID " .. tostring(id) .. " is not a table type: " .. type(node))
            subgraph.nodes_map[id] = {
              nodeid = id,
              text = "Invalid Node " .. tostring(id),
              incoming_edges = {},
              outcoming_edges = {},
            }
          end
        end

        -- First ensure all edges' node references are correctly set
        for _, edge in ipairs(subgraph.edges or {}) do
          if edge.from_node_id and subgraph.nodes_map then
            -- Handle string keys (generated from save_history_to_file function)
            local from_id = edge.from_node_id
            edge.from_node = subgraph.nodes_map[from_id]
            edge.from_node_id = nil
          end

          if edge.to_node_id and subgraph.nodes_map then
            -- Handle string keys (generated from save_history_to_file function)
            local to_id = edge.to_node_id
            edge.to_node = subgraph.nodes_map[to_id]
            edge.to_node_id = nil
          end
        end

        -- Use Edge:new to recreate all Edge objects, ensuring they have correct methods
        local Edge = require("call_graph.class.edge")
        for i, edge in ipairs(subgraph.edges or {}) do
          if edge.from_node and edge.to_node then
            -- Save important attributes
            local pos_params = edge.pos_params
            local sub_edges = edge.sub_edges
            local edgeid = edge.edgeid

            -- Handle sub_edges, ensure they are SubEdge objects
            local processed_sub_edges = {}
            if sub_edges and type(sub_edges) == "table" then
              local SubEdge = require("call_graph.class.subedge")
              for _, sub_edge_data in ipairs(sub_edges) do
                if
                  type(sub_edge_data) == "table"
                  and sub_edge_data.start_row
                  and sub_edge_data.start_col
                  and sub_edge_data.end_row
                  and sub_edge_data.end_col
                then
                  local sub_edge = SubEdge:new(
                    sub_edge_data.start_row,
                    sub_edge_data.start_col,
                    sub_edge_data.end_row,
                    sub_edge_data.end_col
                  )
                  -- Ensure to_string method is correctly set
                  if not sub_edge.to_string then
                    sub_edge.to_string = SubEdge.to_string
                  end
                  table.insert(processed_sub_edges, sub_edge)
                end
              end
            end

            -- Create new Edge object
            local new_edge = Edge:new(edge.from_node, edge.to_node, pos_params, processed_sub_edges)

            -- Keep original edgeid, ensure reference consistency
            new_edge.edgeid = edgeid

            -- Replace original with new created Edge object
            subgraph.edges[i] = new_edge

            -- Update node edge references
            for j, e in ipairs(edge.from_node.outcoming_edges or {}) do
              if e.edgeid == edgeid then
                edge.from_node.outcoming_edges[j] = new_edge
              end
            end

            for j, e in ipairs(edge.to_node.incoming_edges or {}) do
              if e.edgeid == edgeid then
                edge.to_node.incoming_edges[j] = new_edge
              end
            end
          end
        end

        -- Rebuild root node references
        if subgraph.root_node_id and subgraph.nodes_map then
          -- Handle string keys (generated from save_history_to_file function)
          local root_id = subgraph.root_node_id
          subgraph.root_node = subgraph.nodes_map[root_id]
          subgraph.root_node_id = nil
        end

        -- If needed, convert node mapping back to numeric keys for compatibility with rest of the code
        local numeric_nodes_map = {}
        for str_id, node in pairs(subgraph.nodes_map) do
          local num_id = tonumber(str_id)
          if num_id then
            numeric_nodes_map[num_id] = node
          else
            numeric_nodes_map[str_id] = node -- Keep non-numeric keys
          end
        end
        subgraph.nodes_map = numeric_nodes_map

        history_item.subgraph = subgraph
      end

      -- Only add useful entries (with position parameters or subgraph)
      if history_item.pos_params or (entry.call_type == Caller.CallType.SUBGRAPH_CALL and history_item.subgraph) then
        table.insert(graph_history, 1, history_item)
        log.debug(
          "[CallGraph] Added history record: "
            .. (history_item.root_node_name or "nil")
            .. ", type: "
            .. history_item.call_type
        )
      else
        log.debug(
          "[CallGraph] Skipped history record: "
            .. (history_item.root_node_name or "nil")
            .. ", reason: missing position parameters or subgraph"
        )
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
  -- Ensure root_node and necessary call position information exist
  local pos_params = nil
  if root_node and root_node.usr_data and root_node.usr_data.attr and root_node.usr_data.attr.pos_params then
    pos_params = vim.deepcopy(root_node.usr_data.attr.pos_params)
  end

  -- Check if same root_node or same file position record already exists
  local existing_index = nil
  for i, entry in ipairs(graph_history) do
    -- Check if there's a record with same position parameters
    if
      entry.pos_params
      and pos_params
      and entry.pos_params.textDocument.uri == pos_params.textDocument.uri
      and entry.pos_params.position.line == pos_params.position.line
      and entry.pos_params.position.character == pos_params.position.character
    then
      existing_index = i
      break
    end

    -- If no same position but find same root_node_name and call_type, also consider it same record
    if entry.root_node_name == root_node_name and entry.call_type == call_type then
      existing_index = i
      break
    end
  end

  if existing_index then
    -- Record already exists, update buf_id and timestamp, and move to front of list
    local existing_entry = table.remove(graph_history, existing_index)
    existing_entry.buf_id = buf_id
    existing_entry.timestamp = os.time()
    -- If new pos_params are more complete, update
    if pos_params and (not existing_entry.pos_params or vim.tbl_isempty(existing_entry.pos_params)) then
      existing_entry.pos_params = pos_params
    end
    table.insert(graph_history, 1, existing_entry)
    log.debug("[CallGraph] Updated existing history entry for: " .. root_node_name)
  else
    -- Create new history record
    local history_entry = {
      buf_id = buf_id,
      root_node_name = root_node_name,
      call_type = call_type,
      timestamp = os.time(),
      pos_params = pos_params, -- Store position parameters for regenerating graph
    }

    table.insert(graph_history, 1, history_entry)

    -- Trim history if it exceeds max size
    if #graph_history > max_history_size then
      -- Remove the oldest entry (last in the array)
      table.remove(graph_history, #graph_history)
    end
  end

  -- Save history to file
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
    -- Try to regenerate graph
    Caller.regenerate_graph_from_history(latest)
  end
end

--- Show graph history and let user select
function Caller.show_graph_history()
  if #graph_history == 0 then
    -- Try to load history from file
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
    table.insert(items, string.format("%d. [%s] %s (%s)", i, call_type_str, entry.root_node_name, time_str))
  end

  vim.ui.select(items, {
    prompt = "Select a graph to open:",
    format_item = function(item)
      return item
    end,
  }, function(choice, idx)
    if idx then
      local entry = graph_history[idx]
      if vim.api.nvim_buf_is_valid(entry.buf_id) then
        vim.cmd("buffer " .. entry.buf_id)
      else
        -- Try to regenerate graph
        Caller.regenerate_graph_from_history(entry)
      end
    end
  end)
end

--- Regenerate graph from history
---@param history_entry table History record entry
function Caller.regenerate_graph_from_history(history_entry)
  -- For subgraphs, regenerate directly from saved subgraph structure
  if history_entry.call_type == Caller.CallType.SUBGRAPH_CALL and history_entry.subgraph then
    local subgraph = history_entry.subgraph

    -- Ensure subgraph structure is complete
    if not subgraph.root_node then
      vim.notify("[CallGraph] Cannot regenerate subgraph: missing root node", vim.log.levels.ERROR)
      return
    end

    -- Create new view and draw subgraph
    local new_view = CallGraphView:new()

    -- Determine if traversing through incoming edges
    local traverse_by_incoming = subgraph.root_node
      and subgraph.root_node.incoming_edges
      and #subgraph.root_node.incoming_edges > 0

    -- Use subgraph's root node as drawing starting point
    new_view:draw(subgraph.root_node, traverse_by_incoming)

    -- Add subgraph to history
    if subgraph.root_node and new_view.buf and new_view.buf.bufid and vim.api.nvim_buf_is_valid(new_view.buf.bufid) then
      local root_node_name = subgraph.root_node.text or "Subgraph"

      -- Deep copy subgraph structure, ensure safe handling
      local subgraph_copy = vim.deepcopy(subgraph)

      -- Verify subgraph structure completeness
      if not subgraph_copy.nodes_map or not subgraph_copy.edges or not subgraph_copy.root_node then
        log.warn("Subgraph structure incomplete, cannot add to history")
        vim.notify("[CallGraph] Subgraph structure incomplete, cannot save to history", vim.log.levels.WARN)
        return
      end

      -- Ensure all node IDs in nodes_map are valid
      local fixed_nodes_map = {}
      for id, node in pairs(subgraph_copy.nodes_map) do
        if type(node) == "table" then
          fixed_nodes_map[id] = node
        else
          log.warn("Skipping non-table type node: " .. tostring(id))
        end
      end
      subgraph_copy.nodes_map = fixed_nodes_map

      -- Create history record entry for entire subgraph
      local history_entry = {
        buf_id = new_view.buf.bufid,
        root_node_name = root_node_name,
        call_type = Caller.CallType.SUBGRAPH_CALL,
        timestamp = os.time(),
        subgraph = subgraph_copy,
      }

      -- Insert into history at front
      table.insert(graph_history, 1, history_entry)

      -- If history exceeds max size, remove oldest
      if #graph_history > max_history_size then
        table.remove(graph_history, #graph_history)
      end

      -- Save history to file
      save_history_to_file()

      -- Export mermaid chart, ensure user can view latest chart
      local opts = require("call_graph").opts
      if opts.export_mermaid_graph then
        MermaidGraph.export(subgraph.root_node, mermaid_path)
      end

      vim.notify("[CallGraph] Subgraph generated and added to history", vim.log.levels.INFO)
    end

    -- Create new caller instance
    local new_caller = create_caller(nil, new_view)

    -- Save original g_caller reference
    local original_caller = g_caller

    -- Update global view
    g_caller = new_caller
    last_call_type = Caller.CallType.SUBGRAPH_CALL

    -- Save buffer ID to caller instance mapping
    if new_view.buf and new_view.buf.bufid then
      buffer_caller_map[new_view.buf.bufid] = new_caller
      log.debug("[CallGraph] Added subgraph buffer " .. new_view.buf.bufid .. " to buffer_caller_map")
    end

    -- Ensure original graph buffer ID still maps to original caller instance
    if original_caller and original_caller.view and original_caller.view.buf and original_caller.view.buf.bufid then
      buffer_caller_map[original_caller.view.buf.bufid] = original_caller
      log.debug(
        "[CallGraph] Preserved original graph buffer " .. original_caller.view.buf.bufid .. " in buffer_caller_map"
      )
    end

    return -- Subgraph processing completed, return directly
  end

  -- If here, it's regular graph, need to check position data
  if not history_entry or not history_entry.pos_params then
    vim.notify("[CallGraph] Cannot regenerate graph: missing position data", vim.log.levels.ERROR)
    return
  end

  -- Save current file path and position
  local current_buf = vim.api.nvim_get_current_buf()
  local current_win = vim.api.nvim_get_current_win()
  local current_pos = vim.api.nvim_win_get_cursor(current_win)

  -- Open target file
  local uri = history_entry.pos_params.textDocument.uri
  local file_path = vim.uri_to_fname(uri)
  local success = pcall(vim.cmd, "edit " .. file_path)

  if not success then
    vim.notify("[CallGraph] Failed to open file: " .. file_path, vim.log.levels.ERROR)
    return
  end

  -- Move cursor to target position
  local pos = history_entry.pos_params.position
  vim.api.nvim_win_set_cursor(0, { pos.line + 1, pos.character })

  -- Use corresponding command to generate call graph
  local opts = vim.deepcopy(require("call_graph").opts)
  local function on_generated_callback(buf_id, root_node_name)
    -- Update buf_id in history record
    for i, entry in ipairs(graph_history) do
      if entry == history_entry then
        graph_history[i].buf_id = buf_id
        break
      end
    end
  end

  -- Generate call graph based on call graph type
  Caller.generate_call_graph(opts, history_entry.call_type, on_generated_callback)

  -- Note: We don't need to restore original position, because generated call graph will become focus
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
    log.debug("[CallGraph] Graph generated")
    -- Determine if traversing through incoming edges
    local traverse_by_incoming = root_node and root_node.incoming_edges and #root_node.incoming_edges > 0
    caller.view:draw(root_node, traverse_by_incoming)
    local buf_id = caller.view.buf.bufid
    vim.notify("[CallGraph] graph generated", vim.log.levels.INFO)

    -- Save buffer ID to caller instance mapping
    buffer_caller_map[buf_id] = caller
    log.debug("[CallGraph] Added buffer " .. buf_id .. " to buffer-caller map")

    local root_node_name = root_node and root_node.text or "UnknownRoot"
    -- Pass full root_node, so position information can be saved
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
function Caller.mark_node_under_cursor()
  -- If not in mark mode, automatically enter
  if not is_mark_mode_active then
    -- Record current buffer
    local current_buf = vim.api.nvim_get_current_buf()

    -- Check buffer_caller_map content
    local map_keys = {}
    local has_current_buf = false
    for k, _ in pairs(buffer_caller_map) do
      table.insert(map_keys, k)
      if k == current_buf then
        has_current_buf = true
      end
    end

    -- First check if current buffer exists in mapping table
    if buffer_caller_map[current_buf] then
      -- If current buffer is known graph buffer, ensure g_caller points to correct instance
      g_caller = buffer_caller_map[current_buf]
    end

    -- Check g_caller validity
    if
      not g_caller
      or not g_caller.view
      or not g_caller.view.buf
      or not vim.api.nvim_buf_is_valid(g_caller.view.buf.bufid)
    then
      vim.notify("[CallGraph] No active call graph to mark.", vim.log.levels.WARN)
      return
    end

    -- Check if current buffer is g_caller's managed buffer
    if vim.api.nvim_get_current_buf() ~= g_caller.view.buf.bufid then
      vim.notify("[CallGraph] Mark mode must be started from an active call graph window.", vim.log.levels.WARN)
      return
    end

    -- Enter mark mode
    is_mark_mode_active = true
    marked_node_ids = {}

    -- Get graph data
    if g_caller.view.get_drawn_graph_data then
      local graph_data = g_caller.view:get_drawn_graph_data()

      current_graph_nodes_for_marking = graph_data.nodes
      current_graph_edges_for_marking = graph_data.edges
    else
      if g_caller.data and g_caller.data.nodes_map and g_caller.data.edges_list then
        current_graph_nodes_for_marking = g_caller.data.nodes_map
        current_graph_edges_for_marking = g_caller.data.edges_list
      else
        vim.notify("[CallGraph] Could not retrieve current graph data for marking.", vim.log.levels.ERROR)
        is_mark_mode_active = false
        return
      end
    end

    current_graph_view_for_marking = g_caller.view

    vim.notify("[CallGraph] Mark mode started. Use CallGraphMarkNode to select nodes.", vim.log.levels.INFO)

    -- Clear any previous marks
    if current_graph_view_for_marking and current_graph_view_for_marking.clear_marked_node_highlights then
      current_graph_view_for_marking:clear_marked_node_highlights()
    end
  end

  -- Ensure we're in the correct graph buffer
  if
    not current_graph_view_for_marking or vim.api.nvim_get_current_buf() ~= current_graph_view_for_marking.buf.bufid
  then
    vim.notify("[CallGraph] Not in the correct call graph window for marking.", vim.log.levels.WARN)
    is_mark_mode_active = false -- If context lost, exit mark mode
    marked_node_ids = {}
    return
  end

  -- Ensure there's a method to get node at cursor
  if not current_graph_view_for_marking.get_node_at_cursor then
    vim.notify("[CallGraph] Internal error: Cannot get node at cursor (view function missing).", vim.log.levels.ERROR)
    return
  end

  -- Get node at cursor
  local node = current_graph_view_for_marking:get_node_at_cursor()

  if node and node.nodeid then
    -- Check if already marked
    local already_marked = false
    for i, id in ipairs(marked_node_ids) do
      if id == node.nodeid then
        table.remove(marked_node_ids, i)
        already_marked = true
        break
      end
    end

    if not already_marked then
      -- If first mark, directly add
      if #marked_node_ids == 0 then
        table.insert(marked_node_ids, node.nodeid)
        vim.notify(
          string.format("[CallGraph] Root node '%s' (ID: %d) marked.", node.text, node.nodeid),
          vim.log.levels.INFO
        )
      else
        -- Allow nodes directly connected to any marked node to be marked
        local can_mark = false
        for _, marked_id in ipairs(marked_node_ids) do
          local marked_node = current_graph_nodes_for_marking[marked_id]
          -- Check if directly connected (regardless of direction)
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
          -- Reverse: New node's out/in edges also need to be checked
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
          if can_mark then
            break
          end
        end
        if can_mark then
          table.insert(marked_node_ids, node.nodeid)
          vim.notify(
            string.format("[CallGraph] Node '%s' (ID: %d) marked.", node.text, node.nodeid),
            vim.log.levels.INFO
          )
        else
          vim.notify(
            string.format(
              "[CallGraph] Cannot mark node '%s' (ID: %d). It must be directly connected to any marked node.",
              node.text,
              node.nodeid
            ),
            vim.log.levels.WARN
          )
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

  -- Get current view
  local current_view = current_graph_view_for_marking
  if not current_view then
    log.warn("No active view found")
    return
  end

  -- Clear original graph highlights
  if current_view.clear_marked_node_highlights then
    current_view:clear_marked_node_highlights()
  end

  -- Get current graph's nodes and edges data
  local nodes = current_graph_nodes_for_marking
  local edges = current_graph_edges_for_marking

  if not nodes or not edges then
    log.warn("Failed to get graph data")
    return
  end

  -- Get marked node IDs
  local marked_node_ids_array = {}
  for _, node_id in ipairs(marked_node_ids) do
    table.insert(marked_node_ids_array, node_id)
  end

  if #marked_node_ids_array < 2 then
    vim.notify("Please mark at least two nodes", vim.log.levels.WARN)
    return
  end

  -- Generate subgraph
  local subgraph = generate_subgraph(marked_node_ids_array, nodes, edges)
  if not subgraph then
    vim.notify("Subgraph generation failed", vim.log.levels.ERROR)
    return
  end

  -- Create new view and draw subgraph
  local new_view = CallGraphView:new()

  -- Determine if traversing through incoming edges
  local traverse_by_incoming = subgraph.root_node
    and subgraph.root_node.incoming_edges
    and #subgraph.root_node.incoming_edges > 0

  -- Use subgraph's root node as drawing starting point
  new_view:draw(subgraph.root_node, traverse_by_incoming)

  -- Add subgraph to history
  if subgraph.root_node and new_view.buf and new_view.buf.bufid and vim.api.nvim_buf_is_valid(new_view.buf.bufid) then
    local root_node_name = subgraph.root_node.text or "Subgraph"

    -- Deep copy subgraph structure, ensure safe handling
    local subgraph_copy = vim.deepcopy(subgraph)

    -- Verify subgraph structure completeness
    if not subgraph_copy.nodes_map or not subgraph_copy.edges or not subgraph_copy.root_node then
      log.warn("Subgraph structure incomplete, cannot add to history")
      vim.notify("[CallGraph] Subgraph structure incomplete, cannot save to history", vim.log.levels.WARN)
      return
    end

    -- Ensure all node IDs in nodes_map are valid
    local fixed_nodes_map = {}
    for id, node in pairs(subgraph_copy.nodes_map) do
      if type(node) == "table" then
        fixed_nodes_map[id] = node
      else
        log.warn("Skipping non-table type node: " .. tostring(id))
      end
    end
    subgraph_copy.nodes_map = fixed_nodes_map

    -- Create history record entry for entire subgraph
    local history_entry = {
      buf_id = new_view.buf.bufid,
      root_node_name = root_node_name,
      call_type = Caller.CallType.SUBGRAPH_CALL,
      timestamp = os.time(),
      subgraph = subgraph_copy,
    }

    -- Insert into history at front
    table.insert(graph_history, 1, history_entry)

    -- If history exceeds max size, remove oldest
    if #graph_history > max_history_size then
      table.remove(graph_history, #graph_history)
    end

    -- Save history to file
    save_history_to_file()

    -- Export mermaid chart, ensure user can view latest chart
    local opts = require("call_graph").opts
    if opts.export_mermaid_graph then
      MermaidGraph.export(subgraph.root_node, mermaid_path)
    end

    vim.notify("[CallGraph] Subgraph generated and added to history", vim.log.levels.INFO)
  end

  -- Create new caller instance
  local new_caller = create_caller(nil, new_view)

  -- Save original g_caller reference
  local original_caller = g_caller

  -- Update global view
  g_caller = new_caller
  last_call_type = Caller.CallType.SUBGRAPH_CALL

  -- Save buffer ID to caller instance mapping
  if new_view.buf and new_view.buf.bufid then
    buffer_caller_map[new_view.buf.bufid] = new_caller
    log.debug("[CallGraph] Added subgraph buffer " .. new_view.buf.bufid .. " to buffer_caller_map")
  end

  -- Ensure original graph buffer ID still maps to original caller instance
  if original_caller and original_caller.view and original_caller.view.buf and original_caller.view.buf.bufid then
    buffer_caller_map[original_caller.view.buf.bufid] = original_caller
    log.debug(
      "[CallGraph] Preserved original graph buffer " .. original_caller.view.buf.bufid .. " in buffer_caller_map"
    )
  end

  -- Clean mark state
  is_mark_mode_active = false
  marked_node_ids = {}
  current_graph_nodes_for_marking = nil
  current_graph_edges_for_marking = nil
  current_graph_view_for_marking = nil
end

-- Simplified subgraph generation function
function generate_subgraph(marked_node_ids, nodes, edges)
  log.debug("[CallGraph] Generating subgraph for marked nodes")

  if not marked_node_ids or not nodes or not edges then
    log.warn("Invalid input parameters")
    return nil
  end

  -- Collect subgraph's nodes and edges
  local subgraph_nodes = {}
  local subgraph_nodes_map = {}
  local subgraph_edges = {}
  local root_node = nil

  -- Add marked nodes, and build nodeid->node map
  for _, node_id in ipairs(marked_node_ids) do
    if nodes[node_id] then
      -- Deep copy node, ensure not modifying original data
      local node_copy = vim.deepcopy(nodes[node_id])
      -- Reset edge references
      node_copy.incoming_edges = {}
      node_copy.outcoming_edges = {}
      -- Ensure usr_data is correctly copied
      if nodes[node_id].usr_data then
        node_copy.usr_data = vim.deepcopy(nodes[node_id].usr_data)
      end
      -- Ensure pos_params is correctly copied
      if nodes[node_id].pos_params then
        node_copy.pos_params = vim.deepcopy(nodes[node_id].pos_params)
      end
      subgraph_nodes_map[node_id] = node_copy
      table.insert(subgraph_nodes, node_copy)

      -- Select level smallest node as root_node, or use first node
      if not root_node or (node_copy.level and (not root_node.level or node_copy.level < root_node.level)) then
        root_node = node_copy
      end
    end
  end

  -- Add connecting marked node edges, and correct new node's in/out edges
  for _, edge in ipairs(edges) do
    local from_id = edge.from_node.nodeid
    local to_id = edge.to_node.nodeid
    if subgraph_nodes_map[from_id] and subgraph_nodes_map[to_id] then
      -- Rebuild new edges, from/to pointing to new_nodes
      local Edge = require("call_graph.class.edge")
      -- Deep copy pos_params
      local pos_params = edge.pos_params and vim.deepcopy(edge.pos_params) or nil

      -- Special handling sub_edges, ensure each SubEdge is correctly initialized
      local sub_edges = {}
      if edge.sub_edges and #edge.sub_edges > 0 then
        local SubEdge = require("call_graph.class.subedge")
        for _, sub_edge_data in ipairs(edge.sub_edges) do
          if
            type(sub_edge_data) == "table"
            and sub_edge_data.start_row
            and sub_edge_data.start_col
            and sub_edge_data.end_row
            and sub_edge_data.end_col
          then
            local sub_edge = SubEdge:new(
              sub_edge_data.start_row,
              sub_edge_data.start_col,
              sub_edge_data.end_row,
              sub_edge_data.end_col
            )
            -- Ensure to_string method is correctly set
            if not sub_edge.to_string then
              sub_edge.to_string = SubEdge.to_string
            end
            table.insert(sub_edges, sub_edge)
          end
        end
      end

      local new_edge = Edge:new(subgraph_nodes_map[from_id], subgraph_nodes_map[to_id], pos_params, sub_edges)
      table.insert(subgraph_nodes_map[from_id].outcoming_edges, new_edge)
      table.insert(subgraph_nodes_map[to_id].incoming_edges, new_edge)
      table.insert(subgraph_edges, new_edge)
    end
  end

  log.debug("[CallGraph] Generated subgraph with " .. #subgraph_nodes .. " nodes and " .. #subgraph_edges .. " edges")

  return {
    root_node = root_node, -- Return a selected root node
    nodes_map = subgraph_nodes_map,
    nodes_list = subgraph_nodes,
    edges = subgraph_edges,
  }
end

Caller.generate_subgraph = generate_subgraph

-- Initialize load history
local function init()
  load_history_from_file()
end

-- Execute initialization when module loads
init()

-- Expose graph_history update function for testing
Caller._get_graph_history = function()
  return graph_history
end

-- Expose graph_history set function for testing
Caller._set_graph_history = function(history)
  graph_history = history
end

Caller._set_max_history_size = function(size)
  max_history_size = size
  -- If current history exceeds new size limit, trim
  while #graph_history > max_history_size do
    table.remove(graph_history)
  end
end

-- Expose history file path function for testing
Caller._get_history_file_path_func = function()
  return get_history_file_path
end

-- Expose load_history_from_file for testing
Caller.load_history_from_file = load_history_from_file

-- Expose save_history_to_file for testing
Caller.save_history_to_file = save_history_to_file

-- Expose add_to_history for testing
Caller.add_to_history = add_to_history

-- Add clear history function
function Caller.clear_history()
  -- Clear memory history
  graph_history = {}

  -- Get history file path
  local file_path = history_file_path()

  -- Try to clear history file (write empty content)
  local file = io.open(file_path, "w")
  if not file then
    vim.notify("[CallGraph] Cannot open history file for clearing operation: " .. file_path, vim.log.levels.ERROR)
    return false
  end

  -- Write empty content
  file:write("")
  file:close()

  vim.notify("[CallGraph] History cleared", vim.log.levels.INFO)
  return true
end

-- Add exit mark mode function
function Caller.exit_mark_mode()
  -- If not in mark mode, return directly
  if not is_mark_mode_active then
    vim.notify("[CallGraph] Mark mode is not active.", vim.log.levels.WARN)
    return
  end

  -- Get current view
  local current_view = current_graph_view_for_marking
  if current_view and current_view.clear_marked_node_highlights then
    -- Clear highlights
    current_view:clear_marked_node_highlights()
  end

  -- Reset all mark mode related states
  is_mark_mode_active = false
  marked_node_ids = {}
  current_graph_nodes_for_marking = nil
  current_graph_edges_for_marking = nil
  current_graph_view_for_marking = nil

  vim.notify("[CallGraph] Exited mark mode", vim.log.levels.INFO)
end

--- Create buffer switch event handler function, ensure g_caller always points to caller instance corresponding to current buffer
---@return function Returns a function to register to automatic command
function Caller.create_buffer_enter_handler()
  return function()
    local current_buf = vim.api.nvim_get_current_buf()
    -- Record current buffer information
    log.debug("Buffer enter event for buffer: " .. current_buf)

    -- Record current buffer_caller_map state
    local map_keys = {}
    for k, _ in pairs(buffer_caller_map) do
      table.insert(map_keys, k)
    end
    log.debug("buffer_caller_map keys: " .. vim.inspect(map_keys))

    -- If current buffer has corresponding caller instance, update g_caller
    if buffer_caller_map[current_buf] then
      local old_bufid = g_caller and g_caller.view and g_caller.view.buf and g_caller.view.buf.bufid or "nil"
      g_caller = buffer_caller_map[current_buf]
      log.debug("Updated g_caller from buffer " .. old_bufid .. " to " .. current_buf)
    else
      log.debug("Buffer " .. current_buf .. " not found in buffer_caller_map, g_caller unchanged")
    end
  end
end

return Caller
