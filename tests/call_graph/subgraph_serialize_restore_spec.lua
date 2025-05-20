local mock = require("tests.base_mock")
local Caller = require("call_graph.caller")
local Edge = require("call_graph.class.edge")
local SubEdge = require("call_graph.class.subedge")
local GraphNode = require("call_graph.class.graph_node")

-- Create a test suite for serialization and deserialization
describe("Subgraph serialization and restoration", function()
  local mock_fs = {}
  local history_file_path = "/Users/leo/Projects/call-graph.nvim/.call_graph_history.json"
  local original_history_path_func
  local test_history_data = nil

  -- Initialize test environment
  before_each(function()
    -- Backup original function
    original_history_path_func = Caller._get_history_file_path_func()

    -- Mock file system operations
    mock_fs.files = {}
    -- Ensure test history file path exists, note this path should match the return value of history_file_path()
    mock_fs.files[history_file_path] = ""

    -- Override io.open for testing
    _G.io.open = function(path, mode)
      print("io.open called, path: " .. path .. ", mode: " .. mode)
      if mode == "w" then
        mock_fs.files[path] = ""
        return {
          write = function(_, content)
            print("Writing to file " .. path .. ", content length: " .. #content)
            mock_fs.files[path] = content
          end,
          close = function()
            print("Closing file: " .. path)
          end,
        }
      elseif mode == "r" then
        if mock_fs.files[path] then
          print("Reading file: " .. path .. ", file exists")
          return {
            read = function(_)
              return mock_fs.files[path]
            end,
            close = function() end,
          }
        else
          print("Reading file: " .. path .. ", file does not exist")
          return nil
        end
      end
    end

    -- Modify history file path function to return fixed test file path
    Caller._get_history_file_path_func = function()
      return function()
        print("Getting history file path: " .. history_file_path)
        return history_file_path
      end
    end

    -- Ensure history is cleared before each test
    Caller._set_max_history_size(20)
    local history = Caller._get_graph_history()
    while #history > 0 do
      table.remove(history)
    end
  end)

  -- Clean up test environment
  after_each(function()
    -- Restore original function
    Caller._get_history_file_path_func = original_history_path_func
    -- Reset file mock
    mock_fs.files = {}
    -- Clear history
    local history = Caller._get_graph_history()
    while #history > 0 do
      table.remove(history)
    end
  end)

  -- Reset test data before each test case
  before_each(function()
    -- Clear history
    local history = Caller._get_graph_history()
    while #history > 0 do
      table.remove(history)
    end
    -- Clear mock file system
    mock_fs.files = {}
  end)

  -- Create a test graph structure (with nodes, edges, and subedges)
  local function create_test_graph()
    -- Create nodes
    local node1 = GraphNode:new("function1", {
      attr = {
        pos_params = {
          textDocument = { uri = "file:///test/source1.lua" },
          position = { line = 10, character = 5 },
        },
      },
    })

    local node2 = GraphNode:new("function2", {
      attr = {
        pos_params = {
          textDocument = { uri = "file:///test/source2.lua" },
          position = { line = 20, character = 15 },
        },
      },
    })

    local node3 = GraphNode:new("function3", {
      attr = {
        pos_params = {
          textDocument = { uri = "file:///test/source3.lua" },
          position = { line = 30, character = 25 },
        },
      },
    })

    -- Create subedges
    local sub_edge1 = SubEdge:new(0, 10, 1, 20)
    local sub_edge2 = SubEdge:new(1, 15, 2, 25)

    -- Create edges and associate subedges
    local edge1 = Edge:new(node1, node2, {
      textDocument = { uri = "file:///test/edge1.lua" },
      position = { line = 15, character = 10 },
    }, { sub_edge1 })

    local edge2 = Edge:new(node2, node3, {
      textDocument = { uri = "file:///test/edge2.lua" },
      position = { line = 25, character = 20 },
    }, { sub_edge2 })

    -- Set node connection relationships
    table.insert(node1.outcoming_edges, edge1)
    table.insert(node2.incoming_edges, edge1)
    table.insert(node2.outcoming_edges, edge2)
    table.insert(node3.incoming_edges, edge2)

    -- Return complete graph structure
    return {
      nodes_map = {
        [node1.nodeid] = node1,
        [node2.nodeid] = node2,
        [node3.nodeid] = node3,
      },
      edges = { edge1, edge2 },
      root_node = node1,
    }
  end

  -- Verify two graph structures are equal
  local function assert_graphs_equal(graph1, graph2)
    -- Check if node count is the same
    assert.are.equal(vim.tbl_count(graph1.nodes_map), vim.tbl_count(graph2.nodes_map))

    -- Check if edge count is the same
    assert.are.equal(#graph1.edges, #graph2.edges)

    -- Check if root node is the same (by text comparison)
    assert.are.equal(graph1.root_node.text, graph2.root_node.text)

    -- Check each node's text and position information
    for id, node1 in pairs(graph1.nodes_map) do
      local node2 = graph2.nodes_map[id]
      assert.is_not_nil(node2, "Node with ID " .. id .. " not found in second graph")
      assert.are.equal(node1.text, node2.text)

      -- Check incoming and outgoing edge counts
      assert.are.equal(#node1.incoming_edges, #node2.incoming_edges)
      assert.are.equal(#node1.outcoming_edges, #node2.outcoming_edges)
    end

    -- Check each edge's attributes
    for i, edge1 in ipairs(graph1.edges) do
      local edge2 = graph2.edges[i]

      -- Check edge's from_node and to_node
      assert.are.equal(edge1.from_node.text, edge2.from_node.text)
      assert.are.equal(edge1.to_node.text, edge2.to_node.text)

      -- Most important: Check sub_edges count and content
      assert.is_not_nil(edge1.sub_edges, "Edge1 sub_edges is nil")
      assert.is_not_nil(edge2.sub_edges, "Edge2 sub_edges is nil")
      assert.are.equal(#edge1.sub_edges, #edge2.sub_edges)

      for j, sub_edge1 in ipairs(edge1.sub_edges) do
        local sub_edge2 = edge2.sub_edges[j]

        -- Ensure both sub_edges have to_string method
        assert.is_not_nil(sub_edge1.to_string, "SubEdge1 missing to_string method")
        assert.is_not_nil(sub_edge2.to_string, "SubEdge2 missing to_string method")

        -- Verify sub_edge coordinate attributes
        assert.are.equal(sub_edge1.start_row, sub_edge2.start_row)
        assert.are.equal(sub_edge1.start_col, sub_edge2.start_col)
        assert.are.equal(sub_edge1.end_row, sub_edge2.end_row)
        assert.are.equal(sub_edge1.end_col, sub_edge2.end_col)
      end
    end
  end

  -- Test subgraph serialization and deserialization complete process
  it("should correctly serialize and restore subgraph with SubEdge objects", function()
    -- 1. Create test graph
    local test_graph = create_test_graph()

    -- 2. Simulate adding to history
    local history_entry = {
      buf_id = 101,
      root_node_name = test_graph.root_node.text,
      call_type = Caller.CallType.SUBGRAPH_CALL,
      timestamp = os.time(),
      subgraph = test_graph,
    }

    local history = Caller._get_graph_history()
    table.insert(history, 1, history_entry)

    -- 3. Save history to "file"
    print("Starting to save history...")
    Caller.save_history_to_file()

    -- Ensure data is correctly written to mock file system
    print("Checking if file exists: " .. tostring(mock_fs.files[history_file_path] ~= nil))
    print("File content length: " .. (mock_fs.files[history_file_path] and #mock_fs.files[history_file_path] or 0))
    assert.is_not_nil(mock_fs.files[history_file_path])
    assert.is_not.equal(mock_fs.files[history_file_path], "")

    -- 4. Clear history in memory
    while #history > 0 do
      table.remove(history)
    end
    assert.are.equal(0, #history)

    -- 5. Load history from "file"
    print("Starting to load history...")
    assert.is_not_nil(mock_fs.files[history_file_path], "History file should be created")
    assert.is_not.equal(mock_fs.files[history_file_path], "", "History file should not be empty")
    Caller.load_history_from_file()

    -- Get history reference again
    history = Caller._get_graph_history()

    -- 6. Verify if history is correctly loaded
    print("Number of history entries after loading: " .. #history)
    assert.are.equal(1, #history)
    assert.are.equal(Caller.CallType.SUBGRAPH_CALL, history[1].call_type)
    assert.are.equal(test_graph.root_node.text, history[1].root_node_name)

    -- 7. Get restored subgraph
    local restored_subgraph = history[1].subgraph
    print("Is restored subgraph nil: " .. tostring(restored_subgraph == nil))
    assert.is_not_nil(restored_subgraph, "Restored subgraph should not be nil")

    -- 8. Verify restored subgraph structure is correct
    assert_graphs_equal(test_graph, restored_subgraph)

    -- 9. Special verification that SubEdge:to_string method can be called normally
    for _, edge in ipairs(restored_subgraph.edges) do
      assert.is_not_nil(edge.sub_edges)
      for _, sub_edge in ipairs(edge.sub_edges) do
        local to_string_result = sub_edge:to_string()
        assert.is_not_nil(to_string_result)
        assert.is_not.equal(to_string_result, "")
      end
    end
  end)

  -- Test complete workflow: generate subgraph -> save -> restart -> load
  it("should correctly handle the complete workflow of subgraph generation, save, and restore", function()
    -- Simulate the entire process

    -- 1. Create original graph
    local original_graph = create_test_graph()

    -- 2. Select nodes to generate subgraph (here we select node1 and node2)
    local marked_node_ids = {}
    for id, node in pairs(original_graph.nodes_map) do
      if node.text == "function1" or node.text == "function2" then
        table.insert(marked_node_ids, id)
      end
    end

    -- 3. Generate subgraph
    local generated_subgraph = Caller.generate_subgraph(marked_node_ids, original_graph.nodes_map, original_graph.edges)

    assert.is_not_nil(generated_subgraph)
    assert.is_not_nil(generated_subgraph.root_node)

    -- 4. Add subgraph to history
    local history_entry = {
      buf_id = 102,
      root_node_name = generated_subgraph.root_node.text,
      call_type = Caller.CallType.SUBGRAPH_CALL,
      timestamp = os.time(),
      subgraph = generated_subgraph,
    }

    local history = Caller._get_graph_history()
    table.insert(history, 1, history_entry)

    -- 5. Save history to "file" (simulate saving state before restart)
    print("Test 2: Starting to save history...")
    Caller.save_history_to_file()

    -- Check if file is written correctly
    print("Test 2: Checking if file exists: " .. tostring(mock_fs.files[history_file_path] ~= nil))
    print(
      "Test 2: File content length: " .. (mock_fs.files[history_file_path] and #mock_fs.files[history_file_path] or 0)
    )

    -- 6. Clear history in memory (simulate restart)
    while #history > 0 do
      table.remove(history)
    end

    -- 7. Load history from "file" (simulate after restart)
    print("Test 2: Starting to load history...")
    assert.is_not_nil(mock_fs.files[history_file_path], "History file should be created")
    assert.is_not.equal(mock_fs.files[history_file_path], "", "History file should not be empty")
    Caller.load_history_from_file()

    -- Get history reference again
    history = Caller._get_graph_history()

    -- 8. Verify history is loaded correctly
    print("Test 2: Number of history entries after loading: " .. #history)
    assert.are.equal(1, #history)

    -- 9. Get restored subgraph
    local restored_subgraph = history[1].subgraph
    print("Test 2: Is restored subgraph nil: " .. tostring(restored_subgraph == nil))
    assert.is_not_nil(restored_subgraph, "Restored subgraph should not be nil")

    -- 10. Compare if original subgraph and restored subgraph are identical
    assert_graphs_equal(generated_subgraph, restored_subgraph)

    -- 11. Test Edge and SubEdge object methods again
    for _, edge in ipairs(restored_subgraph.edges) do
      -- Test Edge:to_string method
      local edge_to_string = edge:to_string()
      assert.is_not_nil(edge_to_string)

      -- Test Edge:is_same_edge method
      local is_same = edge:is_same_edge(edge)
      assert.is_true(is_same)

      -- Test SubEdge:to_string method
      for _, sub_edge in ipairs(edge.sub_edges) do
        local sub_edge_to_string = sub_edge:to_string()
        assert.is_not_nil(sub_edge_to_string)
      end
    end
  end)
end)
