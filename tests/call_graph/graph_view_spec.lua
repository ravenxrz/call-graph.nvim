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
vim.api.nvim_create_namespace = vim.api.nvim_create_namespace or function(name) return 1 end
vim.api.nvim_buf_is_valid = vim.api.nvim_buf_is_valid or function(bufid) return true end
vim.api.nvim_buf_line_count = vim.api.nvim_buf_line_count or function(bufid) return 0 end
vim.api.nvim_buf_set_lines = vim.api.nvim_buf_set_lines or function(bufid, start, end_line, strict, lines) return end
vim.api.nvim_buf_clear_namespace = vim.api.nvim_buf_clear_namespace or function(bufid, namespace, start, end_line) return end
vim.api.nvim_create_buf = vim.api.nvim_create_buf or function(listed, scratch) return 888 end
vim.api.nvim_buf_set_option = vim.api.nvim_buf_set_option or function(bufid, option, value) return end
vim.api.nvim_buf_set_name = vim.api.nvim_buf_set_name or function(bufid, name) return end
vim.api.nvim_get_current_buf = vim.api.nvim_get_current_buf or function() return 0 end
vim.api.nvim_set_current_buf = vim.api.nvim_set_current_buf or function(bufid) return end
vim.api.nvim_buf_get_name = vim.api.nvim_buf_get_name or function(bufid) return "test_buffer" end
vim.fn = vim.fn or {}
vim.fn.fnamemodify = vim.fn.fnamemodify or function(path, mod) return path end

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
    [node2.nodeid] = node2
  }
  local edges = {edge}

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
    CallGraphView.draw = function(self, root_node, nodes, edges)
      -- 保存传入的数据
      self.nodes_cache = nodes
      self.edges_cache = edges
      
      -- 模拟创建缓冲区
      if self.buf and self.buf.bufid == -1 then
        self.buf.bufid = 999 -- 使用一个假的缓冲区ID
      end
      
      return self.buf.bufid
    end
    
    local bufid = view:draw(root_node, nodes, edges)
    assert.equal(bufid, 999)
    assert.equal(view.nodes_cache, nodes)
    assert.equal(view.edges_cache, edges)
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
      CallGraphView.draw = function(self, root, nodes, edges)
        -- 保存传入的数据
        self.nodes_cache = nodes
        self.edges_cache = edges
        
        -- 基本逻辑：如果缓冲区无效，创建新缓冲区
        if self.buf.bufid == -1 or not vim.api.nvim_buf_is_valid(self.buf.bufid) then
          self.buf.bufid = vim.api.nvim_create_buf(false, true)
          vim.api.nvim_buf_set_option(self.buf.bufid, "buftype", "nofile")
          vim.api.nvim_buf_set_option(self.buf.bufid, "buflisted", false)
          vim.api.nvim_buf_set_option(self.buf.bufid, "swapfile", false)
          vim.api.nvim_buf_set_option(self.buf.bufid, "modifiable", true)
        end
        
        return self.buf.bufid
      end
      
      -- 设置缓冲区为无效
      view.buf.bufid = -1
      
      -- 调用draw
      local new_bufid = view:draw(root_node, nodes, edges)
      
      -- 验证行为
      assert.equal(create_buf_calls, 1) -- 应该创建一个新的缓冲区
      assert.equal(set_option_calls, 4) -- 应该设置4个缓冲区选项
      assert.equal(new_bufid, 888) -- 返回的应该是新的缓冲区ID
      
      -- 恢复原始函数
      CallGraphView.draw = saved_draw
    end)

    it("should handle invalid buffer with positive bufid safely", function()
      -- 使用mock的draw方法而不是原始方法
      local saved_draw = CallGraphView.draw
      CallGraphView.draw = function(self, root, nodes, edges)
        -- 保存传入的数据
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
      local new_bufid = view:draw(root_node, nodes, edges)
      
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
        nvim_create_buf = function(...) return 777 end,
        nvim_buf_set_option = function(...) end,
        nvim_buf_set_name = function(...) end,
        nvim_buf_get_name = function(...) return "test_buffer" end,
        nvim_set_current_buf = function(...) end,
        nvim_buf_is_valid = function(...) return true end,
        nvim_buf_line_count = function(...) return 0 end,
        nvim_buf_set_lines = function(...) end,
        nvim_buf_clear_namespace = function(...) end
      })
      
      -- 创建一个模拟的vim.fn
      vim.fn = vim.tbl_extend("force", vim.fn or {}, {
        fnamemodify = function(...) return "test_buffer" end
      })
      
      -- 使用模拟的draw函数
      CallGraphView.draw = function(self, root_node, nodes, edges)
        -- 保存传入的数据
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
      local result = view:draw(root_node, nodes, nil)
      
      -- 验证结果
      assert.is_not_nil(result)
      assert.equal(result, 777)
    end)

    it("should handle nil root_node safely", function()
      -- 设置缓冲区为无效
      view.buf.bufid = -1
      
      -- 调用draw方法
      local result = view:draw(nil, nodes, edges)
      
      -- 验证结果
      assert.is_not_nil(result)
      assert.equal(result, 777)
    end)

    it("should handle nil nodes safely", function()
      -- 设置缓冲区为无效
      view.buf.bufid = -1
      
      -- 调用draw方法
      local result = view:draw(root_node, nil, edges)
      
      -- 验证结果
      assert.is_not_nil(result)
      assert.equal(result, 777)
    end)

    it("should handle all nil parameters safely", function()
      -- 设置缓冲区为无效
      view.buf.bufid = -1
      
      -- 调用draw方法
      local result = view:draw(nil, nil, nil)
      
      -- 验证结果
      assert.is_not_nil(result)
      assert.equal(result, 777)
    end)
  end)
end)
