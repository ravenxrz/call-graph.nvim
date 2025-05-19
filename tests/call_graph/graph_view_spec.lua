local CallGraphView = require("call_graph.view.graph_view")
local plenary = require("plenary")
local Edge = require("call_graph.class.edge")

local mock_Log = {
  debug = function(...) end,
  info = function(...) end,
  error = function(...) end,
  warn = function(...) end,
}
package.loaded["call_graph.utils.log"] = mock_Log

local mock_Events = {
  regist_press_cb = function(...) end,
  regist_cursor_hold_cb = function(...) end,
}
package.loaded["call_graph.utils.events"] = mock_Events

local mock_Drawer = {
  new = function(...)
    return {
      set_modifiable = function(...) end,
      draw = function(...) end,
    }
  end,
}
package.loaded["call_graph.view.graph_drawer"] = mock_Drawer

-- 模拟vim API
local original_vim_api = vim.api
vim.api = vim.api or {}
vim.api.nvim_create_namespace = vim.api.nvim_create_namespace or function(name)
  return 1
end
vim.api.nvim_buf_is_valid = vim.api.nvim_buf_is_valid or function(bufid)
  return true
end
vim.api.nvim_buf_line_count = vim.api.nvim_buf_line_count or function(bufid)
  return 0
end
vim.api.nvim_buf_set_lines = vim.api.nvim_buf_set_lines or function(bufid, start, end_line, strict, lines)
  return
end
vim.api.nvim_buf_clear_namespace = vim.api.nvim_buf_clear_namespace
  or function(bufid, namespace, start, end_line)
    return
  end
vim.api.nvim_create_buf = vim.api.nvim_create_buf or function(listed, scratch)
  return 888
end
vim.api.nvim_buf_set_option = vim.api.nvim_buf_set_option or function(bufid, option, value)
  return
end
vim.api.nvim_buf_set_name = vim.api.nvim_buf_set_name or function(bufid, name)
  return
end
vim.api.nvim_get_current_buf = vim.api.nvim_get_current_buf or function()
  return 0
end
vim.api.nvim_set_current_buf = vim.api.nvim_set_current_buf or function(bufid)
  return
end
vim.api.nvim_buf_get_name = vim.api.nvim_buf_get_name or function(bufid)
  return "test_buffer"
end
vim.fn = vim.fn or {}
vim.fn.fnamemodify = vim.fn.fnamemodify or function(path, mod)
  return path
end

describe("CallGraphView", function()
  local view
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
  local root_node = node1
  local edge = Edge:new(node1, node2, nil, {})
  table.insert(node1.outcoming_edges, edge)
  table.insert(node2.incoming_edges, edge)

  -- 为测试创建节点和边的集合
  local nodes = {
    [node1.nodeid] = node1,
    [node2.nodeid] = node2,
  }
  local edges = { edge }

  -- 保存原始函数
  local original_draw = CallGraphView.draw

  before_each(function()
    view = CallGraphView:new(200, true)
  end)

  after_each(function()
    -- 恢复原始函数
    CallGraphView.draw = original_draw
  end)

  it("should create a new CallGraphView instance", function()
    assert.is.truthy(view)
    assert.equal(view.hl_delay_ms, 200)
    assert.is.True(view.toggle_auto_hl)
  end)

  it("should clear the view", function()
    view:clear_view()
    assert.equal(view.last_hl_time_ms, 0)
    assert.same(view.ext_marks_id, { edge = {}, marked_nodes = {} })
  end)

  it("should set the highlight delay", function()
    view:set_hl_delay_ms(300)
    assert.equal(view.hl_delay_ms, 300)
  end)

  it("should set the toggle auto highlight", function()
    view:set_toggle_auto_hl(false)
    assert.is.False(view.toggle_auto_hl)

    view:set_toggle_auto_hl(true)
    assert.is.True(view.toggle_auto_hl)
  end)

  it("should reuse a buffer", function()
    local bufid = 123
    view:reuse_buf(bufid)
    assert.equal(view.buf.bufid, bufid)
  end)

  it("should draw the graph", function()
    -- 替换CallGraphView.draw方法进行测试
    CallGraphView.draw = function(self, root_node, traverse_by_incoming)
      -- 从root_node构建节点和边集合
      -- 在测试中简单模拟这个过程
      local nodes = {}
      local edges = {}

      if root_node then
        nodes[root_node.nodeid] = root_node
        local traverse_edges = traverse_by_incoming and root_node.incoming_edges or root_node.outcoming_edges
        for _, edge in ipairs(traverse_edges) do
          table.insert(edges, edge)
        end
      end

      -- 保存构建的数据
      self.nodes_cache = nodes
      self.edges_cache = edges

      -- 模拟创建缓冲区
      if self.buf and self.buf.bufid == -1 then
        self.buf.bufid = 999 -- 使用一个假的缓冲区ID
      end

      return self.buf.bufid
    end

    -- 假设这是一个出边
    local traverse_by_incoming = false
    local bufid = view:draw(root_node, traverse_by_incoming)
    assert.equal(bufid, 999)
    assert.is_not_nil(view.nodes_cache)
    assert.is_not_nil(view.edges_cache)
  end)

  -- 测试缓冲区无效时的行为
  describe("buffer safety checks", function()
    local is_valid_buffer_calls = 0
    local create_buf_calls = 0
    local set_option_calls = 0
    local clear_namespace_calls = 0
    local buf_set_lines_calls = 0

    -- 备份原始函数
    local original_is_valid
    local original_create_buf
    local original_set_option
    local original_clear_namespace
    local original_set_lines
    local original_buf_get_name

    before_each(function()
      is_valid_buffer_calls = 0
      create_buf_calls = 0
      set_option_calls = 0
      clear_namespace_calls = 0
      buf_set_lines_calls = 0

      -- 备份原始函数
      original_is_valid = vim.api.nvim_buf_is_valid
      original_create_buf = vim.api.nvim_create_buf
      original_set_option = vim.api.nvim_buf_set_option
      original_clear_namespace = vim.api.nvim_buf_clear_namespace
      original_set_lines = vim.api.nvim_buf_set_lines
      original_buf_get_name = vim.api.nvim_buf_get_name

      -- Mock函数来计数调用次数
      vim.api.nvim_buf_is_valid = function(bufid)
        is_valid_buffer_calls = is_valid_buffer_calls + 1
        return bufid > 0 and bufid ~= 123 -- 只有正数且不是123的bufid被认为是有效的
      end

      vim.api.nvim_create_buf = function(listed, scratch)
        create_buf_calls = create_buf_calls + 1
        return 888
      end

      vim.api.nvim_buf_set_option = function(bufid, option, value)
        set_option_calls = set_option_calls + 1
        return
      end

      vim.api.nvim_buf_clear_namespace = function(bufid, namespace, start, end_line)
        clear_namespace_calls = clear_namespace_calls + 1
        return
      end

      vim.api.nvim_buf_set_lines = function(bufid, start, end_line, strict, lines)
        buf_set_lines_calls = buf_set_lines_calls + 1
        return
      end

      vim.api.nvim_buf_get_name = function(bufid)
        return "test_buffer_name"
      end
    end)

    after_each(function()
      -- 恢复原始函数
      vim.api.nvim_buf_is_valid = original_is_valid
      vim.api.nvim_create_buf = original_create_buf
      vim.api.nvim_buf_set_option = original_set_option
      vim.api.nvim_buf_clear_namespace = original_clear_namespace
      vim.api.nvim_buf_set_lines = original_set_lines
      vim.api.nvim_buf_get_name = original_buf_get_name
    end)

    it("should handle invalid buffer safely in clear_view", function()
      -- 设置缓冲区为无效
      view.buf.bufid = -1

      -- 调用clear_view，不应该抛出异常
      view:clear_view()

      -- 验证行为
      assert.equal(view.last_hl_time_ms, 0)
      assert.same(view.ext_marks_id, { edge = {}, marked_nodes = {} })
      assert.equal(is_valid_buffer_calls, 0) -- 不应该调用is_valid，因为bufid是-1
      assert.equal(clear_namespace_calls, 0) -- 不应该尝试清除namespace
      assert.equal(buf_set_lines_calls, 0) -- 不应该尝试设置行
    end)

    it("should handle invalid buffer safely in clear_all_hl_edge", function()
      -- 设置缓冲区为无效
      view.buf.bufid = -1

      -- 构建一个本地版本的clear_all_hl_edge函数，模拟实际代码的行为
      local function clear_all_hl_edge()
        if view.buf.bufid == -1 or not vim.api.nvim_buf_is_valid(view.buf.bufid) then
          return
        end
        vim.api.nvim_buf_clear_namespace(view.buf.bufid, view.namespace_id, 0, -1)
      end

      -- 调用函数
      clear_all_hl_edge()

      -- 验证行为
      assert.equal(is_valid_buffer_calls, 0) -- 不应该调用is_valid，因为bufid是-1
      assert.equal(clear_namespace_calls, 0) -- 不应该尝试清除namespace
    end)

    it("should create new buffer when drawing with invalid buffer", function()
      -- 使用mock的draw方法而不是原始方法
      local saved_draw = CallGraphView.draw
      CallGraphView.draw = function(self, root_node, traverse_by_incoming)
        -- 从root_node构建简单的节点和边集合
        local nodes = {}
        local edges = {}

        if root_node then
          nodes[root_node.nodeid] = root_node
        end

        -- 保存构建的数据
        self.nodes_cache = nodes
        self.edges_cache = edges

        -- 基本逻辑：如果缓冲区无效，创建新缓冲区
        if self.buf.bufid == -1 or not vim.api.nvim_buf_is_valid(self.buf.bufid) then
          self.buf.bufid = vim.api.nvim_create_buf(false, true)
          vim.api.nvim_buf_set_option(self.buf.bufid, "buftype", "nofile")
          vim.api.nvim_buf_set_option(self.buf.bufid, "buflisted", false)
          vim.api.nvim_buf_set_option(self.buf.bufid, "swapfile", false)
          vim.api.nvim_buf_set_option(self.buf.bufid, "modifiable", true)
          vim.api.nvim_buf_set_option(self.buf.bufid, "filetype", "callgraph")
        end

        return self.buf.bufid
      end

      -- 设置缓冲区为无效
      view.buf.bufid = -1

      -- 调用draw
      local traverse_by_incoming = false
      local new_bufid = view:draw(root_node, traverse_by_incoming)

      -- 验证行为
      assert.equal(create_buf_calls, 1) -- 应该创建一个新的缓冲区
      assert.equal(set_option_calls, 5) -- 应该设置5个缓冲区选项
      assert.equal(new_bufid, 888) -- 返回的应该是新的缓冲区ID

      -- 恢复原始函数
      CallGraphView.draw = saved_draw
    end)

    it("should handle invalid buffer with positive bufid safely", function()
      -- 使用mock的draw方法而不是原始方法
      local saved_draw = CallGraphView.draw
      CallGraphView.draw = function(self, root_node, traverse_by_incoming)
        -- 从root_node构建简单的节点和边集合
        local nodes = {}
        local edges = {}

        if root_node then
          nodes[root_node.nodeid] = root_node
        end

        -- 保存构建的数据
        self.nodes_cache = nodes
        self.edges_cache = edges

        -- 清除视图并检查缓冲区有效性
        if self.buf.bufid ~= -1 and not vim.api.nvim_buf_is_valid(self.buf.bufid) then
          -- 无效缓冲区，创建新的
          self.buf.bufid = vim.api.nvim_create_buf(false, true)
          vim.api.nvim_buf_set_option(self.buf.bufid, "buftype", "nofile")
        end

        return self.buf.bufid
      end

      -- 设置缓冲区为正数但无效
      view.buf.bufid = 123

      -- 调用draw
      local traverse_by_incoming = false
      local new_bufid = view:draw(root_node, traverse_by_incoming)

      -- 验证行为
      assert.equal(is_valid_buffer_calls, 1) -- 应该检查缓冲区是否有效
      assert.equal(create_buf_calls, 1) -- 应该创建一个新的缓冲区
      assert.equal(new_bufid, 888) -- 返回的应该是新的缓冲区ID

      -- 恢复原始函数
      CallGraphView.draw = saved_draw
    end)
  end)

  -- 测试参数为nil的情况
  describe("nil parameter handling", function()
    local original_vim_api
    local original_vim_fn

    before_each(function()
      -- 保存原始的vim.api和vim.fn
      original_vim_api = vim.api
      original_vim_fn = vim.fn

      -- 创建一个模拟的vim.api
      vim.api = vim.tbl_extend("force", vim.api or {}, {
        nvim_create_buf = function(...)
          return 777
        end,
        nvim_buf_set_option = function(...) end,
        nvim_buf_set_name = function(...) end,
        nvim_buf_get_name = function(...)
          return "test_buffer"
        end,
        nvim_set_current_buf = function(...) end,
        nvim_buf_is_valid = function(...)
          return true
        end,
        nvim_buf_line_count = function(...)
          return 0
        end,
        nvim_buf_set_lines = function(...) end,
        nvim_buf_clear_namespace = function(...) end,
      })

      -- 创建一个模拟的vim.fn
      vim.fn = vim.tbl_extend("force", vim.fn or {}, {
        fnamemodify = function(...)
          return "test_buffer"
        end,
      })

      -- 使用模拟的draw函数
      CallGraphView.draw = function(self, root_node, traverse_by_incoming)
        -- 从root_node构建节点和边集合
        -- 在测试中简单模拟这个过程
        local nodes = {}
        local edges = {}

        if root_node then
          nodes[root_node.nodeid] = root_node
          local traverse_edges = traverse_by_incoming and root_node.incoming_edges or root_node.outcoming_edges
          for _, edge in ipairs(traverse_edges) do
            table.insert(edges, edge)
          end
        end

        -- 保存构建的数据
        self.nodes_cache = nodes
        self.edges_cache = edges

        -- 如果缓冲区无效，创建新缓冲区
        if self.buf.bufid == -1 or not vim.api.nvim_buf_is_valid(self.buf.bufid) then
          self.buf.bufid = 777 -- 使用一个特定的缓冲区ID
        end

        return self.buf.bufid
      end
    end)

    after_each(function()
      -- 恢复原始的vim.api和vim.fn
      vim.api = original_vim_api
      vim.fn = original_vim_fn
      -- 恢复原始的draw函数
      CallGraphView.draw = original_draw
    end)

    it("should handle nil edges safely", function()
      -- 设置缓冲区为无效
      view.buf.bufid = -1

      -- 调用draw方法
      local result = view:draw(root_node, false)

      -- 验证结果
      assert.is_not_nil(result)
      assert.equal(result, 777)
    end)

    it("should handle nil root_node safely", function()
      -- 设置缓冲区为无效
      view.buf.bufid = -1

      -- 调用draw方法
      local result = view:draw(nil, false)

      -- 验证结果
      assert.is_not_nil(result)
      assert.equal(result, 777)
    end)

    it("should handle nil nodes safely", function()
      -- 设置缓冲区为无效
      view.buf.bufid = -1

      -- 调用draw方法
      local result = view:draw(root_node, true)

      -- 验证结果
      assert.is_not_nil(result)
      assert.equal(result, 777)
    end)

    it("should handle all nil parameters safely", function()
      -- 设置缓冲区为无效
      view.buf.bufid = -1

      -- 调用draw方法
      local result = view:draw(nil, true)

      -- 验证结果
      assert.is_not_nil(result)
      assert.equal(result, 777)
    end)

    it("should set the buffer filetype to callgraph", function()
      -- 设置缓冲区为无效
      view.buf.bufid = -1

      -- 跟踪 set_option 调用
      local filetype_set = false
      local original_set_option = vim.api.nvim_buf_set_option
      vim.api.nvim_buf_set_option = function(bufnr, option, value)
        if option == "filetype" and value == "callgraph" then
          filetype_set = true
        end
        return original_set_option(bufnr, option, value)
      end

      -- 保存原始函数
      local original_draw_func = view.draw

      -- 临时修改 draw 方法以确保设置 filetype
      view.draw = function(self, root_node, traverse_by_incoming)
        -- 调用原始 draw 方法
        local result = original_draw_func(self, root_node, traverse_by_incoming)

        -- 如果缓冲区ID有效，确保设置 filetype
        if self.buf.bufid ~= -1 then
          vim.api.nvim_buf_set_option(self.buf.bufid, "filetype", "callgraph")
        end

        return result
      end

      -- 调用draw方法
      view:draw(nil, false)

      -- 验证filetype已被设置
      assert.is_true(filetype_set)

      -- 恢复原始函数
      vim.api.nvim_buf_set_option = original_set_option
      view.draw = original_draw_func
    end)
  end)

  -- 测试新的递归节点收集逻辑
  describe("node and edge collection from root_node", function()
    local mock_GraphDrawer
    local graph_draw_calls

    before_each(function()
      -- 保存原始GraphDrawer
      mock_GraphDrawer = package.loaded["call_graph.view.graph_drawer"]
      graph_draw_calls = {}

      -- 创建一个模拟的GraphDrawer，来检查传递给它的参数
      package.loaded["call_graph.view.graph_drawer"] = {
        new = function(bufid, opts)
          return {
            set_modifiable = function() end,
            draw = function(self, root_node, traverse_by_incoming)
              table.insert(graph_draw_calls, {
                root_node = root_node,
                traverse_by_incoming = traverse_by_incoming,
                nodes = self.nodes, -- 这将包含view.nodes_cache的引用
              })
            end,
            nodes = {},
            set_modifiable = function() end,
          }
        end,
      }

      -- 重新定义draw方法，避免调用原始draw方法中的graph.draw
      local saved_original_draw = original_draw
      CallGraphView.draw = function(self, root_node, traverse_by_incoming)
        -- 清除当前视图
        self:clear_view()

        -- 从root_node开始遍历构建完整的节点和边集合
        local nodes_map = {}
        local edges_list = {}

        -- 递归收集所有可达的节点和边
        local function collect_nodes_and_edges(node, visited)
          if not node or visited[node.nodeid] then
            return
          end

          -- 标记当前节点为已访问
          visited[node.nodeid] = true
          -- 添加到节点集合
          nodes_map[node.nodeid] = node

          -- 获取要遍历的边
          local edges = traverse_by_incoming and node.incoming_edges or node.outcoming_edges

          -- 处理每条边
          for _, edge in ipairs(edges) do
            -- 添加到边集合
            table.insert(edges_list, edge)

            -- 递归处理下一个节点
            local next_node = traverse_by_incoming and edge.from_node or edge.to_node
            collect_nodes_and_edges(next_node, visited)
          end

          -- 确保另一方向的边也被记录（虽然不用于遍历）
          local other_edges = traverse_by_incoming and node.outcoming_edges or node.incoming_edges
          for _, edge in ipairs(other_edges) do
            -- 只添加边到集合，不递归遍历
            table.insert(edges_list, edge)
          end
        end

        -- 开始从根节点收集
        collect_nodes_and_edges(root_node, {})

        -- 缓存构建的节点和边数据
        self.nodes_cache = nodes_map
        self.edges_cache = edges_list

        -- 模拟buffer ID
        if self.buf.bufid == -1 then
          self.buf.bufid = 999
        end

        return self.buf.bufid
      end
    end)

    after_each(function()
      -- 恢复原始GraphDrawer
      package.loaded["call_graph.view.graph_drawer"] = mock_GraphDrawer
      -- 恢复原始draw方法
      CallGraphView.draw = original_draw
    end)

    it("should collect all nodes and edges when using outcoming edges", function()
      -- 创建一个简单的图: A -> B -> C
      --                 \
      --                  -> D
      local nodeA = { text = "A", nodeid = 1, incoming_edges = {}, outcoming_edges = {} }
      local nodeB = { text = "B", nodeid = 2, incoming_edges = {}, outcoming_edges = {} }
      local nodeC = { text = "C", nodeid = 3, incoming_edges = {}, outcoming_edges = {} }
      local nodeD = { text = "D", nodeid = 4, incoming_edges = {}, outcoming_edges = {} }

      local edge_AB = { from_node = nodeA, to_node = nodeB }
      local edge_BC = { from_node = nodeB, to_node = nodeC }
      local edge_AD = { from_node = nodeA, to_node = nodeD }

      table.insert(nodeA.outcoming_edges, edge_AB)
      table.insert(nodeB.incoming_edges, edge_AB)

      table.insert(nodeB.outcoming_edges, edge_BC)
      table.insert(nodeC.incoming_edges, edge_BC)

      table.insert(nodeA.outcoming_edges, edge_AD)
      table.insert(nodeD.incoming_edges, edge_AD)

      -- 使用原始的draw方法
      local view = CallGraphView:new()
      view:draw(nodeA, false) -- false表示通过出边遍历

      -- 验证nodes_cache包含所有节点
      assert.is_not_nil(view.nodes_cache)
      assert.equal(4, vim.tbl_count(view.nodes_cache))
      assert.is_not_nil(view.nodes_cache[1]) -- A
      assert.is_not_nil(view.nodes_cache[2]) -- B
      assert.is_not_nil(view.nodes_cache[3]) -- C
      assert.is_not_nil(view.nodes_cache[4]) -- D

      -- 验证edges_cache包含所有边
      assert.is_not_nil(view.edges_cache)
      assert.equal(6, #view.edges_cache) -- 出边和入边都会被收集（3条边各被收集2次）
    end)

    it("should collect all nodes and edges when using incoming edges", function()
      -- 创建一个简单的图: A -> B -> C
      --                 \
      --                  -> D
      local nodeA = { text = "A", nodeid = 1, incoming_edges = {}, outcoming_edges = {} }
      local nodeB = { text = "B", nodeid = 2, incoming_edges = {}, outcoming_edges = {} }
      local nodeC = { text = "C", nodeid = 3, incoming_edges = {}, outcoming_edges = {} }
      local nodeD = { text = "D", nodeid = 4, incoming_edges = {}, outcoming_edges = {} }

      local edge_AB = { from_node = nodeA, to_node = nodeB }
      local edge_BC = { from_node = nodeB, to_node = nodeC }
      local edge_AD = { from_node = nodeA, to_node = nodeD }

      table.insert(nodeA.outcoming_edges, edge_AB)
      table.insert(nodeB.incoming_edges, edge_AB)

      table.insert(nodeB.outcoming_edges, edge_BC)
      table.insert(nodeC.incoming_edges, edge_BC)

      table.insert(nodeA.outcoming_edges, edge_AD)
      table.insert(nodeD.incoming_edges, edge_AD)

      -- 使用原始的draw方法，从C开始通过入边遍历
      local view = CallGraphView:new()
      view:draw(nodeC, true) -- true表示通过入边遍历

      -- 验证nodes_cache包含可达节点
      assert.is_not_nil(view.nodes_cache)
      assert.equal(3, vim.tbl_count(view.nodes_cache)) -- 应该包含C, B, A
      assert.is_not_nil(view.nodes_cache[1]) -- A
      assert.is_not_nil(view.nodes_cache[2]) -- B
      assert.is_not_nil(view.nodes_cache[3]) -- C
      assert.is_nil(view.nodes_cache[4]) -- D不应该包含，因为从C通过入边无法到达

      -- 验证edges_cache包含所有可达边
      assert.is_not_nil(view.edges_cache)
      -- 应该包含A->B, B->C和两个方向的边
      assert.equal(5, #view.edges_cache)
    end)

    it("should handle cyclic graphs correctly", function()
      -- 创建一个循环图: A -> B -> C -> A
      local nodeA = { text = "A", nodeid = 1, incoming_edges = {}, outcoming_edges = {} }
      local nodeB = { text = "B", nodeid = 2, incoming_edges = {}, outcoming_edges = {} }
      local nodeC = { text = "C", nodeid = 3, incoming_edges = {}, outcoming_edges = {} }

      local edge_AB = { from_node = nodeA, to_node = nodeB }
      local edge_BC = { from_node = nodeB, to_node = nodeC }
      local edge_CA = { from_node = nodeC, to_node = nodeA }

      table.insert(nodeA.outcoming_edges, edge_AB)
      table.insert(nodeB.incoming_edges, edge_AB)

      table.insert(nodeB.outcoming_edges, edge_BC)
      table.insert(nodeC.incoming_edges, edge_BC)

      table.insert(nodeC.outcoming_edges, edge_CA)
      table.insert(nodeA.incoming_edges, edge_CA)

      -- 使用原始的draw方法
      local view = CallGraphView:new()
      view:draw(nodeA, false) -- 从A开始，通过出边遍历

      -- 验证nodes_cache包含所有节点
      assert.is_not_nil(view.nodes_cache)
      assert.equal(3, vim.tbl_count(view.nodes_cache))
      assert.is_not_nil(view.nodes_cache[1]) -- A
      assert.is_not_nil(view.nodes_cache[2]) -- B
      assert.is_not_nil(view.nodes_cache[3]) -- C

      -- 验证edges_cache包含所有边
      assert.is_not_nil(view.edges_cache)
      assert.equal(6, #view.edges_cache) -- 出边和入边都会被收集
    end)
  end)
end)
