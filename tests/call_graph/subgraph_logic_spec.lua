local FN = [[
-- This is a placeholder for the actual functions from caller.lua
-- In a real test setup, you would require the module and access these
-- functions, possibly through a test-specific export or by testing
-- them via the public API that calls them.

-- For the purpose of this generated test, we'll assume these functions
-- are available in the scope.
-- analyze_connectivity = require("call_graph.caller").analyze_connectivity (if it were exported)
-- generate_subgraph = require("call_graph.caller").generate_subgraph (if it were exported)

-- Pasted definitions for isolated testing:
function analyze_connectivity(original_nodes, original_edges, selected_node_ids)
  if not selected_node_ids or #selected_node_ids == 0 then
    return { is_connected = true, disconnected_nodes = {} }
  end
  if #selected_node_ids == 1 then
    return { is_connected = true, disconnected_nodes = {} }
  end

  local adj = {}
  local selected_nodes_set = {}
  for _, id in ipairs(selected_node_ids) do
    selected_nodes_set[id] = true
    adj[id] = {}
  end

  for _, edge in pairs(original_edges) do
    local from_id = edge.from_node.nodeid
    local to_id = edge.to_node.nodeid
    if selected_nodes_set[from_id] and selected_nodes_set[to_id] then
      table.insert(adj[from_id], to_id)
      table.insert(adj[to_id], from_id)
    end
  end

  local visited = {}
  local q = {}
  local start_node_id = selected_node_ids[1]
  table.insert(q, start_node_id)
  visited[start_node_id] = true
  local count_visited = 0

  while #q > 0 do
    local u = table.remove(q, 1)
    count_visited = count_visited + 1
    for _, v_id in ipairs(adj[u] or {}) do -- Added or {} for safety
      if selected_nodes_set[v_id] and not visited[v_id] then
        visited[v_id] = true
        table.insert(q, v_id)
      end
    end
  end
  
  if count_visited == #selected_node_ids then
    return { is_connected = true, disconnected_nodes = {} }
  else
    local disconnected = {}
    for _, id in ipairs(selected_node_ids) do
      if not visited[id] then
        table.insert(disconnected, id)
      end
    end
    return { is_connected = false, disconnected_nodes = disconnected }
  end
end

function generate_subgraph(original_nodes_map, original_edges_list, selected_node_ids)
  local subgraph_nodes_map = {}
  local subgraph_nodes_list = {} 
  local subgraph_edges = {}
  
  local selected_nodes_set = {}
  for _, id in ipairs(selected_node_ids) do
    selected_nodes_set[id] = true
  end

  for _, node_id in ipairs(selected_node_ids) do
    if original_nodes_map[node_id] then
      local original_node = original_nodes_map[node_id]
      local new_node = vim.deepcopy(original_node) 
      new_node.incoming_edges = {} 
      new_node.outcoming_edges = {}
      subgraph_nodes_map[node_id] = new_node
      table.insert(subgraph_nodes_list, new_node)
    end
  end

  for _, original_edge in ipairs(original_edges_list) do -- ipairs for list
    local from_node_id = original_edge.from_node.nodeid
    local to_node_id = original_edge.to_node.nodeid

    if selected_nodes_set[from_node_id] and selected_nodes_set[to_node_id] then
      local new_edge = vim.deepcopy(original_edge)
      new_edge.from_node = subgraph_nodes_map[from_node_id]
      new_edge.to_node = subgraph_nodes_map[to_node_id]  
      table.insert(subgraph_edges, new_edge)
      table.insert(subgraph_nodes_map[from_node_id].outcoming_edges, new_edge)
      table.insert(subgraph_nodes_map[to_node_id].incoming_edges, new_edge)
    end
  end
  
  local root_for_subgraph = nil
  if #subgraph_nodes_list > 0 then
    root_for_subgraph = subgraph_nodes_list[1] 
  end

  -- The caller.lua returns map for nodes, so let's stick to that for consistency
  return { root_node = root_for_subgraph, nodes = subgraph_nodes_map, edges = subgraph_edges } 
end
]]

-- 将FN设置到全局环境中
_G.FN = FN

describe("Subgraph Logic in call_graph.caller", function()
  -- Helper to create mock nodes
  local function create_node(id, text)
    return {
      nodeid = id,
      text = text or "Node" .. tostring(id),
      incoming_edges = {},
      outcoming_edges = {},
      -- usr_data, row, col, etc. can be added if needed
    }
  end

  -- Helper to create mock edges and link them
  local function create_edge(edge_id_counter, from_node, to_node)
    local edge = {
      edgeid = edge_id_counter,
      from_node = from_node,
      to_node = to_node,
    }
    table.insert(from_node.outcoming_edges, edge)
    table.insert(to_node.incoming_edges, edge)
    return edge
  end
  
  -- 自定义断言辅助函数
  local function is_empty(tbl)
    if type(tbl) ~= "table" then return false end
    return next(tbl) == nil
  end
  
  -- 改进的深拷贝函数，避免循环引用导致堆栈溢出
  local function safe_deepcopy(orig, seen)
    seen = seen or {}
    if type(orig) ~= 'table' then return orig end
    if seen[orig] then return seen[orig] end
    
    local copy = {}
    seen[orig] = copy
    
    for k, v in pairs(orig) do
      copy[k] = (type(v) == 'table') and safe_deepcopy(v, seen) or v
    end
    
    return setmetatable(copy, getmetatable(orig))
  end
  
  -- Load the functions to be tested (definitions pasted above for this example)
  -- In a real scenario, you might load them from the module if they are exposed for testing.
  local _G = _G -- Get global environment
  -- 兼容不同版本的Lua (5.1和5.2+)
  local load_fn = loadstring or load
  assert(load_fn(_G.FN))() -- Execute the pasted function definitions

  describe("analyze_connectivity", function()
    local n1, n2, n3, n4
    local nodes_map
    local edges_list
    local edge_id_counter

    before_each(function()
      n1 = create_node(1)
      n2 = create_node(2)
      n3 = create_node(3)
      n4 = create_node(4) -- isolated node
      nodes_map = { [n1.nodeid] = n1, [n2.nodeid] = n2, [n3.nodeid] = n3, [n4.nodeid] = n4 }
      edges_list = {}
      edge_id_counter = 1
      
      -- n1 -> n2, n2 -> n3
      table.insert(edges_list, create_edge(edge_id_counter, n1, n2)); edge_id_counter = edge_id_counter + 1
      table.insert(edges_list, create_edge(edge_id_counter, n2, n3)); edge_id_counter = edge_id_counter + 1
    end)

    it("should return connected for empty selection", function()
      local result = analyze_connectivity(nodes_map, edges_list, {})
      assert.is_true(result.is_connected)
      assert.are.same({}, result.disconnected_nodes)
    end)

    it("should return connected for single node selection", function()
      local result = analyze_connectivity(nodes_map, edges_list, {n1.nodeid})
      assert.is_true(result.is_connected)
    end)

    it("should identify connected nodes (n1, n2)", function()
      local result = analyze_connectivity(nodes_map, edges_list, {n1.nodeid, n2.nodeid})
      assert.is_true(result.is_connected)
    end)

    it("should identify connected nodes (n1, n2, n3)", function()
      local result = analyze_connectivity(nodes_map, edges_list, {n1.nodeid, n2.nodeid, n3.nodeid})
      assert.is_true(result.is_connected)
    end)

    it("should identify disconnected nodes (n1, n4)", function()
      local result = analyze_connectivity(nodes_map, edges_list, {n1.nodeid, n4.nodeid})
      assert.is_false(result.is_connected)
      assert.are.same({n4.nodeid}, result.disconnected_nodes) -- Assuming BFS starts from n1
    end)

    it("should identify disconnected nodes (n1, n3) if n2 is not selected", function()
        -- n1, n3 are connected via n2, but n2 is not in selected_node_ids
      local result = analyze_connectivity(nodes_map, edges_list, {n1.nodeid, n3.nodeid})
      assert.is_false(result.is_connected)
      -- Depending on BFS start, either n1 or n3 will be disconnected from the other
      -- If BFS starts at n1, n3 is disconnected.
      local disconnected_map = {}
      for _, id in ipairs(result.disconnected_nodes) do disconnected_map[id] = true end
      assert.is_true(disconnected_map[n1.nodeid] or disconnected_map[n3.nodeid])
      assert.equals(1, #result.disconnected_nodes) -- Only one of them should be listed as disconnected relative to the component found from the start node.
    end)
    
    it("should handle multiple disconnected components if selected (n1, n4, n2 but not n3)", function()
        -- Graph: 1-2-3, 4. Selected: 1, 2, 4. Edges exist between 1 and 2. 4 is isolated.
        local result = analyze_connectivity(nodes_map, edges_list, {n1.nodeid, n2.nodeid, n4.nodeid})
        assert.is_false(result.is_connected)
        -- If BFS starts from n1, it will find n2. n4 will be disconnected.
        assert.are.same({n4.nodeid}, result.disconnected_nodes)
    end)
  end)

  describe("generate_subgraph", function()
    local n1, n2, n3, n4
    local nodes_map
    local edges_list
    local edge_id_counter

    before_each(function()
      -- Mock vim.deepcopy with our safe implementation
      _G.vim = _G.vim or {}
      _G.vim.deepcopy = safe_deepcopy
      
      -- Mock vim.tbl_count for testing
      _G.vim.tbl_count = function(t)
        local count = 0
        for _, _ in pairs(t) do
          count = count + 1
        end
        return count
      end

      n1 = create_node(1, "Node1")
      n2 = create_node(2, "Node2")
      n3 = create_node(3, "Node3")
      n4 = create_node(4, "Node4")
      nodes_map = { [1]=n1, [2]=n2, [3]=n3, [4]=n4 }
      edges_list = {}
      edge_id_counter = 1
      
      table.insert(edges_list, create_edge(edge_id_counter, n1, n2)); edge_id_counter = edge_id_counter + 1 -- e1
      table.insert(edges_list, create_edge(edge_id_counter, n2, n3)); edge_id_counter = edge_id_counter + 1 -- e2
      table.insert(edges_list, create_edge(edge_id_counter, n1, n3)); edge_id_counter = edge_id_counter + 1 -- e3 (direct n1->n3)
    end)

    it("should return empty graph for no selected nodes", function()
      local subgraph = generate_subgraph(nodes_map, edges_list, {})
      assert.is_nil(subgraph.root_node)
      assert.equals(0, vim.tbl_count(subgraph.nodes))
      assert.equals(0, #subgraph.edges)
    end)

    it("should generate subgraph with a single node", function()
      local subgraph = generate_subgraph(nodes_map, edges_list, {n1.nodeid})
      assert.are.equal(n1.text, subgraph.root_node.text)
      assert.are.equal(1, vim.tbl_count(subgraph.nodes))
      assert.is_not_nil(subgraph.nodes[n1.nodeid])
      assert.equals(0, #subgraph.edges)
      assert.equals(0, #subgraph.nodes[n1.nodeid].incoming_edges)
      assert.equals(0, #subgraph.nodes[n1.nodeid].outcoming_edges)
      assert.is_not_equal(n1, subgraph.nodes[n1.nodeid]) -- Should be a deep copy
    end)

    it("should generate subgraph with two connected nodes (n1, n2)", function()
      local selected_ids = {n1.nodeid, n2.nodeid}
      local subgraph = generate_subgraph(nodes_map, edges_list, selected_ids)
      
      assert.are.equal(n1.text, subgraph.root_node.text)
      assert.are.equal(2, vim.tbl_count(subgraph.nodes))
      assert.is_not_nil(subgraph.nodes[n1.nodeid])
      assert.is_not_nil(subgraph.nodes[n2.nodeid])
      assert.are.equal(1, #subgraph.edges) -- Only edge n1->n2

      local sub_n1 = subgraph.nodes[n1.nodeid]
      local sub_n2 = subgraph.nodes[n2.nodeid]
      local sub_edge = subgraph.edges[1]

      assert.are.equal(sub_n1, sub_edge.from_node)
      assert.are.equal(sub_n2, sub_edge.to_node)
      
      assert.are.equal(1, #sub_n1.outcoming_edges)
      assert.are.same(sub_edge, sub_n1.outcoming_edges[1])
      assert.equals(0, #sub_n1.incoming_edges)

      assert.are.equal(1, #sub_n2.incoming_edges)
      assert.are.same(sub_edge, sub_n2.incoming_edges[1])
      assert.equals(0, #sub_n2.outcoming_edges)
    end)

    it("should generate subgraph with (n1, n2, n3) and all relevant edges", function()
      local selected_ids = {n1.nodeid, n2.nodeid, n3.nodeid}
      local subgraph = generate_subgraph(nodes_map, edges_list, selected_ids)
      
      assert.are.equal(n1.text, subgraph.root_node.text)
      assert.are.equal(3, vim.tbl_count(subgraph.nodes))
      assert.are.equal(3, #subgraph.edges) -- n1->n2, n2->n3, n1->n3

      local sub_n1 = subgraph.nodes[n1.nodeid]
      local sub_n2 = subgraph.nodes[n2.nodeid]
      local sub_n3 = subgraph.nodes[n3.nodeid]

      -- Check edges are connected to subgraph nodes
      for _, edge in ipairs(subgraph.edges) do
        assert.is_true(subgraph.nodes[edge.from_node.nodeid] == edge.from_node)
        assert.is_true(subgraph.nodes[edge.to_node.nodeid] == edge.to_node)
      end
      
      -- Check n1 (out: n2, n3)
      assert.are.equal(2, #sub_n1.outcoming_edges)
      assert.equals(0, #sub_n1.incoming_edges)

      -- Check n2 (in: n1, out: n3)
      assert.are.equal(1, #sub_n2.incoming_edges)
      assert.are.equal(1, #sub_n2.outcoming_edges)
      assert.are.equal(sub_n1, sub_n2.incoming_edges[1].from_node) -- from n1->n2
      assert.are.equal(sub_n3, sub_n2.outcoming_edges[1].to_node) -- from n2->n3

      -- Check n3 (in: n2, n1)
      assert.are.equal(2, #sub_n3.incoming_edges)
      assert.equals(0, #sub_n3.outcoming_edges)
    end)
    
    it("should not include edges to non-selected nodes", function()
      -- Original: n1 -> n2. Selected: {n1}.
      local selected_ids = {n1.nodeid}
      local subgraph = generate_subgraph(nodes_map, edges_list, selected_ids)
      assert.are.equal(1, vim.tbl_count(subgraph.nodes))
      assert.equals(0, #subgraph.edges)
      assert.equals(0, #subgraph.nodes[n1.nodeid].outcoming_edges)
    end)

  end)
end) 
