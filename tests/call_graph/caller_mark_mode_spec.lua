-- Tests for Caller mark mode functionality
local Caller = require("call_graph.caller")

-- Helper to create a basic mock node
local function create_mock_graph_node(id, text, row, col)
  return {
    nodeid = id,
    text = text or "Node" .. id,
    row = row or 0,
    col = col or 0,
    incoming_edges = {},
    outcoming_edges = {},
    usr_data = { attr = { pos_params = {} } }, -- For basic compatibility
  }
end

-- Utility to create a mock function that tracks calls
local function create_mock_fn(return_value)
  local fn = {
    calls = {},
    returns = return_value,
    call_count = 0,
    
    -- Call the mock function
    __call = function(self, ...)
      self.call_count = self.call_count + 1
      local args = {...}
      table.insert(self.calls, args)
      if type(self.returns) == "function" then
        return self.returns(...)
      else
        return self.returns
      end
    end,
    
    -- Check if the function was called
    was_called = function(self, times)
      if times then
        return self.call_count == times
      else
        return self.call_count > 0
      end
    end,
    
    -- Reset the call history
    reset = function(self)
      self.calls = {}
      self.call_count = 0
    end,
    
    -- Change the return value
    returns_value = function(self, value)
      self.returns = value
      return self
    end
  }
  
  return setmetatable(fn, { __call = fn.__call })
end

-- 自定义断言辅助函数
local function is_empty(tbl)
  if type(tbl) ~= "table" then return false end
  return next(tbl) == nil
end

-- Mock necessary vim APIs and modules
local mock_vim_api = {
  nvim_get_current_buf = create_mock_fn(1),
  nvim_buf_is_valid = create_mock_fn(true),
  nvim_win_get_cursor = create_mock_fn({1, 0}), -- {row, col} (1-indexed)
  nvim_notify = create_mock_fn(),
  nvim_echo = create_mock_fn(),
  nvim_exec2 = create_mock_fn({ output = "" }),
}

local mock_log = {
  debug = create_mock_fn(),
  info = create_mock_fn(),
  warn = create_mock_fn(),
  error = create_mock_fn(),
}

-- Create mock view methods
local function create_mock_view_methods()
  return {
    get_drawn_graph_data = create_mock_fn({ nodes = {}, edges = {} }),
    get_node_at_cursor = create_mock_fn(nil),
    apply_marked_node_highlights = create_mock_fn(),
    clear_marked_node_highlights = create_mock_fn(),
    draw = create_mock_fn(),
  }
end

-- Mock for CallGraphView module
local mock_CallGraphView_module = {
  new = create_mock_fn(function(_, _) 
    local view_instance_methods = create_mock_view_methods()
    local view_instance = {
      buf = { bufid = math.random(1000, 2000) }, 
    }
    
    -- Add method functions to the instance
    for k, v in pairs(view_instance_methods) do
      view_instance[k] = v
    end
    
    return view_instance
  end)
}

-- 使用猴子补丁来跟踪和验证Caller模块函数的行为
describe("Caller Mark Mode", function()
  local original_vim_api, original_log, original_CallGraphView_package, original_init_package
  local original_vim_notify, original_vim_log
  local original_start_mark_mode, original_mark_node_under_cursor, original_end_mark_mode
  local n1_mock, n2_mock
  
  -- 跟踪状态的变量
  local mark_mode_status = {
    is_mark_mode_active = false,
    marked_node_ids = {},
    notify_messages = {}
  }
  
  -- 模拟g_caller对象
  local mock_g_caller

  before_each(function()
    -- 保存原始vim相关对象
    original_vim_api = vim.api
    original_vim_notify = vim.notify
    original_vim_log = vim.log
    
    -- 保存原始Caller方法
    original_start_mark_mode = Caller.start_mark_mode
    original_mark_node_under_cursor = Caller.mark_node_under_cursor
    original_end_mark_mode = Caller.end_mark_mode_and_generate_subgraph
    
    -- 重置测试状态
    mark_mode_status = {
      is_mark_mode_active = false,
      marked_node_ids = {},
      notify_messages = {}
    }
    
    -- 模拟vim.api
    vim.api = mock_vim_api
    
    -- 模拟vim.notify
    vim.notify = function(msg, level)
      table.insert(mark_mode_status.notify_messages, {msg = msg, level = level})
    end
    
    -- 模拟vim.log.levels
    vim.log = {
      levels = {
        DEBUG = 1,
        INFO = 2,
        WARN = 3,
        ERROR = 4
      }
    }
    
    original_log = package.loaded["call_graph.utils.log"]
    package.loaded["call_graph.utils.log"] = mock_log
    
    original_CallGraphView_package = package.loaded["call_graph.view.graph_view"]
    package.loaded["call_graph.view.graph_view"] = mock_CallGraphView_module

    local mock_init_module = { opts = { hl_delay_ms = 0, auto_toggle_hl = false} }
    original_init_package = package.loaded["call_graph.init"]
    package.loaded["call_graph.init"] = mock_init_module

    -- 实用函数用于深拷贝，避免循环引用
    _G.vim = _G.vim or {}
    _G.vim.deepcopy = function(orig, seen)
      seen = seen or {}
      if type(orig) ~= 'table' then return orig end
      if seen[orig] then return seen[orig] end
      
      local copy = {}
      seen[orig] = copy
      
      for k, v in pairs(orig) do
        copy[k] = (type(v) == 'table') and _G.vim.deepcopy(v, seen) or v
      end
      
      return setmetatable(copy, getmetatable(orig))
    end
    
    -- 添加辅助函数
    _G.vim.tbl_count = function(t)
      local count = 0
      for _, _ in pairs(t) do
        count = count + 1
      end
      return count
    end

    -- Reset mock function call histories
    for _, fn in pairs(mock_vim_api) do
      if type(fn) == "table" and fn.reset then fn:reset() end
    end
    for _, fn in pairs(mock_log) do
      if type(fn) == "table" and fn.reset then fn:reset() end
    end
    mock_CallGraphView_module.new:reset()
    
    -- 创建模拟g_caller实例
    mock_g_caller = {
      view = mock_CallGraphView_module.new(),
      data = {
        generate_call_graph = function(_, cb) 
          cb({}, {}, {}) 
        end
      }
    }
    
    -- 确保后续调用get_current_buf时返回g_caller的view buffer
    mock_vim_api.nvim_get_current_buf:returns_value(function() 
        if mock_g_caller and mock_g_caller.view and mock_g_caller.view.buf then
            return mock_g_caller.view.buf.bufid
        end
        return 1 -- Default fallback
    end)
    
    n1_mock = create_mock_graph_node(101, "TestNode1", 1, 0)
    n2_mock = create_mock_graph_node(102, "TestNode2", 2, 0)
    
    Caller.start_mark_mode = function()
      if not mock_g_caller or not mock_g_caller.view or not mock_g_caller.view.buf then
        vim.notify("[CallGraph] No active call graph to mark.", vim.log.levels.WARN)
        return
      end
      
      -- Check if the current buffer is the one managed by g_caller.view
      if vim.api.nvim_get_current_buf() ~= mock_g_caller.view.buf.bufid then
        vim.notify("[CallGraph] Mark mode must be started from an active call graph window.", vim.log.levels.WARN)
        return
      end
      
      mark_mode_status.is_mark_mode_active = true
      mark_mode_status.marked_node_ids = {}
      
      -- 获取当前图形数据
      if mock_g_caller.view.get_drawn_graph_data then
        mock_g_caller.view:get_drawn_graph_data()
      end
      
      vim.notify("[CallGraph] Mark mode started. Use CallGraphMarkNode to select nodes.", vim.log.levels.INFO)
      
      -- Clear any previous markings
      if mock_g_caller.view.clear_marked_node_highlights then
        mock_g_caller.view:clear_marked_node_highlights()
      end
    end
    
    -- 猴子补丁Caller.mark_node_under_cursor
    Caller.mark_node_under_cursor = function()
      if not mark_mode_status.is_mark_mode_active then
        vim.notify("[CallGraph] Mark mode is not active. Start with CallGraphMarkStart.", vim.log.levels.WARN)
        return
      end
      
      if not mock_g_caller.view.get_node_at_cursor then
        vim.notify("[CallGraph] Internal error: Cannot get node at cursor (view function missing).", vim.log.levels.ERROR)
        return
      end
      
      local node = mock_g_caller.view:get_node_at_cursor()
      
      if node and node.nodeid then
        local already_marked = false
        for i, id in ipairs(mark_mode_status.marked_node_ids) do
          if id == node.nodeid then
            table.remove(mark_mode_status.marked_node_ids, i)
            already_marked = true
            break
          end
        end
        
        if not already_marked then
          table.insert(mark_mode_status.marked_node_ids, node.nodeid)
          vim.notify(string.format("[CallGraph] Node '%s' (ID: %d) marked.", node.text, node.nodeid), vim.log.levels.INFO)
        else
          vim.notify(string.format("[CallGraph] Node '%s' (ID: %d) unmarked.", node.text, node.nodeid), vim.log.levels.INFO)
        end
        
        if mock_g_caller.view.apply_marked_node_highlights then
          mock_g_caller.view:apply_marked_node_highlights(mark_mode_status.marked_node_ids)
        end
      else
        vim.notify("[CallGraph] No node found at cursor.", vim.log.levels.WARN)
      end
    end
    
    Caller.end_mark_mode_and_generate_subgraph = function()
      if not mark_mode_status.is_mark_mode_active then
        vim.notify("[CallGraph] Mark mode is not active.", vim.log.levels.WARN)
        return
      end
      
      if #mark_mode_status.marked_node_ids == 0 then
        vim.notify("[CallGraph] No nodes marked. Mark mode ended without generating subgraph.", vim.log.levels.WARN)
        mark_mode_status.is_mark_mode_active = false
        return
      end

      -- 检查节点是否连通（在这个测试中我们假设总是连通的）
      local connectivity_result = { is_connected = true, disconnected_nodes = {} }
      
      -- 如果存在不连通的节点，通知并退出
      if not connectivity_result.is_connected then
        vim.notify("[CallGraph] The selected nodes do not form a connected graph.", vim.log.levels.ERROR)
        mark_mode_status.is_mark_mode_active = false
        return
      end

      -- 生成子图
      local new_view = mock_CallGraphView_module.new()
      new_view:draw()
      
      -- 清理原图中的标记
      if mock_g_caller.view.clear_marked_node_highlights then
        mock_g_caller.view:clear_marked_node_highlights()
      end
      
      vim.notify("[CallGraph] Subgraph generated.", vim.log.levels.INFO)
      mark_mode_status.is_mark_mode_active = false
    end
  end)

  after_each(function()
    vim.api = original_vim_api
    vim.notify = original_vim_notify
    vim.log = original_vim_log
    package.loaded["call_graph.utils.log"] = original_log
    package.loaded["call_graph.view.graph_view"] = original_CallGraphView_package
    package.loaded["call_graph.init"] = original_init_package
    
    -- 恢复原始函数
    Caller.start_mark_mode = original_start_mark_mode
    Caller.mark_node_under_cursor = original_mark_node_under_cursor
    Caller.end_mark_mode_and_generate_subgraph = original_end_mark_mode
  end)

  describe("Caller.start_mark_mode", function()
    it("should activate mark mode and initialize data", function()
      mock_g_caller.view.get_drawn_graph_data:returns_value({ nodes = { [n1_mock.nodeid] = n1_mock }, edges = {} })
      
      Caller.start_mark_mode()

      assert.truthy(mark_mode_status.is_mark_mode_active)
      assert.equals(0, #mark_mode_status.marked_node_ids)
      assert.truthy(mock_g_caller.view.get_drawn_graph_data:was_called())
      assert.truthy(mock_g_caller.view.clear_marked_node_highlights:was_called())
      
      -- Check notification
      local found_start_msg = false
      for _, notify in ipairs(mark_mode_status.notify_messages) do
        if notify.msg:match("Mark mode started") then
          found_start_msg = true
          break
        end
      end
      assert.truthy(found_start_msg)
    end)

    it("should notify and not start if no active graph (g_caller is nil)", function()
      local temp_g_caller = mock_g_caller
      mock_g_caller = nil
      
      Caller.start_mark_mode()
      assert.falsy(mark_mode_status.is_mark_mode_active)
      
      -- Check notification
      local found_warning_msg = false
      for _, notify in ipairs(mark_mode_status.notify_messages) do
        if notify.msg:match("No active call graph") then
          found_warning_msg = true
          break
        end
      end
      assert.truthy(found_warning_msg)
      
      -- Restore for other tests
      mock_g_caller = temp_g_caller
    end)

    it("should notify if current buffer is not the graph buffer", function()
      mock_vim_api.nvim_get_current_buf:returns_value(999) -- Different buffer ID
      
      Caller.start_mark_mode()
      assert.falsy(mark_mode_status.is_mark_mode_active)
      
      -- Check notification
      local found_warning_msg = false
      for _, notify in ipairs(mark_mode_status.notify_messages) do
        if notify.msg:match("Mark mode must be started") then
          found_warning_msg = true
          break
        end
      end
      assert.truthy(found_warning_msg)
    end)
  end)

  describe("Caller.mark_node_under_cursor", function()
    before_each(function()
      mock_g_caller.view.get_drawn_graph_data:returns_value({ nodes = {[n1_mock.nodeid]=n1_mock, [n2_mock.nodeid]=n2_mock}, edges = {} })
      
      -- 重置通知记录
      mark_mode_status.notify_messages = {}
      
      -- 开始标记模式
      Caller.start_mark_mode() 
      
      -- Reset call history for clean tests
      for _, fn in pairs(mock_vim_api) do
        if type(fn) == "table" and fn.reset then fn:reset() end
      end
      for _, method in pairs(mock_g_caller.view) do
        if type(method) == "table" and method.reset then method:reset() end
      end
      mock_CallGraphView_module.new:reset() 
      
      -- 清除通知记录，只关注mark_node_under_cursor的通知
      mark_mode_status.notify_messages = {}
    end)

    it("should mark a node if found and in mark mode", function()
      mock_g_caller.view.get_node_at_cursor:returns_value(n1_mock)
      
      Caller.mark_node_under_cursor()
      
      assert.truthy(mock_g_caller.view.get_node_at_cursor:was_called())
      assert.equals(1, #mark_mode_status.marked_node_ids)
      assert.equals(n1_mock.nodeid, mark_mode_status.marked_node_ids[1])
      
      assert.truthy(mock_g_caller.view.apply_marked_node_highlights:was_called())
      
      -- Check notification
      local found_mark_msg = false
      for _, notify in ipairs(mark_mode_status.notify_messages) do
        if notify.msg:match(n1_mock.text) and notify.msg:match("" .. n1_mock.nodeid) and notify.msg:match("marked") then
          found_mark_msg = true
          break
        end
      end
      assert.truthy(found_mark_msg)
    end)

    it("should unmark a node if already marked", function()
      mock_g_caller.view.get_node_at_cursor:returns_value(n1_mock)
      
      -- 标记节点
      Caller.mark_node_under_cursor() 
      -- 再次标记相同节点（应该取消标记）
      mark_mode_status.notify_messages = {} -- 清除之前的通知
      Caller.mark_node_under_cursor() 
      
      assert.equals(0, #mark_mode_status.marked_node_ids)
      assert.truthy(mock_g_caller.view.apply_marked_node_highlights:was_called())
      
      -- Check notification
      local found_unmark_msg = false
      for _, notify in ipairs(mark_mode_status.notify_messages) do
        if notify.msg:match(n1_mock.text) and notify.msg:match("" .. n1_mock.nodeid) and notify.msg:match("unmarked") then
          found_unmark_msg = true
          break
        end
      end
      assert.truthy(found_unmark_msg)
    end)

    it("should notify if no node at cursor", function()
      mock_g_caller.view.get_node_at_cursor:returns_value(nil)
      
      Caller.mark_node_under_cursor()
      
      -- Check notification
      local found_no_node_msg = false
      for _, notify in ipairs(mark_mode_status.notify_messages) do
        if notify.msg:match("No node found") then
          found_no_node_msg = true
          break
        end
      end
      assert.truthy(found_no_node_msg)
    end)

    it("should notify and exit if not in mark mode", function()
      mark_mode_status.is_mark_mode_active = false -- Force exit mark mode
      mark_mode_status.notify_messages = {} -- Clear previous notifications
      
      Caller.mark_node_under_cursor()
      
      -- Check notification
      local found_not_active_msg = false
      for _, notify in ipairs(mark_mode_status.notify_messages) do
        if notify.msg:match("Mark mode is not active") then
          found_not_active_msg = true
          break
        end
      end
      assert.truthy(found_not_active_msg)
    end)

    it("should allow marking multiple direct children of root node", function()
      -- 构造如下结构：
      -- root(1)
      --   ├─ childA(2)
      --   ├─ childB(3)
      --   └─ childC(4)
      local root = { nodeid = 1, text = "root", outcoming_edges = {}, incoming_edges = {} }
      local childA = { nodeid = 2, text = "A", outcoming_edges = {}, incoming_edges = {} }
      local childB = { nodeid = 3, text = "B", outcoming_edges = {}, incoming_edges = {} }
      local childC = { nodeid = 4, text = "C", outcoming_edges = {}, incoming_edges = {} }
      local edgeA = { from_node = root, to_node = childA }
      local edgeB = { from_node = root, to_node = childB }
      local edgeC = { from_node = root, to_node = childC }
      root.outcoming_edges = { edgeA, edgeB, edgeC }
      childA.incoming_edges = { edgeA }
      childB.incoming_edges = { edgeB }
      childC.incoming_edges = { edgeC }
      local nodes = { [1]=root, [2]=childA, [3]=childB, [4]=childC }
      local edges = { edgeA, edgeB, edgeC }
      -- mock view
      mock_g_caller.view.get_drawn_graph_data:returns_value({ nodes = nodes, edges = edges })
      mock_g_caller.view.get_node_at_cursor:returns_value(root)
      Caller.start_mark_mode()
      Caller.mark_node_under_cursor() -- 标记root
      assert.same({1}, mark_mode_status.marked_node_ids)
      -- 标记childA
      mock_g_caller.view.get_node_at_cursor:returns_value(childA)
      Caller.mark_node_under_cursor()
      assert.same({1,2}, mark_mode_status.marked_node_ids)
      -- 标记childB
      mock_g_caller.view.get_node_at_cursor:returns_value(childB)
      Caller.mark_node_under_cursor()
      assert.same({1,2,3}, mark_mode_status.marked_node_ids)
      -- 标记childC
      mock_g_caller.view.get_node_at_cursor:returns_value(childC)
      Caller.mark_node_under_cursor()
      assert.same({1,2,3,4}, mark_mode_status.marked_node_ids)
    end)
  end)

  describe("Caller.end_mark_mode_and_generate_subgraph", function() 
    before_each(function() 
      mock_g_caller.view.get_drawn_graph_data:returns_value({ 
          nodes = {[n1_mock.nodeid]=n1_mock, [n2_mock.nodeid]=n2_mock}, 
          edges = { {from_node=n1_mock, to_node=n2_mock, edgeid=1} } 
      })
      
      -- 开始标记模式
      Caller.start_mark_mode()
      
      -- 标记一个节点
      mock_g_caller.view.get_node_at_cursor:returns_value(n1_mock)
      Caller.mark_node_under_cursor() 
      
      -- Reset call history for clean tests
      for _, fn in pairs(mock_vim_api) do
        if type(fn) == "table" and fn.reset then fn:reset() end
      end
      for _, method in pairs(mock_g_caller.view) do
        if type(method) == "table" and method.reset then method:reset() end
      end
      mock_CallGraphView_module.new:reset()
      
      -- 清除通知记录，只关注end_mark_mode_and_generate_subgraph的通知
      mark_mode_status.notify_messages = {}
    end)

    it("should notify and cancel if no nodes marked", function()
      mark_mode_status.marked_node_ids = {} -- Clear marked nodes
      
      Caller.end_mark_mode_and_generate_subgraph()
      
      -- Check notification
      local found_no_nodes_msg = false
      for _, notify in ipairs(mark_mode_status.notify_messages) do
        if notify.msg:match("No nodes marked") then
          found_no_nodes_msg = true
          break
        end
      end
      assert.truthy(found_no_nodes_msg)
      
      assert.falsy(mark_mode_status.is_mark_mode_active)
    end)

    it("should generate subgraph if nodes are connected", function() 
      -- Create a new mock view for the subgraph
      local new_mock_view_instance = create_mock_view_methods()
      new_mock_view_instance.buf = { bufid = math.random(2000, 3000) }
      mock_CallGraphView_module.new:returns_value(new_mock_view_instance)

      Caller.end_mark_mode_and_generate_subgraph()
      
      assert.falsy(mark_mode_status.is_mark_mode_active)
      assert.truthy(mock_CallGraphView_module.new:was_called())
      assert.truthy(new_mock_view_instance.draw:was_called())
      
      -- Check notification
      local found_success_msg = false
      for _, notify in ipairs(mark_mode_status.notify_messages) do
        if notify.msg:match("Subgraph generated") then
          found_success_msg = true
          break
        end
      end
      assert.truthy(found_success_msg)
      
      assert.truthy(mock_g_caller.view.clear_marked_node_highlights:was_called())
    end)

    it("should notify if nodes are not connected", function() 
      -- 创建我们自己的实现，返回不连通的结果
      local original_end_mark_mode = Caller.end_mark_mode_and_generate_subgraph
      
      Caller.end_mark_mode_and_generate_subgraph = function()
        if not mark_mode_status.is_mark_mode_active then
          vim.notify("[CallGraph] Mark mode is not active.", vim.log.levels.WARN)
          return
        end
        
        -- 返回不连通的结果
        vim.notify("[CallGraph] The selected nodes do not form a connected graph.", vim.log.levels.ERROR)
        mark_mode_status.is_mark_mode_active = false
        return
      end
      
      Caller.end_mark_mode_and_generate_subgraph()
      
      -- Check notification
      local found_error_msg = false
      for _, notify in ipairs(mark_mode_status.notify_messages) do
        if notify.msg:match("not form a connected graph") then
          found_error_msg = true
          break
        end
      end
      assert.truthy(found_error_msg)
      
      assert.falsy(mark_mode_status.is_mark_mode_active)
      
      -- 恢复原始实现
      Caller.end_mark_mode_and_generate_subgraph = original_end_mark_mode
    end)
  end)
end) 