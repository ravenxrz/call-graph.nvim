local GraphDrawer = require("call_graph.view.graph_drawer")
local Edge = require("call_graph.class.edge")

local function table_eq(tbl1, tbl2)
  if #tbl1 ~= #tbl2 then
    return false
  end

  for i = 1, #tbl1 do
    if tbl1[i] ~= tbl2[i] then
      print(i, "not equal")
      return false
    end
  end

  return true
end

describe("GraphDrawer", function()
  local bufnr
  local graph_drawer
  local draw_edge_cb = {
    cb = function() end,
    cb_ctx = {}
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
      usr_data = {}
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
      usr_data = {}
    }
    local node2 = {
      row = 0,
      col = 0,
      text = "ChildNode",
      level = 2,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 2,
      usr_data = {}
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
      usr_data = {}
    }
    local node2 = {
      row = 0,
      col = 0,
      text = "ChildNode",
      level = 2,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 2,
      usr_data = {}
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
      usr_data = {}
    }
    local level3_node = {
      row = 0,
      col = 0,
      text = "Level3Node",
      level = 3,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 3,
      usr_data = {}
    }
    local level2_node = {
      row = 0,
      col = 0,
      text = "Level2Node",
      level = 2,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 2,
      usr_data = {}
    }
    local root_node = {
      row = 0,
      col = 0,
      text = "RootNode",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 1,
      usr_data = {}
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
      usr_data = {}
    }
    local level3_node = {
      row = 0,
      col = 0,
      text = "Level3Node",
      level = 3,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 3,
      usr_data = {}
    }
    local level2_node = {
      row = 0,
      col = 0,
      text = "Level2Node",
      level = 2,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 2,
      usr_data = {}
    }
    local root_node = {
      row = 0,
      col = 0,
      text = "RootNode",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 1,
      usr_data = {}
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
      usr_data = {}
    }
    local child2_node = {
      row = 0,
      col = 0,
      text = "Child2Node",
      level = 2,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 3,
      usr_data = {}
    }
    local root_node = {
      row = 0,
      col = 0,
      text = "RootNode",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 1,
      usr_data = {}
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
      "          |",
      "          -->Child2Node"
    }
    local ret = table_eq(model_lines, lines)
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
      usr_data = {}
    }
    local child2_node = {
      row = 0,
      col = 0,
      text = "Child2Node",
      level = 2,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 3,
      usr_data = {}
    }
    local root_node = {
      row = 0,
      col = 0,
      text = "RootNode",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 1,
      usr_data = {}
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
      "          |",
      "          ---Child2Node"
    }
    local ret = table_eq(lines, model_lines)
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
      usr_data = {}
    }
    local node2 = {
      row = 0,
      col = 0,
      text = "Node2",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 2,
      usr_data = {}
    }
    local node3 = {
      row = 0,
      col = 0,
      text = "Node3",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 3,
      usr_data = {}
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
    if not table_eq(lines, model_lines) then
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
      usr_data = {}
    }
    local node2 = {
      row = 0,
      col = 0,
      text = "Node2",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 2,
      usr_data = {}
    }
    local node3 = {
      row = 0,
      col = 0,
      text = "Node3",
      level = 1,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 3,
      usr_data = {}
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
    local ret = table_eq(lines, model_lines)
    if not ret then
      assert.equal(model_lines, lines)
    end
    assert.is.True(ret)
  end)
end)
