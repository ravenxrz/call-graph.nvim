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


  it("should draw a 3 - level graph with specific node configuration using outcoming edges", function()
    -- 定义根节点
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

    -- 定义第二层的 3 个节点
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
      text = "ThisIsALongTextNodeWithMoreThanTwentyChars",
      level = 2,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 3,
      usr_data = {}
    }

    local child3_node = {
      row = 0,
      col = 0,
      text = "Child3Node",
      level = 2,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 4,
      usr_data = {}
    }

    -- 定义第三层的节点
    local grandchild_node = {
      row = 0,
      col = 0,
      text = "GrandChildNode",
      level = 3,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 5,
      usr_data = {}
    }

    -- 连接根节点和第二层的节点
    local edge1 = Edge:new(root_node, child1_node, nil, {})
    table.insert(root_node.outcoming_edges, edge1)
    table.insert(child1_node.incoming_edges, edge1)

    local edge2 = Edge:new(root_node, child2_node, nil, {})
    table.insert(root_node.outcoming_edges, edge2)
    table.insert(child2_node.incoming_edges, edge2)

    local edge3 = Edge:new(root_node, child3_node, nil, {})
    table.insert(root_node.outcoming_edges, edge3)
    table.insert(child3_node.incoming_edges, edge3)

    -- 连接第二层的第二个节点和第三层的节点
    local edge4 = Edge:new(child2_node, grandchild_node, nil, {})
    table.insert(child2_node.outcoming_edges, edge4)
    table.insert(grandchild_node.incoming_edges, edge4)

    local edge5 = Edge:new(child3_node, grandchild_node, nil, {})
    table.insert(child3_node.outcoming_edges, edge5)
    table.insert(grandchild_node.incoming_edges, edge5)

    -- 假设这里创建了一个 buffer 用于绘制图形
    local bufnr = vim.api.nvim_create_buf(false, true)
    local graph_drawer = GraphDrawer:new(bufnr, {
      cb = function() end,
      cb_ctx = {}
    })

    -- 绘制图形
    graph_drawer:draw(root_node, false)

    -- 获取绘制后的行
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- 这里可以根据预期的图形输出定义 model_lines
    -- 由于具体的图形布局可能比较复杂，这里只是简单示例，你需要根据实际情况修改
    local model_lines = {
      "RootNode---->Child1Node                                 --->GrandChildNode",
      "          |                                             ||",
      "          |                                             ||",
      "          -->ThisIsALongTextNodeWithMoreThanTwentyChars---",
      "          |                                             |",
      "          |                                             |",
      "          -->Child3Node----------------------------------",
    }
    local ret = table_eq(model_lines, lines)
    if not ret then
      assert.equal(lines, model_lines) -- get a pretty print
    end
    assert.is.True(ret)
  end)

  it("should draw a 3 - level graph with specific node configuration using incoming edges", function()
    -- 定义根节点
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

    -- 定义第二层的 3 个节点
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
      text = "ThisIsALongTextNodeWithMoreThanTwentyChars",
      level = 2,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 3,
      usr_data = {}
    }

    local child3_node = {
      row = 0,
      col = 0,
      text = "Child3Node",
      level = 2,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 4,
      usr_data = {}
    }

    -- 定义第三层的节点
    local grandchild_node = {
      row = 0,
      col = 0,
      text = "GrandChildNode",
      level = 3,
      incoming_edges = {},
      outcoming_edges = {},
      nodeid = 5,
      usr_data = {}
    }

    -- 连接第二层节点到根节点（反向连接）
    local edge1 = Edge:new(child1_node, root_node, nil, {})
    table.insert(child1_node.outcoming_edges, edge1)
    table.insert(root_node.incoming_edges, edge1)

    local edge2 = Edge:new(child2_node, root_node, nil, {})
    table.insert(child2_node.outcoming_edges, edge2)
    table.insert(root_node.incoming_edges, edge2)

    local edge3 = Edge:new(child3_node, root_node, nil, {})
    table.insert(child3_node.outcoming_edges, edge3)
    table.insert(root_node.incoming_edges, edge3)

    -- 连接第三层节点到第二层的第二个节点和第三个节点（反向连接）
    local edge4 = Edge:new(grandchild_node, child2_node, nil, {})
    table.insert(grandchild_node.outcoming_edges, edge4)
    table.insert(child2_node.incoming_edges, edge4)

    local edge5 = Edge:new(grandchild_node, child3_node, nil, {})
    table.insert(grandchild_node.outcoming_edges, edge5)
    table.insert(child3_node.incoming_edges, edge5)

    -- 假设这里创建了一个 buffer 用于绘制图形
    local bufnr = vim.api.nvim_create_buf(false, true)
    local graph_drawer = GraphDrawer:new(bufnr, {
      cb = function() end,
      cb_ctx = {}
    })

    -- 绘制图形，使用 incoming edge 进行遍历
    graph_drawer:draw(root_node, true)

    -- 获取绘制后的行
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- 这里根据 incoming edge 遍历的预期输出定义 model_lines
    local model_lines = {
      'RootNode<----Child1Node                                 ----GrandChildNode',
      '          |                                             ||',
      '          |                                             ||',
      '          ---ThisIsALongTextNodeWithMoreThanTwentyChars<--',
      '          |                                             |',
      '          |                                             |',
      '          ---Child3Node<---------------------------------', }

    local ret = table_eq(model_lines, lines)
    if not ret then
      assert.equal(lines, model_lines) -- get a pretty print
    end
    assert.is.True(ret)
  end)
end)
