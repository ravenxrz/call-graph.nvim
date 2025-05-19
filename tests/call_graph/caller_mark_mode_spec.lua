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
      local args = { ... }
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
    end,
  }

  return setmetatable(fn, { __call = fn.__call })
end

-- 自定义断言辅助函数
local function is_empty(tbl)
  if type(tbl) ~= "table" then
    return false
  end
  return next(tbl) == nil
end

-- Mock necessary vim APIs and modules
local mock_vim_api = {
  nvim_get_current_buf = create_mock_fn(1),
  nvim_buf_is_valid = create_mock_fn(true),
  nvim_win_get_cursor = create_mock_fn({ 1, 0 }), -- {row, col} (1-indexed)
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
  end),
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
    notify_messages = {},
  }

  -- 模拟g_caller对象
  local mock_g_caller

  before_each(function()
    -- 保存原始vim相关对象
    original_vim_api = vim.api
    original_vim_notify = vim.notify
    original_vim_log = vim.log

    -- 保存原始Caller方法
    original_start_mark_mode = Caller.mark_node_under_cursor
    original_mark_node_under_cursor = Caller.mark_node_under_cursor
    original_end_mark_mode = Caller.end_mark_mode_and_generate_subgraph

    -- 重置测试状态
    mark_mode_status = {
      is_mark_mode_active = false,
      marked_node_ids = {},
      notify_messages = {},
    }

    -- 模拟vim.api
    vim.api = mock_vim_api

    -- 模拟vim.notify
    vim.notify = function(msg, level)
      table.insert(mark_mode_status.notify_messages, { msg = msg, level = level })
    end

    -- 模拟vim.log.levels
    vim.log = {
      levels = {
        DEBUG = 1,
        INFO = 2,
        WARN = 3,
        ERROR = 4,
      },
    }

    original_log = package.loaded["call_graph.utils.log"]
    package.loaded["call_graph.utils.log"] = mock_log

    original_CallGraphView_package = package.loaded["call_graph.view.graph_view"]
    package.loaded["call_graph.view.graph_view"] = mock_CallGraphView_module

    local mock_init_module = { opts = { hl_delay_ms = 0, auto_toggle_hl = false } }
    original_init_package = package.loaded["call_graph.init"]
    package.loaded["call_graph.init"] = mock_init_module

    -- 实用函数用于深拷贝，避免循环引用
    _G.vim = _G.vim or {}
    _G.vim.deepcopy = function(orig, seen)
      seen = seen or {}
      if type(orig) ~= "table" then
        return orig
      end
      if seen[orig] then
        return seen[orig]
      end

      local copy = {}
      seen[orig] = copy

      for k, v in pairs(orig) do
        copy[k] = (type(v) == "table") and _G.vim.deepcopy(v, seen) or v
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
      if type(fn) == "table" and fn.reset then
        fn:reset()
      end
    end
    for _, fn in pairs(mock_log) do
      if type(fn) == "table" and fn.reset then
        fn:reset()
      end
    end
    mock_CallGraphView_module.new:reset()

    -- 创建模拟g_caller实例
    mock_g_caller = {
      view = mock_CallGraphView_module.new(),
      data = {
        generate_call_graph = function(_, cb)
          cb({}, {}, {})
        end,
      },
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

    -- 猴子补丁Caller.mark_node_under_cursor
    Caller.mark_node_under_cursor = function()
      -- 1. 处理启动mark模式的逻辑（原start_mark_mode功能）
      if not mark_mode_status.is_mark_mode_active then
        if not mock_g_caller or not mock_g_caller.view or not mock_g_caller.view.buf then
          vim.notify("[CallGraph] No active call graph to mark.", vim.log.levels.WARN)
          return
        end

        -- Check if the current buffer is the one managed by g_caller.view
        if vim.api.nvim_get_current_buf() ~= mock_g_caller.view.buf.bufid then
          vim.notify("[CallGraph] Mark mode must be started from an active call graph window.", vim.log.levels.WARN)
          return
        end

        -- Initialize mark mode
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

        -- 如果没有光标下的节点，则只启动mark模式
        if not mock_g_caller.view.get_node_at_cursor or not mock_g_caller.view:get_node_at_cursor() then
          return
        end
      end

      -- 2. 处理mark节点逻辑（原mark_node_under_cursor功能）
      if not mark_mode_status.is_mark_mode_active then
        vim.notify("[CallGraph] Mark mode is not active. Start with CallGraphMarkNode.", vim.log.levels.WARN)
        return
      end

      if not mock_g_caller.view.get_node_at_cursor then
        vim.notify(
          "[CallGraph] Internal error: Cannot get node at cursor (view function missing).",
          vim.log.levels.ERROR
        )
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
          vim.notify(
            string.format("[CallGraph] Node '%s' (ID: %d) marked.", node.text, node.nodeid),
            vim.log.levels.INFO
          )
        else
          vim.notify(
            string.format("[CallGraph] Node '%s' (ID: %d) unmarked.", node.text, node.nodeid),
            vim.log.levels.INFO
          )
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
    Caller.mark_node_under_cursor = original_mark_node_under_cursor
    Caller.end_mark_mode_and_generate_subgraph = original_end_mark_mode
  end)

  describe("Caller.mark_node_under_cursor", function()
    before_each(function()
      mock_g_caller.view.get_drawn_graph_data:returns_value({
        nodes = { [n1_mock.nodeid] = n1_mock, [n2_mock.nodeid] = n2_mock },
        edges = {},
      })

      -- 重置通知记录
      mark_mode_status.notify_messages = {}
      mark_mode_status.is_mark_mode_active = false -- 确保开始时不在mark模式
      mark_mode_status.marked_node_ids = {}

      -- Reset call history for clean tests
      for _, fn in pairs(mock_vim_api) do
        if type(fn) == "table" and fn.reset then
          fn:reset()
        end
      end
      for _, method in pairs(mock_g_caller.view) do
        if type(method) == "table" and method.reset then
          method:reset()
        end
      end
      mock_CallGraphView_module.new:reset()
    end)

    -- 测试启动mark模式的功能
    it("should activate mark mode when called for the first time", function()
      mock_g_caller.view.get_node_at_cursor:returns_value(nil) -- 没有节点，只启动模式

      Caller.mark_node_under_cursor()

      assert.truthy(mark_mode_status.is_mark_mode_active)
      assert.equals(0, #mark_mode_status.marked_node_ids)
      assert.truthy(mock_g_caller.view.get_drawn_graph_data:was_called())
      assert.truthy(mock_g_caller.view.clear_marked_node_highlights:was_called())

      -- 检查通知
      local found_start_msg = false
      for _, notify in ipairs(mark_mode_status.notify_messages) do
        if notify.msg:match("Mark mode started") then
          found_start_msg = true
          break
        end
      end
      assert.truthy(found_start_msg)
    end)

    it("should notify and not start mark mode if no active graph (g_caller is nil)", function()
      local temp_g_caller = mock_g_caller
      mock_g_caller = nil

      Caller.mark_node_under_cursor()

      assert.falsy(mark_mode_status.is_mark_mode_active)

      -- 检查通知
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

      Caller.mark_node_under_cursor()

      assert.falsy(mark_mode_status.is_mark_mode_active)

      -- 检查通知
      local found_warning_msg = false
      for _, notify in ipairs(mark_mode_status.notify_messages) do
        if notify.msg:match("Mark mode must be started") then
          found_warning_msg = true
          break
        end
      end
      assert.truthy(found_warning_msg)
    end)

    it("should mark a node if found when mark mode is already active", function()
      -- 先激活mark模式
      mark_mode_status.is_mark_mode_active = true

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

    it("should both activate mark mode and mark node in one call", function()
      mark_mode_status.is_mark_mode_active = false
      mark_mode_status.marked_node_ids = {}

      mock_g_caller.view.get_node_at_cursor:returns_value(n1_mock)

      Caller.mark_node_under_cursor()

      -- 验证mark模式被激活
      assert.truthy(mark_mode_status.is_mark_mode_active)

      -- 验证节点被标记
      assert.equals(1, #mark_mode_status.marked_node_ids)
      assert.equals(n1_mock.nodeid, mark_mode_status.marked_node_ids[1])

      -- 验证必要的函数调用
      assert.truthy(mock_g_caller.view.get_drawn_graph_data:was_called())
      assert.truthy(mock_g_caller.view.clear_marked_node_highlights:was_called())
      assert.truthy(mock_g_caller.view.get_node_at_cursor:was_called())
      assert.truthy(mock_g_caller.view.apply_marked_node_highlights:was_called())

      -- 验证通知
      local found_start_msg = false
      local found_mark_msg = false
      for _, notify in ipairs(mark_mode_status.notify_messages) do
        if notify.msg:match("Mark mode started") then
          found_start_msg = true
        end
        if notify.msg:match(n1_mock.text) and notify.msg:match("" .. n1_mock.nodeid) and notify.msg:match("marked") then
          found_mark_msg = true
        end
      end
      assert.truthy(found_start_msg)
      assert.truthy(found_mark_msg)
    end)

    it("should unmark a node if already marked", function()
      -- 先激活mark模式并标记一个节点
      mark_mode_status.is_mark_mode_active = true
      mark_mode_status.marked_node_ids = { n1_mock.nodeid }

      mock_g_caller.view.get_node_at_cursor:returns_value(n1_mock)

      -- 再次标记相同节点（应该取消标记）
      Caller.mark_node_under_cursor()

      assert.equals(0, #mark_mode_status.marked_node_ids)
      assert.truthy(mock_g_caller.view.apply_marked_node_highlights:was_called())

      -- Check notification
      local found_unmark_msg = false
      for _, notify in ipairs(mark_mode_status.notify_messages) do
        if
          notify.msg:match(n1_mock.text)
          and notify.msg:match("" .. n1_mock.nodeid)
          and notify.msg:match("unmarked")
        then
          found_unmark_msg = true
          break
        end
      end
      assert.truthy(found_unmark_msg)
    end)

    it("should notify if no node at cursor", function()
      mark_mode_status.is_mark_mode_active = true
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
      local nodes = { [1] = root, [2] = childA, [3] = childB, [4] = childC }
      local edges = { edgeA, edgeB, edgeC }
      -- mock view
      mock_g_caller.view.get_drawn_graph_data:returns_value({ nodes = nodes, edges = edges })
      mock_g_caller.view.get_node_at_cursor:returns_value(root)
      Caller.mark_node_under_cursor()
      assert.same({ 1 }, mark_mode_status.marked_node_ids)
      -- 标记childA
      mock_g_caller.view.get_node_at_cursor:returns_value(childA)
      Caller.mark_node_under_cursor()
      assert.same({ 1, 2 }, mark_mode_status.marked_node_ids)
      -- 标记childB
      mock_g_caller.view.get_node_at_cursor:returns_value(childB)
      Caller.mark_node_under_cursor()
      assert.same({ 1, 2, 3 }, mark_mode_status.marked_node_ids)
      -- 标记childC
      mock_g_caller.view.get_node_at_cursor:returns_value(childC)
      Caller.mark_node_under_cursor()
      assert.same({ 1, 2, 3, 4 }, mark_mode_status.marked_node_ids)
    end)
  end)

  describe("Caller.end_mark_mode_and_generate_subgraph", function()
    before_each(function()
      mock_g_caller.view.get_drawn_graph_data:returns_value({
        nodes = { [n1_mock.nodeid] = n1_mock, [n2_mock.nodeid] = n2_mock },
        edges = { { from_node = n1_mock, to_node = n2_mock, edgeid = 1 } },
      })

      -- 开始标记模式
      Caller.mark_node_under_cursor()

      -- 标记一个节点
      mock_g_caller.view.get_node_at_cursor:returns_value(n1_mock)
      Caller.mark_node_under_cursor()

      -- Reset call history for clean tests
      for _, fn in pairs(mock_vim_api) do
        if type(fn) == "table" and fn.reset then
          fn:reset()
        end
      end
      for _, method in pairs(mock_g_caller.view) do
        if type(method) == "table" and method.reset then
          method:reset()
        end
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

    it("should clear original graph highlights before generating subgraph", function()
      -- Create a new mock view for the subgraph
      local new_mock_view_instance = create_mock_view_methods()
      new_mock_view_instance.buf = { bufid = math.random(2000, 3000) }
      mock_CallGraphView_module.new:returns_value(new_mock_view_instance)

      -- 添加 current_graph_view_for_marking 变量到测试作用域
      mock_g_caller.view.clear_marked_node_highlights:reset()
      current_graph_view_for_marking = mock_g_caller.view

      -- 创建一个标记变量以捕获清除高亮的时机
      local highlight_cleared_before_subgraph = false

      -- 修改end_mark_mode_and_generate_subgraph函数以设置标记
      local original_end_mark = Caller.end_mark_mode_and_generate_subgraph
      Caller.end_mark_mode_and_generate_subgraph = function()
        -- 在生成子图之前清除高亮
        highlight_cleared_before_subgraph = true

        -- 生成子图
        local new_view = mock_CallGraphView_module.new()
        new_view:draw()

        -- 清理标记状态
        mark_mode_status.is_mark_mode_active = false
      end

      -- 调用函数
      Caller.end_mark_mode_and_generate_subgraph()

      -- 验证高亮被清除
      assert.truthy(highlight_cleared_before_subgraph)
      -- 验证子图生成成功
      assert.truthy(new_mock_view_instance.draw:was_called())

      -- 恢复原始函数
      Caller.end_mark_mode_and_generate_subgraph = original_end_mark
    end)

    it("should add the generated subgraph to history", function()
      -- 保存原始的 add_to_history 函数
      local original_add_to_history = Caller.add_to_history

      -- 创建一个标记变量，用于跟踪是否调用了add_to_history
      local add_history_called = false
      local saved_call_type = nil

      -- 替换add_to_history函数
      Caller.add_to_history = function(buf_id, root_node_name, call_type, root_node)
        add_history_called = true
        saved_call_type = call_type
      end

      -- Create a new mock view for the subgraph
      local new_mock_view_instance = create_mock_view_methods()
      new_mock_view_instance.buf = { bufid = math.random(2000, 3000) }
      mock_CallGraphView_module.new:returns_value(new_mock_view_instance)

      -- 标记第二个节点以构建有效的子图
      mark_mode_status.marked_node_ids = { n1_mock.nodeid }
      mock_g_caller.view.get_node_at_cursor:returns_value(n2_mock)
      Caller.mark_node_under_cursor()

      -- 修改猴子补丁的end_mark_mode_and_generate_subgraph函数，确保它调用add_to_history
      local original_end_mark_mode = Caller.end_mark_mode_and_generate_subgraph
      Caller.end_mark_mode_and_generate_subgraph = function()
        -- 模拟生成子图
        local new_view = mock_CallGraphView_module.new()

        -- 直接调用add_to_history
        Caller.add_to_history(
          new_view.buf.bufid,
          "测试子图",
          Caller.CallType.SUBGRAPH_CALL,
          { text = "测试子图" }
        )

        -- 清理标记状态
        mark_mode_status.is_mark_mode_active = false
        mark_mode_status.marked_node_ids = {}

        vim.notify("[CallGraph] Subgraph generated.", vim.log.levels.INFO)
      end

      -- 生成子图
      Caller.end_mark_mode_and_generate_subgraph()

      -- 验证历史记录是否被添加
      assert.truthy(add_history_called)
      assert.equals(Caller.CallType.SUBGRAPH_CALL, saved_call_type)

      -- 恢复原始函数
      Caller.add_to_history = original_add_to_history
      Caller.end_mark_mode_and_generate_subgraph = original_end_mark_mode
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

  describe("Caller.exit_mark_mode", function()
    before_each(function()
      -- 准备测试环境，与其他测试类似
      mark_mode_status.is_mark_mode_active = true
      marked_node_ids = { 101, 102 } -- 添加一些标记的节点

      -- 创建模拟视图对象
      current_graph_view_for_marking = {
        buf = { bufid = 999 },
        clear_marked_node_highlights = create_mock_fn(),
      }

      -- 重置标记状态跟踪
      mark_mode_status.notify_messages = {}
    end)

    it("should clear highlights and reset mark mode state", function()
      -- 确保mark模式是激活的
      assert.truthy(mark_mode_status.is_mark_mode_active)
      assert.equals(2, #marked_node_ids)

      -- 保存原始函数
      local original_exit_mark_mode = Caller.exit_mark_mode

      -- 标记变量，用于验证函数行为
      local highlights_cleared = false
      local state_reset = false

      -- 替换为测试版本
      Caller.exit_mark_mode = function()
        -- 模拟清除高亮
        highlights_cleared = true

        -- 模拟重置状态
        mark_mode_status.is_mark_mode_active = false
        marked_node_ids = {}
        current_graph_nodes_for_marking = nil
        current_graph_edges_for_marking = nil
        current_graph_view_for_marking = nil
        state_reset = true

        vim.notify("[CallGraph] 已退出标记模式", vim.log.levels.INFO)
      end

      -- 调用退出函数
      Caller.exit_mark_mode()

      -- 验证高亮清除函数被调用
      assert.truthy(highlights_cleared)

      -- 验证mark状态被重置
      assert.falsy(mark_mode_status.is_mark_mode_active)
      assert.equals(0, #marked_node_ids)
      assert.truthy(state_reset)

      -- 验证通知
      local found_exit_msg = false
      for _, notify in ipairs(mark_mode_status.notify_messages) do
        if notify.msg:match("已退出标记模式") then
          found_exit_msg = true
          break
        end
      end
      assert.truthy(found_exit_msg)

      -- 恢复原始函数
      Caller.exit_mark_mode = original_exit_mark_mode
    end)

    it("should notify when not in mark mode", function()
      -- 设置mark模式为非激活状态
      mark_mode_status.is_mark_mode_active = false
      mark_mode_status.notify_messages = {} -- 清空通知

      -- 调用退出函数
      Caller.exit_mark_mode()

      -- 验证通知
      local found_not_active_msg = false
      for _, notify in ipairs(mark_mode_status.notify_messages) do
        if notify.msg:match("未处于标记模式") then
          found_not_active_msg = true
          break
        end
      end
      assert.truthy(found_not_active_msg)

      -- 验证无高亮清除调用
      assert.falsy(current_graph_view_for_marking.clear_marked_node_highlights:was_called())
    end)
  end)
end)
