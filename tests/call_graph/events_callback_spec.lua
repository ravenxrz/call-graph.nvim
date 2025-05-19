local CallGraphView = require("call_graph.view.graph_view")
local Events = require("call_graph.utils.events")
local Edge = require("call_graph.class.edge")

-- 模拟日志
local mock_Log = {
  debug = function(...) end,
  info = function(...) end,
  error = function(...) end,
  warn = function(...) end,
}
package.loaded["call_graph.utils.log"] = mock_Log

-- 模拟vim API
local original_vim_api = vim.api
vim.api = vim.api or {}
vim.api.nvim_create_namespace = vim.api.nvim_create_namespace or function(name)
  return 1
end
vim.api.nvim_buf_is_valid = vim.api.nvim_buf_is_valid or function(bufid)
  return true
end
vim.api.nvim_win_get_cursor = vim.api.nvim_win_get_cursor or function(win)
  return { 1, 0 }
end
vim.api.nvim_buf_get_name = vim.api.nvim_buf_get_name or function(bufid)
  return "test_buffer"
end
vim.api.nvim_get_current_buf = vim.api.nvim_get_current_buf or function()
  return 1
end
vim.api.nvim_create_buf = vim.api.nvim_create_buf or function()
  return 2
end
vim.api.nvim_buf_set_lines = vim.api.nvim_buf_set_lines or function() end
vim.api.nvim_win_set_cursor = vim.api.nvim_win_set_cursor or function() end
vim.api.nvim_open_win = vim.api.nvim_open_win or function()
  return 3
end
vim.api.nvim_win_is_valid = vim.api.nvim_win_is_valid or function()
  return false
end
vim.api.nvim_create_autocmd = vim.api.nvim_create_autocmd or function() end
vim.cmd = vim.cmd or function() end
vim.uri_to_fname = vim.uri_to_fname
  or function(uri)
    -- 从 file:///path 格式中提取路径部分
    return uri:gsub("file://", "")
  end
vim.notify = vim.notify or function() end
vim.ui = vim.ui or {}
vim.ui.select = vim.ui.select
  or function(items, opts, on_choice)
    if #items > 0 then
      on_choice(items[1], 1)
    end
  end

local mock_Drawer = {
  new = function(...)
    return {
      set_modifiable = function(...) end,
      draw = function(...) end,
    }
  end,
}
package.loaded["call_graph.view.graph_drawer"] = mock_Drawer

-- 备份原始函数
local original_regist_press_cb = Events.regist_press_cb
local original_regist_cursor_hold_cb = Events.regist_cursor_hold_cb

describe("Event callbacks", function()
  local view
  local press_cb_calls
  local keymap_bindings
  local cursor_hold_cb_calls

  -- 测试数据
  local node1 = {
    row = 0,
    col = 0,
    text = "RootNode",
    level = 1,
    incoming_edges = {},
    outcoming_edges = {},
    nodeid = 1,
    usr_data = {
      attr = {
        pos_params = {
          textDocument = { uri = "file:///test/file1.lua" },
          position = { line = 10, character = 5 },
        },
      },
    },
  }
  local node2 = {
    row = 1, -- 不同的行
    col = 0,
    text = "ChildNode",
    level = 2,
    incoming_edges = {},
    outcoming_edges = {},
    nodeid = 2,
    usr_data = {
      attr = {
        pos_params = {
          textDocument = { uri = "file:///test/file2.lua" },
          position = { line = 20, character = 15 },
        },
      },
    },
  }

  -- 创建边
  local edge = Edge:new(node1, node2, nil, {
    pos_params = {
      textDocument = { uri = "file:///test/edge.lua" },
      position = { line = 30, character = 25 },
    },
  })

  -- 设置边的关系
  table.insert(node1.outcoming_edges, edge)
  table.insert(node2.incoming_edges, edge)

  -- 为测试创建节点和边的集合
  local nodes = {
    [node1.nodeid] = node1,
    [node2.nodeid] = node2,
  }
  local edges = { edge }

  -- 设置边的子边
  edge.sub_edges = {
    {
      start_row = 0,
      start_col = 0,
      end_row = 1,
      end_col = 10,
      to_string = function()
        return "SubEdge"
      end,
    },
  }

  -- 跟踪哪些文件被打开
  local opened_files = {}
  local jumped_to_positions = {}

  before_each(function()
    -- 重置状态
    press_cb_calls = {}
    keymap_bindings = {}
    cursor_hold_cb_calls = {}
    opened_files = {}
    jumped_to_positions = {}

    -- 模拟vim API函数
    vim.api.nvim_buf_is_valid = function(bufid)
      return true
    end
    vim.api.nvim_buf_get_option = function(bufid, option)
      if option == "modifiable" then
        return true -- 允许修改缓冲区
      end
      return false
    end
    vim.api.nvim_buf_set_option = function(bufid, option, value) end
    vim.api.nvim_buf_set_lines = function(bufid, start, end_line, strict, lines) end
    vim.api.nvim_buf_line_count = function(bufid)
      return 0
    end

    -- 模拟keymap.set
    vim.keymap = vim.keymap or {}
    vim.keymap.set = function(mode, key, callback, opts)
      keymap_bindings[key] = {
        callback = callback,
        opts = opts,
      }
    end

    -- 模拟Events模块
    Events.regist_press_cb = function(bufid, cb, cb_ctx, keymap)
      table.insert(press_cb_calls, {
        bufid = bufid,
        cb = cb,
        ctx = cb_ctx,
        keymap = keymap,
      })
    end

    Events.regist_cursor_hold_cb = function(bufid, cb, cb_ctx)
      table.insert(cursor_hold_cb_calls, {
        bufid = bufid,
        cb = cb,
        ctx = cb_ctx,
      })
    end

    -- 模拟vim.cmd
    vim.cmd = function(cmd)
      if type(cmd) == "string" and cmd:match("^edit") then
        local file = cmd:match("edit%s+(.+)")
        table.insert(opened_files, file)
      end
    end

    -- 模拟vim.api.nvim_win_set_cursor
    vim.api.nvim_win_set_cursor = function(win, pos)
      table.insert(jumped_to_positions, {
        win = win,
        line = pos[1],
        col = pos[2],
      })
    end

    -- 修改uri_to_fname函数
    vim.uri_to_fname = function(uri)
      return uri:gsub("^file://", "")
    end

    -- 创建视图
    view = CallGraphView:new(200, true)
    view.buf.bufid = 1

    -- 模拟draw方法（绕过缓冲区逻辑）
    local original_draw = CallGraphView.draw
    CallGraphView.draw = function(self, root_node, traverse_by_incoming)
      -- 从root_node构建节点和边缓存
      local n = {}
      local e = {}

      if root_node then
        n[root_node.nodeid] = root_node

        -- 收集边
        local traverse_edges = traverse_by_incoming and root_node.incoming_edges or root_node.outcoming_edges
        for _, edge in ipairs(traverse_edges) do
          table.insert(e, edge)
        end

        -- 添加测试节点
        for nodeid, node in pairs(nodes) do
          n[nodeid] = node
        end

        -- 添加测试边
        for _, edge in ipairs(edges) do
          table.insert(e, edge)
        end
      end

      self.nodes_cache = n
      self.edges_cache = e

      -- 直接设置self.buf.graph以避免实际创建缓冲区
      self.buf.graph = {
        set_modifiable = function() end,
        draw = function() end,
      }

      -- 重要：调用setup_buf以注册事件回调
      self:setup_buf(n, e)

      return self.buf.bufid
    end
  end)

  after_each(function()
    -- 恢复原始函数
    Events.regist_press_cb = original_regist_press_cb
    Events.regist_cursor_hold_cb = original_regist_cursor_hold_cb
  end)

  it("should register events when drawing graph", function()
    view:draw(node1, false)

    -- 检查是否注册了所有事件
    assert.equal(2, #press_cb_calls) -- K和gd
    assert.equal(1, #cursor_hold_cb_calls) -- cursor hold

    -- 检查gd键绑定
    local gd_call = nil
    for _, call in ipairs(press_cb_calls) do
      if call.keymap == "gd" then
        gd_call = call
        break
      end
    end
    assert.is_not_nil(gd_call)
    assert.equal(1, gd_call.bufid)

    -- 不直接比较nodes和edges对象，因为收集逻辑可能生成不同的数组结构
    -- 但应该包含相同的节点信息
    local ctx_nodes = gd_call.ctx.nodes
    assert.is_not_nil(ctx_nodes[1]) -- 应该包含节点1
    assert.is_not_nil(ctx_nodes[2]) -- 应该包含节点2
    assert.equal("RootNode", ctx_nodes[1].text)
    assert.equal("ChildNode", ctx_nodes[2].text)

    -- 检查K键绑定
    local k_call = nil
    for _, call in ipairs(press_cb_calls) do
      if call.keymap == "K" then
        k_call = call
        break
      end
    end
    assert.is_not_nil(k_call)
    assert.equal(1, k_call.bufid)

    -- 同样检查nodes包含正确的节点
    ctx_nodes = k_call.ctx.nodes
    assert.is_not_nil(ctx_nodes[1])
    assert.is_not_nil(ctx_nodes[2])
  end)

  -- 测试gd回调
  it("should jump to position when using gd on a node", function()
    -- 修改node1的uri使其不包含file://前缀
    local original_uri = node1.usr_data.attr.pos_params.textDocument.uri
    node1.usr_data.attr.pos_params.textDocument.uri = original_uri:gsub("^file://", "")

    -- 在view上绘制图表
    view:draw(node1, false)

    -- 找到gd回调函数
    local gd_call = nil
    for _, call in ipairs(press_cb_calls) do
      if call.keymap == "gd" then
        gd_call = call
        break
      end
    end

    -- 模拟被调用时的上下文
    vim.api.nvim_win_get_cursor = function()
      return { 1, 5 }
    end -- 第1行，第5列

    -- 手动调用回调函数
    gd_call.cb(0, 5, gd_call.ctx) -- row=0 (第1行-1)，col=5

    -- 验证是否打开了正确的文件
    assert.equal(1, #opened_files)
    assert.equal("/test/file1.lua", opened_files[1])

    -- 验证是否跳转到正确的位置
    assert.equal(1, #jumped_to_positions)
    assert.equal(11, jumped_to_positions[1].line) -- line是1-based
    assert.equal(5, jumped_to_positions[1].col) -- col

    -- 恢复原始uri
    node1.usr_data.attr.pos_params.textDocument.uri = original_uri
  end)

  -- 测试不同行的gd跳转
  it("should jump to position when using gd on a different node", function()
    -- 修改node2的uri使其不包含file://前缀
    local original_uri = node2.usr_data.attr.pos_params.textDocument.uri
    node2.usr_data.attr.pos_params.textDocument.uri = original_uri:gsub("^file://", "")

    -- 在view上绘制图表
    view:draw(node1, false)

    local gd_call = nil
    for _, call in ipairs(press_cb_calls) do
      if call.keymap == "gd" then
        gd_call = call
        break
      end
    end

    -- 模拟光标在第2行(index=1)
    vim.api.nvim_win_get_cursor = function()
      return { 2, 5 }
    end

    -- 手动调用回调函数
    gd_call.cb(1, 5, gd_call.ctx) -- row=1 (第2行-1)，col=5

    -- 验证是否打开了正确的文件
    assert.equal(1, #opened_files)
    assert.equal("/test/file2.lua", opened_files[1])

    -- 验证是否跳转到正确的位置
    assert.equal(1, #jumped_to_positions)
    assert.equal(21, jumped_to_positions[1].line) -- line + 1
    assert.equal(15, jumped_to_positions[1].col)

    -- 恢复原始uri
    node2.usr_data.attr.pos_params.textDocument.uri = original_uri
  end)

  -- 测试K键功能
  it("should show node info when using K on a node", function()
    -- 修改node1的uri使其不包含file://前缀
    local original_uri = node1.usr_data.attr.pos_params.textDocument.uri
    node1.usr_data.attr.pos_params.textDocument.uri = original_uri:gsub("^file://", "")

    -- 在view上绘制图表
    view:draw(node1, false)

    -- 追踪创建的悬浮窗口
    local created_floating_windows = {}
    local created_floating_buffers = {}
    local floating_window_content = {}

    -- 模拟创建缓冲区和窗口的函数
    vim.api.nvim_create_buf = function(listed, scratch)
      local buf_id = 100
      table.insert(created_floating_buffers, buf_id)
      floating_window_content[buf_id] = {}
      return buf_id
    end

    vim.api.nvim_buf_set_lines = function(bufnr, start, end_line, strict, lines)
      if floating_window_content[bufnr] then
        floating_window_content[bufnr] = lines
      end
    end

    vim.api.nvim_open_win = function(bufnr, enter, config)
      local win_id = 200
      table.insert(created_floating_windows, {
        buf_id = bufnr,
        win_id = win_id,
        config = config,
      })
      return win_id
    end

    -- 找到K回调函数
    local k_call = nil
    for _, call in ipairs(press_cb_calls) do
      if call.keymap == "K" then
        k_call = call
        break
      end
    end

    -- 模拟被调用时的上下文 - 鼠标在第1行 (0-based是0)
    vim.api.nvim_win_get_cursor = function()
      return { 1, 5 }
    end

    -- 手动调用回调函数
    k_call.cb(0, 5, k_call.ctx)

    -- 验证是否创建了悬浮窗口
    assert.equal(1, #created_floating_buffers)
    assert.equal(1, #created_floating_windows)

    -- 检查悬浮窗口内容是否包含正确的文件路径和位置
    local buf_id = created_floating_buffers[1]
    assert.is_not_nil(floating_window_content[buf_id])

    -- 检查内容中是否包含文件路径和位置信息
    local content_text = table.concat(floating_window_content[buf_id], "\n")
    assert.is_not_nil(string.find(content_text, "/test/file1.lua"))
    assert.is_not_nil(string.find(content_text, "11")) -- line + 1
    assert.is_not_nil(string.find(content_text, "5")) -- character

    -- 恢复原始uri
    node1.usr_data.attr.pos_params.textDocument.uri = original_uri
  end)

  -- 测试在不同节点上使用K
  it("should show node info when using K on a different node", function()
    -- 修改node2的uri使其不包含file://前缀
    local original_uri = node2.usr_data.attr.pos_params.textDocument.uri
    node2.usr_data.attr.pos_params.textDocument.uri = original_uri:gsub("^file://", "")

    -- 在view上绘制图表
    view:draw(node1, false)

    -- 追踪创建的悬浮窗口
    local created_floating_windows = {}
    local created_floating_buffers = {}
    local floating_window_content = {}

    -- 模拟创建缓冲区和窗口的函数
    vim.api.nvim_create_buf = function(listed, scratch)
      local buf_id = 100
      table.insert(created_floating_buffers, buf_id)
      floating_window_content[buf_id] = {}
      return buf_id
    end

    vim.api.nvim_buf_set_lines = function(bufnr, start, end_line, strict, lines)
      if floating_window_content[bufnr] then
        floating_window_content[bufnr] = lines
      end
    end

    vim.api.nvim_open_win = function(bufnr, enter, config)
      local win_id = 200
      table.insert(created_floating_windows, {
        buf_id = bufnr,
        win_id = win_id,
        config = config,
      })
      return win_id
    end

    -- 找到K回调函数
    local k_call = nil
    for _, call in ipairs(press_cb_calls) do
      if call.keymap == "K" then
        k_call = call
        break
      end
    end

    -- 模拟被调用时的上下文 - 鼠标在第2行 (0-based是1)
    vim.api.nvim_win_get_cursor = function()
      return { 2, 5 }
    end

    -- 手动调用回调函数
    k_call.cb(1, 5, k_call.ctx)

    -- 验证是否创建了悬浮窗口
    assert.equal(1, #created_floating_buffers)
    assert.equal(1, #created_floating_windows)

    -- 检查悬浮窗口内容是否包含正确的文件路径和位置
    local buf_id = created_floating_buffers[1]
    assert.is_not_nil(floating_window_content[buf_id])

    -- 检查内容中是否包含文件路径和位置信息
    local content_text = table.concat(floating_window_content[buf_id], "\n")
    assert.is_not_nil(string.find(content_text, "/test/file2.lua", 1, true))
    assert.is_not_nil(string.find(content_text, "21")) -- line + 1
    assert.is_not_nil(string.find(content_text, "15")) -- character

    -- 恢复原始uri
    node2.usr_data.attr.pos_params.textDocument.uri = original_uri
  end)
end)
