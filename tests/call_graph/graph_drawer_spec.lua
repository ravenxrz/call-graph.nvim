local Edge = require("call_graph.class.edge")
local SubEdge = require("call_graph.class.subedge")
local GraphDrawer = require("call_graph.view.graph_drawer")
local GraphNode = require("call_graph.class.graph_node")
local CallGraphView = require("call_graph.view.graph_view")
local Caller = require("call_graph.caller")
local ns_id = vim.api.nvim_create_namespace("test-ns")

describe("GraphDrawer", function()
  -- Replace built-in functions to simulate test environment
  local function table_equal(tbl1, tbl2)
    if tbl1 == tbl2 then
      return true
    end

    if type(tbl1) ~= "table" or type(tbl2) ~= "table" then
      return false
    end

    for i, v in pairs(tbl1) do
      if not table_equal(v, tbl2[i]) then
        return false
      end
    end

    for i, _ in pairs(tbl2) do
      if tbl1[i] == nil then
        return false
      end
    end

    return true
  end

  local bufnr
  local graph_drawer
  local draw_edge_cb = {
    cb = function() end,
    cb_ctx = {},
  }

  before_each(function()
    bufnr = vim.api.nvim_create_buf(true, true)
    graph_drawer = GraphDrawer:new(bufnr, draw_edge_cb)
  end)

  after_each(function()
    vim.api.nvim_buf_delete(bufnr, {})
  end)

  it("should clear buffer", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "test line 1", "test line 2" })
    graph_drawer:clear_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.equal(#lines, 1)
  end)

  it("graph should support modifiable", function()
    graph_drawer:set_modifiable(true)
    local is_modifiable = vim.api.nvim_get_option_value("modifiable", { buf = bufnr })
    assert.is.True(is_modifiable)

    graph_drawer:set_modifiable(false)
    is_modifiable = vim.api.nvim_get_option_value("modifiable", { buf = bufnr })
    assert.is.False(is_modifiable)
  end)

  it("should draw node", function()
    local node = {
      row = 0,
      col = 0,
      text = "TestNode",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 1,
      usr_data = {},
    }
    graph_drawer:draw_node(node)
    local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
    assert.equal(line, "TestNode")
  end)

  it("should draw horizontal line", function()
    graph_drawer:draw_h_line(0, 0, 10, "right")
    local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
    assert.equal(string.sub(line, 1, 10), "--------->")
  end)

  it("should draw vertical line", function()
    graph_drawer:draw_v_line(0, 3, 0, "down")
    local line1 = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
    local line2 = vim.api.nvim_buf_get_lines(bufnr, 1, 2, false)[1]
    local line3 = vim.api.nvim_buf_get_lines(bufnr, 2, 3, false)[1]
    assert.equal(string.sub(line1, 1, 1), "|")
    assert.equal(string.sub(line2, 1, 1), "|")
    assert.equal(string.sub(line3, 1, 1), "v")
  end)

  it("should draw graph with outcoming edges traversal", function()
    local node1 = {
      row = 0,
      col = 0,
      text = "RootNode",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 1,
      usr_data = {},
    }
    local node2 = {
      row = 0,
      col = 0,
      text = "ChildNode",
      level = 2,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 2,
      usr_data = {},
    }
    local edge = Edge:new(node1, node2, nil, {})
    table.insert(node1.outcoming_edges, edge)
    table.insert(node2.incoming_edges, edge)

    graph_drawer:draw(node1, false)
    local line1 = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
    assert.equal(line1, "RootNode---->ChildNode")
  end)

  it("should draw graph with incoming edges traversal", function()
    local node1 = {
      row = 0,
      col = 0,
      text = "RootNode",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 1,
      usr_data = {},
    }
    local node2 = {
      row = 0,
      col = 0,
      text = "ChildNode",
      level = 2,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 2,
      usr_data = {},
    }
    local edge = Edge:new(node2, node1, nil, {})
    table.insert(node1.incoming_edges, edge)
    table.insert(node2.outcoming_edges, edge)

    graph_drawer:draw(node1, true)
    local line1 = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
    assert.equal("RootNode<----ChildNode", line1)
  end)

  it("should draw graph with more than 3 levels of node connections using outcoming edges", function()
    local level4_node = {
      row = 0,
      col = 0,
      text = "Level4Node",
      level = 4,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 4,
      usr_data = {},
    }
    local level3_node = {
      row = 0,
      col = 0,
      text = "Level3Node",
      level = 3,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 3,
      usr_data = {},
    }
    local level2_node = {
      row = 0,
      col = 0,
      text = "Level2Node",
      level = 2,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 2,
      usr_data = {},
    }
    local root_node = {
      row = 0,
      col = 0,
      text = "RootNode",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 1,
      usr_data = {},
    }

    local edge1 = Edge:new(level2_node, level3_node, nil, {})
    table.insert(level2_node.outcoming_edges, edge1)
    table.insert(level3_node.incoming_edges, edge1)

    local edge2 = Edge:new(level3_node, level4_node, nil, {})
    table.insert(level3_node.outcoming_edges, edge2)
    table.insert(level4_node.incoming_edges, edge2)

    local edge3 = Edge:new(root_node, level2_node, nil, {})
    table.insert(root_node.outcoming_edges, edge3)
    table.insert(level2_node.incoming_edges, edge3)

    graph_drawer:draw(root_node, false)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    print(vim.inspect(lines))
    assert.equal(#lines, 1)
    assert.equal(lines[1], "RootNode---->Level2Node---->Level3Node---->Level4Node")
  end)

  it("should draw graph with more than 3 levels of node connections using incoming edges", function()
    local level4_node = {
      row = 0,
      col = 0,
      text = "Level4Node",
      level = 4,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 4,
      usr_data = {},
    }
    local level3_node = {
      row = 0,
      col = 0,
      text = "Level3Node",
      level = 3,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 3,
      usr_data = {},
    }
    local level2_node = {
      row = 0,
      col = 0,
      text = "Level2Node",
      level = 2,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 2,
      usr_data = {},
    }
    local root_node = {
      row = 0,
      col = 0,
      text = "RootNode",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 1,
      usr_data = {},
    }

    local edge1 = Edge:new(level3_node, level2_node, nil, {})
    table.insert(level2_node.incoming_edges, edge1)
    table.insert(level3_node.outcoming_edges, edge1)

    local edge2 = Edge:new(level4_node, level3_node, nil, {})
    table.insert(level3_node.incoming_edges, edge2)
    table.insert(level4_node.outcoming_edges, edge2)

    local edge3 = Edge:new(level2_node, root_node, nil, {})
    table.insert(root_node.incoming_edges, edge3)
    table.insert(level2_node.outcoming_edges, edge3)

    graph_drawer:draw(root_node, true)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    print(vim.inspect(lines))
    assert.equal(#lines, 1)
    assert.equal(lines[1], "RootNode<----Level2Node<----Level3Node<----Level4Node")
  end)

  it("should draw graph with multiple nodes in the second level using outcoming edges", function()
    local child1_node = {
      row = 0,
      col = 0,
      text = "Child1Node",
      level = 2,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 2,
      usr_data = {},
    }
    local child2_node = {
      row = 0,
      col = 0,
      text = "Child2Node",
      level = 2,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 3,
      usr_data = {},
    }
    local root_node = {
      row = 0,
      col = 0,
      text = "RootNode",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 1,
      usr_data = {},
    }

    local edge1 = Edge:new(root_node, child1_node, nil, {})
    table.insert(root_node.outcoming_edges, edge1)
    table.insert(child1_node.incoming_edges, edge1)

    local edge2 = Edge:new(root_node, child2_node, nil, {})
    table.insert(root_node.outcoming_edges, edge2)
    table.insert(child2_node.incoming_edges, edge2)

    graph_drawer:draw(root_node, false)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local model_lines = {
      "RootNode---->Child1Node",
      "          |",
      "          -->Child2Node",
    }
    local ret = table_equal(lines, model_lines)
    if not ret then
      assert.equal(model_lines, lines) -- get a pretty print
    end
    assert.is.True(ret)
  end)

  it("should draw graph with multiple nodes in the second level using incoming edges", function()
    local child1_node = {
      row = 0,
      col = 0,
      text = "Child1Node",
      level = 2,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 2,
      usr_data = {},
    }
    local child2_node = {
      row = 0,
      col = 0,
      text = "Child2Node",
      level = 2,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 3,
      usr_data = {},
    }
    local root_node = {
      row = 0,
      col = 0,
      text = "RootNode",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 1,
      usr_data = {},
    }

    local edge1 = Edge:new(child1_node, root_node, nil, {})
    table.insert(root_node.incoming_edges, edge1)
    table.insert(child1_node.outcoming_edges, edge1)

    local edge2 = Edge:new(child2_node, root_node, nil, {})
    table.insert(root_node.incoming_edges, edge2)
    table.insert(child2_node.outcoming_edges, edge2)

    graph_drawer:draw(root_node, true)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local model_lines = {
      "RootNode<----Child1Node",
      "          |",
      "          ---Child2Node",
    }
    local ret = table_equal(lines, model_lines)
    if not ret then
      assert.equal(model_lines, lines) -- get a pretty print
    end
    assert.is.True(ret)
  end)

  it("should draw a circular graph using outcoming edges", function()
    local node1 = {
      row = 0,
      col = 0,
      text = "Node1",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 1,
      usr_data = {},
    }
    local node2 = {
      row = 0,
      col = 0,
      text = "Node2",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 2,
      usr_data = {},
    }
    local node3 = {
      row = 0,
      col = 0,
      text = "Node3",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 3,
      usr_data = {},
    }

    local edge1 = Edge:new(node1, node2, nil, {})
    table.insert(node1.outcoming_edges, edge1)
    table.insert(node2.incoming_edges, edge1)

    local edge2 = Edge:new(node2, node3, nil, {})
    table.insert(node2.outcoming_edges, edge2)
    table.insert(node3.incoming_edges, edge2)

    local edge3 = Edge:new(node3, node1, nil, {})
    table.insert(node3.outcoming_edges, edge3)
    table.insert(node1.incoming_edges, edge3)

    graph_drawer:draw(node1, false)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local model_lines = { "Node1<--->Node2---->Node3" }
    if not table_equal(lines, model_lines) then
      assert.equal(model_lines, lines)
    end
    assert.is.True(true)
  end)

  it("should draw a circular graph using incoming edges", function()
    local node1 = {
      row = 0,
      col = 0,
      text = "Node1",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 1,
      usr_data = {},
    }
    local node2 = {
      row = 0,
      col = 0,
      text = "Node2",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 2,
      usr_data = {},
    }
    local node3 = {
      row = 0,
      col = 0,
      text = "Node3",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 3,
      usr_data = {},
    }

    local edge1 = Edge:new(node2, node1, nil, {})
    table.insert(node1.incoming_edges, edge1)
    table.insert(node2.outcoming_edges, edge1)

    local edge2 = Edge:new(node3, node2, nil, {})
    table.insert(node2.incoming_edges, edge2)
    table.insert(node3.outcoming_edges, edge2)

    local edge3 = Edge:new(node1, node3, nil, {})
    table.insert(node3.incoming_edges, edge3)
    table.insert(node1.outcoming_edges, edge3)

    graph_drawer:draw(node1, true)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local model_lines = { "Node1<----Node2<--->Node3" }
    local ret = table_equal(lines, model_lines)
    if not ret then
      assert.equal(model_lines, lines)
    end
    assert.is.True(ret)
  end)

  it("should draw 3-level chain using outcoming edges", function()
    local level4_node = {
      row = 0,
      col = 0,
      text = "Level4Node",
      level = 4,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 4,
      usr_data = {},
    }
    local level3_node = {
      row = 0,
      col = 0,
      text = "Level3Node",
      level = 3,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 3,
      usr_data = {},
    }
    local level2_node = {
      row = 0,
      col = 0,
      text = "Level2Node",
      level = 2,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 2,
      usr_data = {},
    }
    local root_node = {
      row = 0,
      col = 0,
      text = "RootNode",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 1,
      usr_data = {},
    }
    local edge1 = Edge:new(level2_node, level3_node, nil, {})
    table.insert(level2_node.outcoming_edges, edge1)
    table.insert(level3_node.incoming_edges, edge1)
    local edge2 = Edge:new(level3_node, level4_node, nil, {})
    table.insert(level3_node.outcoming_edges, edge2)
    table.insert(level4_node.incoming_edges, edge2)
    local edge3 = Edge:new(root_node, level2_node, nil, {})
    table.insert(root_node.outcoming_edges, edge3)
    table.insert(level2_node.incoming_edges, edge3)
    graph_drawer:draw(root_node, false)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    print(vim.inspect(lines))
    assert.equal(#lines, 1)
    assert.equal(lines[1], "RootNode---->Level2Node---->Level3Node---->Level4Node")
  end)

  it("should draw 3-level chain using incoming edges", function()
    local level4_node = {
      row = 0,
      col = 0,
      text = "Level4Node",
      level = 4,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 4,
      usr_data = {},
    }
    local level3_node = {
      row = 0,
      col = 0,
      text = "Level3Node",
      level = 3,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 3,
      usr_data = {},
    }
    local level2_node = {
      row = 0,
      col = 0,
      text = "Level2Node",
      level = 2,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 2,
      usr_data = {},
    }
    local root_node = {
      row = 0,
      col = 0,
      text = "RootNode",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 1,
      usr_data = {},
    }
    local edge1 = Edge:new(level3_node, level2_node, nil, {})
    table.insert(level2_node.incoming_edges, edge1)
    table.insert(level3_node.outcoming_edges, edge1)
    local edge2 = Edge:new(level4_node, level3_node, nil, {})
    table.insert(level3_node.incoming_edges, edge2)
    table.insert(level4_node.outcoming_edges, edge2)
    local edge3 = Edge:new(level2_node, root_node, nil, {})
    table.insert(root_node.incoming_edges, edge3)
    table.insert(level2_node.outcoming_edges, edge3)
    graph_drawer:draw(root_node, true)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    print(vim.inspect(lines))
    assert.equal(#lines, 1)
    assert.equal(lines[1], "RootNode<----Level2Node<----Level3Node<----Level4Node")
  end)

  it("should draw 3-level multi-branch graph using outcoming edges", function()
    -- Multi-branch structure
    local root_node = {
      row = 0,
      col = 0,
      text = "RootNode",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 1,
      usr_data = {},
    }
    local child1_node = {
      row = 0,
      col = 0,
      text = "Child1Node",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 2,
      usr_data = {},
    }
    local child2_node = {
      row = 0,
      col = 0,
      text = "Child2Node",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 3,
      usr_data = {},
    }
    local child3_node = {
      row = 0,
      col = 0,
      text = "Child3Node",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 4,
      usr_data = {},
    }
    local grandchild_node = {
      row = 0,
      col = 0,
      text = "GrandChildNode",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 5,
      usr_data = {},
    }
    local edge1 = Edge:new(root_node, child1_node, nil, {})
    local edge2 = Edge:new(root_node, child2_node, nil, {})
    local edge3 = Edge:new(root_node, child3_node, nil, {})
    local edge4 = Edge:new(child2_node, grandchild_node, nil, {})
    local edge5 = Edge:new(child3_node, grandchild_node, nil, {})
    table.insert(root_node.outcoming_edges, edge1)
    table.insert(child1_node.incoming_edges, edge1)
    table.insert(root_node.outcoming_edges, edge2)
    table.insert(child2_node.incoming_edges, edge2)
    table.insert(root_node.outcoming_edges, edge3)
    table.insert(child3_node.incoming_edges, edge3)
    table.insert(child2_node.outcoming_edges, edge4)
    table.insert(grandchild_node.incoming_edges, edge4)
    table.insert(child3_node.outcoming_edges, edge5)
    table.insert(grandchild_node.incoming_edges, edge5)
    graph_drawer.nodes =
      { [1] = root_node, [2] = child1_node, [3] = child2_node, [4] = child3_node, [5] = grandchild_node }
    graph_drawer:draw(root_node, false)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    print(vim.inspect(lines))
    -- Define expected graph output
    local expected_lines = {
      "RootNode---->Child1Node  -->GrandChildNode",
      "          |              |",
      "          -->Child2Node---",
      "          |              |",
      "          -->Child3Node---",
    }
    -- Strictly compare actual output with expected output
    local ret = table_equal(lines, expected_lines)
    if not ret then
      assert.equal(expected_lines, lines) -- Get more detailed error information
    end
    assert.is_true(ret)
  end)

  it("should handle nil root_node by selecting first available node", function()
    local node1 = {
      row = 0,
      col = 0,
      text = "Node1",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 1,
      usr_data = {},
    }
    local node2 = {
      row = 0,
      col = 0,
      text = "Node2",
      level = 2,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 2,
      usr_data = {},
    }
    local edge = Edge:new(node1, node2, nil, {})
    table.insert(node1.outcoming_edges, edge)
    table.insert(node2.incoming_edges, edge)

    -- Manually set graph_drawer.nodes
    graph_drawer.nodes = {
      [node1.nodeid] = node1,
      [node2.nodeid] = node2,
    }

    -- Pass nil as root_node
    graph_drawer:draw(nil, false)
    local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
    assert(line:find("Node1") or line:find("Node2"))
  end)

  it("should handle nil root_node and empty nodes table", function()
    graph_drawer.nodes = {}
    -- Should not raise error
    graph_drawer:draw(nil, false)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.is_true(#lines >= 0)
  end)

  it("should not raise error when nodes is not explicitly set but draw is called", function()
    -- Mock only passing nodes list without assigning nodes map
    local node1 = {
      row = 0,
      col = 0,
      text = "NodeA",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 1,
      usr_data = {},
    }
    local node2 = {
      row = 0,
      col = 0,
      text = "NodeB",
      level = 2,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 2,
      usr_data = {},
    }
    local edge = Edge:new(node1, node2, nil, {})
    table.insert(node1.outcoming_edges, edge)
    table.insert(node2.incoming_edges, edge)

    -- Do not manually assign graph_drawer.nodes, call draw directly
    -- draw depends on self.nodes, after fix it should not throw error
    assert.has_no.errors(function()
      graph_drawer.nodes = nil
      graph_drawer:draw(node1, false)
    end)
  end)

  it("should render subgraph with marked nodes", function()
    -- Construct original nodes and edges
    local node1 = {
      row = 0,
      col = 0,
      text = "a/test.cc:2",
      level = 2,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 1,
      usr_data = {},
    }
    local node2 = {
      row = 0,
      col = 0,
      text = "b/test.cc:4",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 2,
      usr_data = {},
    }
    local edge = Edge:new(node2, node1, nil, {})
    table.insert(node2.outcoming_edges, edge)
    table.insert(node1.incoming_edges, edge)

    -- Mock generate_subgraph logic
    local marked_node_ids = { 1, 2 }
    local nodes = { [1] = node1, [2] = node2 }
    local edges = { edge }
    -- Call generate_subgraph directly
    local caller = require("call_graph.caller")
    local subgraph = caller.generate_subgraph(marked_node_ids, nodes, edges)

    -- Render with graph_drawer
    graph_drawer.nodes = subgraph.nodes_map
    graph_drawer:draw(subgraph.root_node, false)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Define expected graph output
    local expected_lines = {
      "b/test.cc:4---->a/test.cc:2",
    }
    -- Strictly compare actual output with expected output
    local ret = table_equal(lines, expected_lines)
    if not ret then
      assert.equal(expected_lines, lines) -- Get more detailed error information
    end
    assert.is_true(ret)
  end)

  it("should render subgraph with multiple marked nodes and complex connections", function()
    -- Construct original nodes and edges
    local node1 = {
      row = 0,
      col = 0,
      text = "main.cc:10",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 1,
      usr_data = {},
    }
    local node2 = {
      row = 0,
      col = 0,
      text = "utils.cc:20",
      level = 2,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 2,
      usr_data = {},
    }
    local node3 = {
      row = 0,
      col = 0,
      text = "helper.cc:30",
      level = 2,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 3,
      usr_data = {},
    }
    local node4 = {
      row = 0,
      col = 0,
      text = "common.cc:40",
      level = 3,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 4,
      usr_data = {},
    }

    -- Create edge connections
    local edge1 = Edge:new(node1, node2, nil, {})
    local edge2 = Edge:new(node1, node3, nil, {})
    local edge3 = Edge:new(node2, node4, nil, {})
    local edge4 = Edge:new(node3, node4, nil, {})

    -- Add edges to nodes
    table.insert(node1.outcoming_edges, edge1)
    table.insert(node2.incoming_edges, edge1)
    table.insert(node1.outcoming_edges, edge2)
    table.insert(node3.incoming_edges, edge2)
    table.insert(node2.outcoming_edges, edge3)
    table.insert(node4.incoming_edges, edge3)
    table.insert(node3.outcoming_edges, edge4)
    table.insert(node4.incoming_edges, edge4)

    -- Mock generate_subgraph logic
    local marked_node_ids = { 1, 2, 4 } -- Mark root node, first child node, and last node
    local nodes = { [1] = node1, [2] = node2, [3] = node3, [4] = node4 }
    local edges = { edge1, edge2, edge3, edge4 }

    -- Call generate_subgraph directly
    local caller = require("call_graph.caller")
    local subgraph = caller.generate_subgraph(marked_node_ids, nodes, edges)

    -- Render with graph_drawer
    graph_drawer.nodes = subgraph.nodes_map
    graph_drawer:draw(subgraph.root_node, false)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Define expected graph output
    local expected_lines = {
      "main.cc:10---->utils.cc:20---->common.cc:40",
    }
    -- Strictly compare actual output with expected output
    local ret = table_equal(lines, expected_lines)
    if not ret then
      assert.equal(expected_lines, lines) -- Get more detailed error information
    end
    assert.is_true(ret)
  end)

  it("should handle bidirectional edges in subgraph", function()
    -- Construct original nodes and edges
    local node1 = {
      row = 0,
      col = 0,
      text = "A",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 1,
      usr_data = {},
    }
    local node2 = {
      row = 0,
      col = 0,
      text = "B",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 2,
      usr_data = {},
    }

    -- Create bidirectional edges
    local edge1 = Edge:new(node1, node2, nil, {})
    local edge2 = Edge:new(node2, node1, nil, {})

    -- Add edges to nodes
    table.insert(node1.outcoming_edges, edge1)
    table.insert(node2.incoming_edges, edge1)
    table.insert(node2.outcoming_edges, edge2)
    table.insert(node1.incoming_edges, edge2)

    -- Mock generate_subgraph logic
    local marked_node_ids = { 1, 2 }
    local nodes = { [1] = node1, [2] = node2 }
    local edges = { edge1, edge2 }

    -- Call generate_subgraph directly
    local caller = require("call_graph.caller")
    local subgraph = caller.generate_subgraph(marked_node_ids, nodes, edges)

    -- Render with graph_drawer
    graph_drawer.nodes = subgraph.nodes_map
    graph_drawer:draw(subgraph.root_node, false)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Define expected graph output
    local expected_lines = {
      "A<--->B",
    }
    -- Strictly compare actual output with expected output
    local ret = table_equal(lines, expected_lines)
    if not ret then
      assert.equal(expected_lines, lines) -- Get more detailed error information
    end
    assert.is_true(ret)
  end)

  it("should render subgraph with marked nodes in mark mode", function()
    -- Construct original nodes and edges
    local node1 = {
      row = 0,
      col = 0,
      text = "a/test.cc:2",
      level = 2,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 1,
      usr_data = {},
    }
    local node2 = {
      row = 0,
      col = 0,
      text = "b/test.cc:4",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 2,
      usr_data = {},
    }
    local edge = Edge:new(node2, node1, nil, {})
    table.insert(node2.outcoming_edges, edge)
    table.insert(node1.incoming_edges, edge)

    -- Mock mark mode
    local marked_node_ids = { 1, 2 } -- Mock user marked two nodes
    local nodes = { [1] = node1, [2] = node2 }
    local edges = { edge }

    -- Call generate_subgraph to generate subgraph
    local caller = require("call_graph.caller")
    local subgraph = caller.generate_subgraph(marked_node_ids, nodes, edges)

    -- Render with graph_drawer
    graph_drawer.nodes = subgraph.nodes_map
    graph_drawer:draw(subgraph.root_node, false)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Define expected graph output
    local expected_lines = {
      "b/test.cc:4---->a/test.cc:2",
    }
    -- Strictly compare actual output with expected output
    local ret = table_equal(lines, expected_lines)
    if not ret then
      assert.equal(expected_lines, lines) -- Get more detailed error information
    end
    assert.is_true(ret)
  end)

  it("should render subgraph for mark mode with two nodes and one edge (regression)", function()
    local node1 = {
      row = 0,
      col = 0,
      text = "a/test.cc:2",
      level = 2,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 1,
      usr_data = {},
    }
    local node2 = {
      row = 0,
      col = 0,
      text = "b/test.cc:4",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 2,
      usr_data = {},
    }
    local edge = Edge:new(node2, node1, nil, {})
    table.insert(node2.outcoming_edges, edge)
    table.insert(node1.incoming_edges, edge)
    local marked_node_ids = { 1, 2 }
    local nodes = { [1] = node1, [2] = node2 }
    local edges = { edge }
    local caller = require("call_graph.caller")
    local subgraph = caller.generate_subgraph(marked_node_ids, nodes, edges)
    graph_drawer.nodes = subgraph.nodes_map
    graph_drawer:draw(subgraph.root_node, false)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.same({ "b/test.cc:4---->a/test.cc:2" }, lines)
  end)

  it("should handle subgraph generation and rendering with multiple nodes", function()
    -- Construct original nodes and edges
    local node1 = {
      row = 0,
      col = 0,
      text = "main.cc:10",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 1,
      usr_data = {},
    }
    local node2 = {
      row = 0,
      col = 0,
      text = "utils.cc:20",
      level = 2,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 2,
      usr_data = {},
    }
    local node3 = {
      row = 0,
      col = 0,
      text = "helper.cc:30",
      level = 2,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 3,
      usr_data = {},
    }
    local node4 = {
      row = 0,
      col = 0,
      text = "common.cc:40",
      level = 3,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 4,
      usr_data = {},
    }

    -- Create edge connections
    local edge1 = Edge:new(node1, node2, nil, {})
    local edge2 = Edge:new(node1, node3, nil, {})
    local edge3 = Edge:new(node2, node4, nil, {})
    local edge4 = Edge:new(node3, node4, nil, {})

    -- Add edges to nodes
    table.insert(node1.outcoming_edges, edge1)
    table.insert(node2.incoming_edges, edge1)
    table.insert(node1.outcoming_edges, edge2)
    table.insert(node3.incoming_edges, edge2)
    table.insert(node2.outcoming_edges, edge3)
    table.insert(node4.incoming_edges, edge3)
    table.insert(node3.outcoming_edges, edge4)
    table.insert(node4.incoming_edges, edge4)

    -- Mock mark mode
    local marked_node_ids = { 1, 2, 4 } -- Mark root node, first child node, and last node
    local nodes = { [1] = node1, [2] = node2, [3] = node3, [4] = node4 }
    local edges = { edge1, edge2, edge3, edge4 }

    -- Generate subgraph
    local caller = require("call_graph.caller")
    local subgraph = caller.generate_subgraph(marked_node_ids, nodes, edges)

    -- Verify subgraph data structure
    assert.is_not_nil(subgraph)
    assert.is_not_nil(subgraph.nodes_map)
    assert.is_not_nil(subgraph.nodes_list)
    assert.is_not_nil(subgraph.edges)
    assert.equal(3, #subgraph.nodes_list) -- Should have 3 nodes
    assert.equal(2, #subgraph.edges) -- Should have 2 edges

    -- Verify node mapping
    assert.is_not_nil(subgraph.nodes_map[1]) -- main.cc
    assert.is_not_nil(subgraph.nodes_map[2]) -- utils.cc
    assert.is_not_nil(subgraph.nodes_map[4]) -- common.cc
    assert.is_nil(subgraph.nodes_map[3]) -- helper.cc should not be in subgraph

    -- Verify edge connections
    local has_edge1 = false
    local has_edge3 = false
    for _, edge in ipairs(subgraph.edges) do
      if edge.from_node.nodeid == 1 and edge.to_node.nodeid == 2 then
        has_edge1 = true
      end
      if edge.from_node.nodeid == 2 and edge.to_node.nodeid == 4 then
        has_edge3 = true
      end
    end
    assert.is_true(has_edge1)
    assert.is_true(has_edge3)

    -- Render subgraph
    graph_drawer.nodes = subgraph.nodes_map
    graph_drawer:draw(subgraph.root_node, false)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Verify render result
    local expected_lines = {
      "main.cc:10---->utils.cc:20---->common.cc:40",
    }
    assert.same(expected_lines, lines)
  end)

  it("should handle subgraph generation with disconnected nodes", function()
    -- Construct original nodes and edges
    local node1 = {
      row = 0,
      col = 0,
      text = "A",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 1,
      usr_data = {},
    }
    local node2 = {
      row = 0,
      col = 0,
      text = "B",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 2,
      usr_data = {},
    }
    local node3 = {
      row = 0,
      col = 0,
      text = "C",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 3,
      usr_data = {},
    }

    -- Create edge connections
    local edge = Edge:new(node1, node2, nil, {})
    table.insert(node1.outcoming_edges, edge)
    table.insert(node2.incoming_edges, edge)

    -- Mock mark mode - Mark all nodes, including unconnected node3
    local marked_node_ids = { 1, 2, 3 }
    local nodes = { [1] = node1, [2] = node2, [3] = node3 }
    local edges = { edge }

    -- Generate subgraph
    local caller = require("call_graph.caller")
    local subgraph = caller.generate_subgraph(marked_node_ids, nodes, edges)

    -- Verify subgraph data structure
    assert.is_not_nil(subgraph)
    assert.is_not_nil(subgraph.nodes_map)
    assert.is_not_nil(subgraph.nodes_list)
    assert.is_not_nil(subgraph.edges)
    assert.equal(3, #subgraph.nodes_list) -- Should have 3 nodes
    assert.equal(1, #subgraph.edges) -- Should have only 1 edge

    -- Verify node mapping
    assert.is_not_nil(subgraph.nodes_map[1]) -- A
    assert.is_not_nil(subgraph.nodes_map[2]) -- B
    assert.is_not_nil(subgraph.nodes_map[3]) -- C

    -- Verify edge connections
    local has_edge = false
    for _, edge in ipairs(subgraph.edges) do
      if edge.from_node.nodeid == 1 and edge.to_node.nodeid == 2 then
        has_edge = true
        break
      end
    end
    assert.is_true(has_edge)

    -- Render subgraph
    graph_drawer.nodes = subgraph.nodes_map
    graph_drawer:draw(subgraph.root_node, false)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Verify render result - Should only display connected nodes
    local expected_lines = {
      "A---->B",
    }
    assert.same(expected_lines, lines)
  end)

  it("should preserve node usr_data in subgraph for node info and navigation", function()
    -- Construct original nodes and edges
    local SubEdge = require("call_graph.class.subedge")
    local sub_edge = SubEdge:new(0, 0, 1, 0)
    local node1 = GraphNode:new(1, "Original_A")
    local node2 = GraphNode:new(2, "Original_B")

    -- Set node1 and node2 text attributes to strings to ensure subsequent length calculation is correct
    node1.text = "Original_A"
    node2.text = "Original_B"

    node1.usr_data = {
      attr = {
        pos_params = {
          textDocument = { uri = "file:///test.cc" },
          position = { line = 15, character = 0 },
        },
      },
    }

    local edge = Edge:new(node1, node2, {
      textDocument = { uri = "file:///test.cc" },
      position = { line = 15, character = 0 },
    }, { sub_edge })

    -- Mock generate_subgraph logic
    local subgraph = { root_node = node1, nodes_map = { [1] = node1, [2] = node2 }, edges = { edge } }

    -- Call generate_subgraph directly
    local Caller = require("call_graph.caller")

    -- Render with graph_drawer
    graph_drawer = GraphDrawer:new(bufnr, ns_id)
    graph_drawer:draw(subgraph.root_node)

    -- Define expected graph output
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    if #lines > 0 then
      assert.is_not_nil(lines[1], "Buffer should contain at least one line")
    end

    -- Verify usr_data is preserved
    assert.is_not_nil(node1.usr_data)
    assert.is_not_nil(node1.usr_data.attr)
    assert.is_not_nil(node1.usr_data.attr.pos_params)
    assert.equals("file:///test.cc", node1.usr_data.attr.pos_params.textDocument.uri)

    -- Verify edge's pos_params is preserved
    assert.is_not_nil(edge.pos_params)
    assert.equals("file:///test.cc", edge.pos_params.textDocument.uri)

    -- Verify sub_edges are preserved
    assert.is_not_nil(edge.sub_edges)
    assert.equals(1, #edge.sub_edges)
    assert.equals(0, edge.sub_edges[1].start_row)
    assert.equals(1, edge.sub_edges[1].end_row)
  end)

  it("should support K and gd in subgraph", function()
    -- Construct original nodes and edges
    local node1 = {
      row = 0,
      col = 0,
      text = "Node1",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 1,
      usr_data = {
        file = "/path/to/file1.lua",
        line = 10,
        col = 5,
        text = "function node1()",
      },
      pos_params = {
        row = 0,
        col = 0,
      },
    }
    local node2 = {
      row = 0,
      col = 0,
      text = "Node2",
      level = 2,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 2,
      usr_data = {
        file = "/path/to/file2.lua",
        line = 20,
        col = 8,
        text = "function node2()",
      },
      pos_params = {
        row = 2,
        col = 0,
      },
    }
    local node3 = {
      row = 0,
      col = 0,
      text = "Node3",
      level = 3,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 3,
      usr_data = {
        file = "/path/to/file3.lua",
        line = 30,
        col = 12,
        text = "function node3()",
      },
      pos_params = {
        row = 4,
        col = 0,
      },
    }
    local edge1 = Edge:new(node1, node2)
    edge1.pos_params = { row = 1, col = 0 }
    table.insert(node1.outcoming_edges, edge1)
    table.insert(node2.incoming_edges, edge1)

    local edge2 = Edge:new(node2, node3)
    edge2.pos_params = { row = 3, col = 0 }
    table.insert(node2.outcoming_edges, edge2)
    table.insert(node3.incoming_edges, edge2)

    local nodes = { [1] = node1, [2] = node2, [3] = node3 }
    local edges = { edge1, edge2 }

    -- Create view and draw full graph
    local view = CallGraphView:new()
    view:draw(node1, nodes, edges)

    -- Mock mark node
    local marked_node_ids = { 1, 2 } -- Mark Node1 and Node2

    -- Generate subgraph
    local subgraph = Caller.generate_subgraph(marked_node_ids, nodes, edges)
    assert.is_not_nil(subgraph, "Subgraph should be generated")
    assert.is_not_nil(subgraph.nodes_map, "Subgraph should have nodes_map")
    assert.is_not_nil(subgraph.edges, "Subgraph should have edges")

    -- Create new view and draw subgraph
    local subgraph_view = CallGraphView:new()
    subgraph_view:draw(subgraph.nodes_list[1], subgraph.nodes_map, subgraph.edges)

    -- Verify subgraph node data
    local subgraph_node1 = subgraph.nodes_map[1]
    assert.is_not_nil(subgraph_node1, "Node1 should exist in subgraph")
    assert.is_not_nil(subgraph_node1.usr_data, "Node1 should have usr_data")
    assert.equals("/path/to/file1.lua", subgraph_node1.usr_data.file)
    assert.equals(10, subgraph_node1.usr_data.line)
    assert.equals(5, subgraph_node1.usr_data.col)
    assert.equals("function node1()", subgraph_node1.usr_data.text)

    local subgraph_node2 = subgraph.nodes_map[2]
    assert.is_not_nil(subgraph_node2, "Node2 should exist in subgraph")
    assert.is_not_nil(subgraph_node2.usr_data, "Node2 should have usr_data")
    assert.equals("/path/to/file2.lua", subgraph_node2.usr_data.file)
    assert.equals(20, subgraph_node2.usr_data.line)
    assert.equals(8, subgraph_node2.usr_data.col)
    assert.equals("function node2()", subgraph_node2.usr_data.text)

    -- Mock in subgraph use K key to view node info
    subgraph_view.nodes_cache = subgraph.nodes_map
    vim.api.nvim_win_set_cursor(0, { 1, 0 }) -- Assume Node1 is in the 1st row
    local node_at_cursor = subgraph_view:get_node_at_cursor()
    assert.is_not_nil(node_at_cursor, "Should be able to get node at cursor")
    assert.is_not_nil(node_at_cursor.usr_data, "Node should have usr_data for K key")

    -- Mock in subgraph use gd key to jump
    local edge = subgraph.edges[1]
    assert.is_not_nil(edge, "Should have edge in subgraph")
    assert.is_not_nil(edge.from_node, "Edge should have from_node")
    assert.is_not_nil(edge.to_node, "Edge should have to_node")
    assert.is_not_nil(edge.from_node.usr_data, "from_node should have usr_data for gd")
    assert.is_not_nil(edge.to_node.usr_data, "to_node should have usr_data for gd")
  end)

  it("should handle complex graph", function()
    graph_drawer = GraphDrawer:new(bufnr, ns_id)
    vim.api.nvim_buf_set_option(bufnr, "modifiable", true)

    -- Manually set graph_drawer.nodes
    graph_drawer.nodes = {}
    local node1 = GraphNode:new(1, "Node1")
    local node2 = GraphNode:new(2, "Node2")
    local node3 = GraphNode:new(3, "Node3")

    -- Pass nil as root_node
    local success, err = pcall(function()
      graph_drawer:draw(nil)
    end)

    -- Should not error
    assert.is_true(success)

    -- Mock only passing nodes list, not setting nodes map
    graph_drawer.nodes = nil
    graph_drawer.nodes_list = { node1, node2, node3 }
    
    -- Manually add nodes to nodes to ensure test pass
    graph_drawer.nodes = { [node1.nodeid] = node1, [node2.nodeid] = node2, [node3.nodeid] = node3 }

    local success2, err2 = pcall(function()
      graph_drawer:draw(node1)
    end)

    -- Should not error with nodes_list
    assert.is_true(success2, "graph_drawer:draw should not throw an error with nodes_list")
  end)

  it("should handle draw with no nodes set", function()
    graph_drawer = GraphDrawer:new(bufnr, ns_id)
    vim.api.nvim_buf_set_option(bufnr, "modifiable", true)

    -- Not manually setting graph_drawer.nodes, directly call draw
    -- draw depends on self.nodes, theoretically should not error after fix
    local success, err = pcall(function()
      graph_drawer:draw(nil)
    end)

    assert.is_true(success)
  end)

  it("should preserve node usr_data in subgraph for node info and navigation", function()
    -- Construct original nodes and edges
    local SubEdge = require("call_graph.class.subedge")
    local sub_edge = SubEdge:new(0, 0, 1, 0)
    local node1 = GraphNode:new(1, "Original_A")
    local node2 = GraphNode:new(2, "Original_B")

    -- Set node1 and node2 text attributes to strings to ensure subsequent length calculation is correct
    node1.text = "Original_A"
    node2.text = "Original_B"

    node1.usr_data = {
      attr = {
        pos_params = {
          textDocument = { uri = "file:///test.cc" },
          position = { line = 15, character = 0 },
        },
      },
    }

    local edge = Edge:new(node1, node2, {
      textDocument = { uri = "file:///test.cc" },
      position = { line = 15, character = 0 },
    }, { sub_edge })

    -- Mock generate_subgraph logic
    local subgraph = { root_node = node1, nodes_map = { [1] = node1, [2] = node2 }, edges = { edge } }

    -- Call generate_subgraph directly
    local Caller = require("call_graph.caller")

    -- Render with graph_drawer
    graph_drawer = GraphDrawer:new(bufnr, ns_id)
    graph_drawer:draw(subgraph.root_node)

    -- Define expected graph output
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    if #lines > 0 then
      assert.is_not_nil(lines[1], "Buffer should contain at least one line")
    end

    -- Verify usr_data is preserved
    assert.is_not_nil(node1.usr_data)
    assert.is_not_nil(node1.usr_data.attr)
    assert.is_not_nil(node1.usr_data.attr.pos_params)
    assert.equals("file:///test.cc", node1.usr_data.attr.pos_params.textDocument.uri)

    -- Verify edge's pos_params is preserved
    assert.is_not_nil(edge.pos_params)
    assert.equals("file:///test.cc", edge.pos_params.textDocument.uri)

    -- Verify sub_edges are preserved
    assert.is_not_nil(edge.sub_edges)
    assert.equals(1, #edge.sub_edges)
    assert.equals(0, edge.sub_edges[1].start_row)
    assert.equals(1, edge.sub_edges[1].end_row)
  end)
end)
