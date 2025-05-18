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
    local ret = table_eq(lines, model_lines)
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
    local ret = table_eq(lines, model_lines)
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
    -- 多分支结构
    local root_node = { row = 0, col = 0, text = "RootNode", level = 1, incoming_edges = {}, outcoming_edges = {}, nodeid = 1, usr_data = {}, }
    local child1_node = { row = 0, col = 0, text = "Child1Node", level = 1, incoming_edges = {}, outcoming_edges = {}, nodeid = 2, usr_data = {}, }
    local child2_node = { row = 0, col = 0, text = "Child2Node", level = 1, incoming_edges = {}, outcoming_edges = {}, nodeid = 3, usr_data = {}, }
    local child3_node = { row = 0, col = 0, text = "Child3Node", level = 1, incoming_edges = {}, outcoming_edges = {}, nodeid = 4, usr_data = {}, }
    local grandchild_node = { row = 0, col = 0, text = "GrandChildNode", level = 1, incoming_edges = {}, outcoming_edges = {}, nodeid = 5, usr_data = {}, }
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
    graph_drawer.nodes = { [1]=root_node, [2]=child1_node, [3]=child2_node, [4]=child3_node, [5]=grandchild_node }
    graph_drawer:draw(root_node, false)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    print(vim.inspect(lines))
    -- 定义预期的图形输出
    local expected_lines = {
      "RootNode---->Child1Node  -->GrandChildNode",
      "          |              |",
      "          -->Child2Node---",
      "          |              |",
      "          -->Child3Node---"
    }
    -- 严格比较实际输出和预期输出
    local ret = table_eq(lines, expected_lines)
    if not ret then
      assert.equal(expected_lines, lines) -- 获取更详细的错误信息
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

    -- 手动设置 graph_drawer.nodes
    graph_drawer.nodes = {
      [node1.nodeid] = node1,
      [node2.nodeid] = node2
    }

    -- 传入 nil 作为 root_node
    graph_drawer:draw(nil, false)
    local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
    assert(line:find("Node1") or line:find("Node2"))
  end)

  it("should handle nil root_node and empty nodes table", function()
    graph_drawer.nodes = {}
    -- 不应报错
    graph_drawer:draw(nil, false)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.is_true(#lines >= 0)
  end)

  it("should not raise error when nodes is not explicitly set but draw is called", function()
    -- 模拟只传入 nodes list，未赋值 nodes map
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

    -- 不手动赋值 graph_drawer.nodes，直接调用 draw
    -- draw 依赖 self.nodes，理论上修复后不会报错
    assert.has_no.errors(function()
      graph_drawer.nodes = nil
      graph_drawer:draw(node1, false)
    end)
  end)

  it("should render subgraph with two marked nodes and one edge", function()
    -- 构造原始节点和边
    local node1 = {
      row = 0,
      col = 0,
      text = "a/test.cc:2",
      level = 2, -- 被指向，level更高
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 1,
      usr_data = {},
    }
    local node2 = {
      row = 0,
      col = 0,
      text = "b/test.cc:4",
      level = 1, -- 作为root
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 2,
      usr_data = {},
    }
    local edge = Edge:new(node2, node1, nil, {})
    table.insert(node2.outcoming_edges, edge)
    table.insert(node1.incoming_edges, edge)

    -- 模拟 generate_subgraph 逻辑
    local marked_node_ids = {1, 2}
    local nodes = { [1]=node1, [2]=node2 }
    local edges = { edge }
    -- 直接调用 generate_subgraph
    local caller = require("call_graph.caller")
    local subgraph = caller.generate_subgraph(marked_node_ids, nodes, edges)

    -- 用 graph_drawer 渲染
    graph_drawer.nodes = subgraph.nodes_map
    -- 以 node2 作为 root
    graph_drawer:draw(subgraph.nodes_map[2], false)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    
    -- 定义预期的图形输出
    local expected_lines = {
      "b/test.cc:4---->a/test.cc:2"
    }
    -- 严格比较实际输出和预期输出
    local ret = table_eq(lines, expected_lines)
    if not ret then
      assert.equal(expected_lines, lines) -- 获取更详细的错误信息
    end
    assert.is_true(ret)
  end)

  it("should render subgraph with multiple marked nodes and complex connections", function()
    -- 构造原始节点和边
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

    -- 创建边连接
    local edge1 = Edge:new(node1, node2, nil, {})
    local edge2 = Edge:new(node1, node3, nil, {})
    local edge3 = Edge:new(node2, node4, nil, {})
    local edge4 = Edge:new(node3, node4, nil, {})

    -- 添加边到节点
    table.insert(node1.outcoming_edges, edge1)
    table.insert(node2.incoming_edges, edge1)
    table.insert(node1.outcoming_edges, edge2)
    table.insert(node3.incoming_edges, edge2)
    table.insert(node2.outcoming_edges, edge3)
    table.insert(node4.incoming_edges, edge3)
    table.insert(node3.outcoming_edges, edge4)
    table.insert(node4.incoming_edges, edge4)

    -- 模拟 generate_subgraph 逻辑
    local marked_node_ids = {1, 2, 4} -- 标记根节点、第一个子节点和最后一个节点
    local nodes = { [1]=node1, [2]=node2, [3]=node3, [4]=node4 }
    local edges = { edge1, edge2, edge3, edge4 }
    
    -- 直接调用 generate_subgraph
    local caller = require("call_graph.caller")
    local subgraph = caller.generate_subgraph(marked_node_ids, nodes, edges)

    -- 用 graph_drawer 渲染
    graph_drawer.nodes = subgraph.nodes_map
    graph_drawer:draw(subgraph.nodes_list[1], false)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- 定义预期的图形输出
    local expected_lines = {
      "main.cc:10---->utils.cc:20---->common.cc:40"
    }
    -- 严格比较实际输出和预期输出
    local ret = table_eq(lines, expected_lines)
    if not ret then
      assert.equal(expected_lines, lines) -- 获取更详细的错误信息
    end
    assert.is_true(ret)
  end)

  it("should handle bidirectional edges in subgraph", function()
    -- 构造原始节点和边
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

    -- 创建双向边
    local edge1 = Edge:new(node1, node2, nil, {})
    local edge2 = Edge:new(node2, node1, nil, {})

    -- 添加边到节点
    table.insert(node1.outcoming_edges, edge1)
    table.insert(node2.incoming_edges, edge1)
    table.insert(node2.outcoming_edges, edge2)
    table.insert(node1.incoming_edges, edge2)

    -- 模拟 generate_subgraph 逻辑
    local marked_node_ids = {1, 2}
    local nodes = { [1]=node1, [2]=node2 }
    local edges = { edge1, edge2 }
    
    -- 直接调用 generate_subgraph
    local caller = require("call_graph.caller")
    local subgraph = caller.generate_subgraph(marked_node_ids, nodes, edges)

    -- 用 graph_drawer 渲染
    graph_drawer.nodes = subgraph.nodes_map
    graph_drawer:draw(nil, subgraph.nodes_list, subgraph.edges)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- 定义预期的图形输出
    local expected_lines = {
      "A<--->B"
    }
    -- 严格比较实际输出和预期输出
    local ret = table_eq(lines, expected_lines)
    if not ret then
      assert.equal(expected_lines, lines) -- 获取更详细的错误信息
    end
    assert.is_true(ret)
  end)

  it("should render subgraph with marked nodes in mark mode", function()
    -- 构造原始节点和边
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

    -- 模拟标记模式
    local marked_node_ids = {1, 2} -- 模拟用户标记了两个节点
    local nodes = { [1]=node1, [2]=node2 }
    local edges = { edge }
    
    -- 调用 generate_subgraph 生成子图
    local caller = require("call_graph.caller")
    local subgraph = caller.generate_subgraph(marked_node_ids, nodes, edges)

    -- 用 graph_drawer 渲染
    graph_drawer.nodes = subgraph.nodes_map
    graph_drawer:draw(subgraph.nodes_map[2], false)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    
    -- 定义预期的图形输出
    local expected_lines = {
      "b/test.cc:4---->a/test.cc:2"
    }
    -- 严格比较实际输出和预期输出
    local ret = table_eq(lines, expected_lines)
    if not ret then
      assert.equal(expected_lines, lines) -- 获取更详细的错误信息
    end
    assert.is_true(ret)
  end)

  it("should render subgraph for mark mode with two nodes and one edge (regression)", function()
    local node1 = { row=0, col=0, text="a/test.cc:2", level=2, incoming_edges={}, outcoming_edges={}, nodeid=1, usr_data={} }
    local node2 = { row=0, col=0, text="b/test.cc:4", level=1, incoming_edges={}, outcoming_edges={}, nodeid=2, usr_data={} }
    local edge = Edge:new(node2, node1, nil, {})
    table.insert(node2.outcoming_edges, edge)
    table.insert(node1.incoming_edges, edge)
    local marked_node_ids = {1, 2}
    local nodes = { [1]=node1, [2]=node2 }
    local edges = { edge }
    local caller = require("call_graph.caller")
    local subgraph = caller.generate_subgraph(marked_node_ids, nodes, edges)
    graph_drawer.nodes = subgraph.nodes_map
    graph_drawer:draw(subgraph.nodes_map[2], false)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.same({ "b/test.cc:4---->a/test.cc:2" }, lines)
  end)

  it("should handle subgraph generation and rendering with multiple nodes", function()
    -- 构造原始节点和边
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

    -- 创建边连接
    local edge1 = Edge:new(node1, node2, nil, {})
    local edge2 = Edge:new(node1, node3, nil, {})
    local edge3 = Edge:new(node2, node4, nil, {})
    local edge4 = Edge:new(node3, node4, nil, {})

    -- 添加边到节点
    table.insert(node1.outcoming_edges, edge1)
    table.insert(node2.incoming_edges, edge1)
    table.insert(node1.outcoming_edges, edge2)
    table.insert(node3.incoming_edges, edge2)
    table.insert(node2.outcoming_edges, edge3)
    table.insert(node4.incoming_edges, edge3)
    table.insert(node3.outcoming_edges, edge4)
    table.insert(node4.incoming_edges, edge4)

    -- 模拟标记模式
    local marked_node_ids = {1, 2, 4} -- 标记根节点、第一个子节点和最后一个节点
    local nodes = { [1]=node1, [2]=node2, [3]=node3, [4]=node4 }
    local edges = { edge1, edge2, edge3, edge4 }
    
    -- 生成子图
    local caller = require("call_graph.caller")
    local subgraph = caller.generate_subgraph(marked_node_ids, nodes, edges)

    -- 验证子图数据结构
    assert.is_not_nil(subgraph)
    assert.is_not_nil(subgraph.nodes_map)
    assert.is_not_nil(subgraph.nodes_list)
    assert.is_not_nil(subgraph.edges)
    assert.equal(3, #subgraph.nodes_list) -- 应该有3个节点
    assert.equal(2, #subgraph.edges) -- 应该有2条边

    -- 验证节点映射
    assert.is_not_nil(subgraph.nodes_map[1]) -- main.cc
    assert.is_not_nil(subgraph.nodes_map[2]) -- utils.cc
    assert.is_not_nil(subgraph.nodes_map[4]) -- common.cc
    assert.is_nil(subgraph.nodes_map[3]) -- helper.cc 不应该在子图中

    -- 验证边的连接
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

    -- 渲染子图
    graph_drawer.nodes = subgraph.nodes_map
    graph_drawer:draw(subgraph.nodes_map[1], false)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- 验证渲染结果
    local expected_lines = {
      "main.cc:10---->utils.cc:20---->common.cc:40"
    }
    assert.same(expected_lines, lines)
  end)

  it("should handle subgraph generation with disconnected nodes", function()
    -- 构造原始节点和边
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

    -- 创建边连接
    local edge = Edge:new(node1, node2, nil, {})
    table.insert(node1.outcoming_edges, edge)
    table.insert(node2.incoming_edges, edge)

    -- 模拟标记模式 - 标记所有节点，包括未连接的节点3
    local marked_node_ids = {1, 2, 3}
    local nodes = { [1]=node1, [2]=node2, [3]=node3 }
    local edges = { edge }
    
    -- 生成子图
    local caller = require("call_graph.caller")
    local subgraph = caller.generate_subgraph(marked_node_ids, nodes, edges)

    -- 验证子图数据结构
    assert.is_not_nil(subgraph)
    assert.is_not_nil(subgraph.nodes_map)
    assert.is_not_nil(subgraph.nodes_list)
    assert.is_not_nil(subgraph.edges)
    assert.equal(3, #subgraph.nodes_list) -- 应该有3个节点
    assert.equal(1, #subgraph.edges) -- 应该只有1条边

    -- 验证节点映射
    assert.is_not_nil(subgraph.nodes_map[1]) -- A
    assert.is_not_nil(subgraph.nodes_map[2]) -- B
    assert.is_not_nil(subgraph.nodes_map[3]) -- C

    -- 验证边的连接
    local has_edge = false
    for _, edge in ipairs(subgraph.edges) do
      if edge.from_node.nodeid == 1 and edge.to_node.nodeid == 2 then
        has_edge = true
        break
      end
    end
    assert.is_true(has_edge)

    -- 渲染子图
    graph_drawer.nodes = subgraph.nodes_map
    graph_drawer:draw(subgraph.nodes_map[1], false)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- 验证渲染结果 - 应该只显示连接的节点
    local expected_lines = {
      "A---->B"
    }
    assert.same(expected_lines, lines)
  end)
end)
