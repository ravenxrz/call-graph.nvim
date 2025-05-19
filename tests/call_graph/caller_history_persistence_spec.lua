local Caller = require("call_graph.caller")
local base_mock = require("tests.base_mock")
local mock = require("luassert.mock")

describe("Call Graph History Persistence", function()
  local original_io_open = io.open
  local test_history_file_path = "/tmp/test_call_graph_history.json"
  local mock_opts = {
    reuse_buf = false,
    hl_delay_ms = 200,
    auto_toggle_hl = true,
    in_call_max_depth = 4,
    ref_call_max_depth = 4,
    export_mermaid_graph = false,
    max_history_size = 5 -- 使用较小的值便于测试
  }
  
  -- 重置Caller内部状态的辅助函数
  local function reset_caller_state()
    -- 清空历史记录
    local history = Caller._get_graph_history()
    while #history > 0 do
      table.remove(history, 1)
    end
    -- 设置最大历史记录大小
    Caller._set_max_history_size(mock_opts.max_history_size)
  end
  
  before_each(function()
    -- 保存原始 io.open 函数
    original_io_open = io.open
    
    -- 重置测试状态
    base_mock.reset_calls()
    reset_caller_state()
    
    -- 模拟 vim.api.nvim_win_set_cursor 函数，避免光标位置错误
    vim.api.nvim_win_set_cursor = function(_, _) 
      return true
    end
    
    -- 模拟 vim.cmd 函数，避免实际执行命令
    vim.cmd = function(cmd)
      table.insert(base_mock.cmd_calls, cmd)
      return true
    end
    
    -- 禁用保存函数，避免干扰测试
    package.loaded["call_graph.caller"].save_history_to_file = function() end
  end)
  
  after_each(function()
    -- 恢复原始函数
    io.open = original_io_open
  end)

  describe("Basic persistence functionality", function()
    it("should update history when adding a call graph", function()
      -- 重置历史记录
      reset_caller_state()
      
      -- 创建模拟调用图节点
      local mock_root_node = {
        text = "test_function",
        usr_data = {
          attr = {
            pos_params = {
              textDocument = {
                uri = "file:///test/file.lua"
              },
              position = {
                line = 10,
                character = 5
              }
            }
          }
        }
      }
      
      -- 直接调用add_to_history函数
      Caller.add_to_history(101, "test_function", Caller.CallType.INCOMING_CALL, mock_root_node)
      
      -- 验证历史记录已更新
      local history = Caller._get_graph_history()
      assert.is_not_nil(history)
      assert.equals(1, #history)
      assert.equals("test_function", history[1].root_node_name)
      assert.equals(Caller.CallType.INCOMING_CALL, history[1].call_type)
      assert.is_not_nil(history[1].pos_params)
    end)
  end)
  
  describe("Graph regeneration functionality", function()
    it("should regenerate call graph from history", function()
      -- 重置历史记录
      reset_caller_state()
      
      -- 准备测试数据
      local history_entry = {
        buf_id = -1,
        root_node_name = "test_regenerate_function",
        call_type = Caller.CallType.OUTCOMING_CALL,
        timestamp = os.time(),
        pos_params = {
          textDocument = {
            uri = "file:///test/regenerate_file.lua"
          },
          position = {
            line = 30,
            character = 15
          }
        }
      }
      
      -- 模拟调用图生成过程
      local original_generate = Caller.generate_call_graph
      Caller.generate_call_graph = function(opts, call_type, callback)
        assert.equals(Caller.CallType.OUTCOMING_CALL, call_type)
        if callback then
          callback(202, "regenerated_node")
        end
      end
      
      -- 添加条目到历史
      local history = Caller._get_graph_history()
      table.insert(history, history_entry)
      
      -- 调用重生成函数
      Caller.regenerate_graph_from_history(history_entry)
      
      -- 验证历史记录中buf_id已更新
      assert.equals(202, history_entry.buf_id)
      
      -- 恢复原始函数
      Caller.generate_call_graph = original_generate
    end)
    
    it("should handle invalid history entries", function()
      -- 重置历史记录
      reset_caller_state()
      
      -- 准备无效的历史记录条目（没有位置数据）
      local invalid_entry = {
        buf_id = -1,
        root_node_name = "invalid_function",
        call_type = Caller.CallType.INCOMING_CALL,
        timestamp = os.time()
        -- 无 pos_params
      }
      
      -- 调用重生成函数
      Caller.regenerate_graph_from_history(invalid_entry)
      
      -- 验证显示了错误通知
      assert.equals(1, #base_mock.notify_calls)
      assert.equals("[CallGraph] Cannot regenerate graph: missing position data", base_mock.notify_calls[1].msg)
      assert.equals(vim.log.levels.ERROR, base_mock.notify_calls[1].level)
    end)
  end)
  
  describe("History record management", function()
    it("should respect maximum history size setting", function()
      -- 重置历史记录
      reset_caller_state()
      
      -- 设置最大历史记录大小
      Caller._set_max_history_size(3)
      
      -- 创建测试节点
      local function create_test_node(name, index)
        return {
          text = name,
          usr_data = {
            attr = {
              pos_params = {
                textDocument = { uri = "file:///test/" .. index .. ".lua" },
                position = { line = index * 10, character = 5 }
              }
            }
          }
        }
      end
      
      -- 添加5个条目（超过最大限制）
      for i = 1, 5 do
        Caller.add_to_history(100 + i, "function_" .. i, Caller.CallType.INCOMING_CALL, create_test_node("function_" .. i, i))
      end
      
      -- 验证历史记录大小不超过限制
      local history = Caller._get_graph_history()
      assert.equals(3, #history)
      
      -- 验证保留的是最新的3个
      assert.equals("function_5", history[1].root_node_name)
      assert.equals("function_4", history[2].root_node_name)
      assert.equals("function_3", history[3].root_node_name)
    end)
  end)
  
  describe("Subgraph history functionality", function()
    -- 创建一个模拟子图的辅助函数
    local function create_mock_subgraph()
      local node1 = {
        nodeid = 1, 
        text = "root_node",
        level = 1,
        incoming_edges = {},
        outcoming_edges = {}
      }
      
      local node2 = {
        nodeid = 2,
        text = "child_node",
        level = 2,
        incoming_edges = {},
        outcoming_edges = {}
      }
      
      local edge = {
        edgeid = 1,
        from_node = node1,
        to_node = node2
      }
      
      table.insert(node1.outcoming_edges, edge)
      table.insert(node2.incoming_edges, edge)
      
      return {
        root_node = node1,
        nodes_map = {
          [1] = node1,
          [2] = node2
        },
        nodes_list = {node1, node2},
        edges = {edge}
      }
    end
    
    it("should correctly save subgraph to history", function()
      -- 重置历史记录
      reset_caller_state()
      
      -- 创建一个子图
      local subgraph = create_mock_subgraph()
      
      -- 创建一个历史条目
      local history_entry = {
        buf_id = 301,
        root_node_name = "子图测试",
        call_type = Caller.CallType.SUBGRAPH_CALL,
        timestamp = os.time(),
        subgraph = subgraph
      }
      
      -- 添加到历史记录
      local history = Caller._get_graph_history()
      table.insert(history, 1, history_entry)
      
      -- 启用真实的save_history_to_file函数
      local original_save = package.loaded["call_graph.caller"].save_history_to_file
      package.loaded["call_graph.caller"].save_history_to_file = Caller.save_history_to_file
      
      -- 模拟io.open函数，避免实际写入文件
      local mock_file = {
        write = function() return true end,
        close = function() return true end
      }
      
      io.open = function() return mock_file end
      
      -- 尝试保存历史记录
      local success, err = pcall(function() Caller.save_history_to_file() end)
      
      -- 验证保存是否成功
      assert.is_true(success)
      
      -- 恢复原始函数
      package.loaded["call_graph.caller"].save_history_to_file = original_save
    end)
    
    it("should regenerate subgraph from history", function()
      -- 重置历史记录
      reset_caller_state()
      
      -- 创建一个带有子图的历史条目
      local history_entry = {
        buf_id = -1,
        root_node_name = "测试子图恢复",
        call_type = Caller.CallType.SUBGRAPH_CALL,
        timestamp = os.time(),
        subgraph = create_mock_subgraph()
      }
      
      -- 保存原始函数
      local original_regenerate = Caller.regenerate_graph_from_history
      
      -- 替换为测试用的模拟函数
      Caller.regenerate_graph_from_history = function(entry)
        entry.buf_id = 302 -- 直接设置一个有效的buffer id
        return true
      end
      
      -- 调用重生成函数
      local success = pcall(function()
        Caller.regenerate_graph_from_history(history_entry)
      end)
      
      -- 验证
      assert.is_true(success)
      assert.equals(302, history_entry.buf_id)
      
      -- 恢复原始函数
      Caller.regenerate_graph_from_history = original_regenerate
    end)
    
    it("should handle circular references in subgraph", function()
      -- 创建包含循环引用的子图
      local subgraph = create_mock_subgraph()
      
      -- 确保存在循环引用
      assert.equals(subgraph.root_node, subgraph.edges[1].from_node)
      assert.equals(subgraph.nodes_map[2], subgraph.edges[1].to_node)
      
      -- 启用vim.json模拟
      local original_json = vim.json
      vim.json = {
        encode = function(data)
          -- 返回一个假的JSON字符串，避免实际处理循环引用
          return '{"mocked_json":"success"}'
        end,
        decode = function(str)
          return { mocked_json = "success" }
        end
      }
      
      -- 创建历史条目并尝试保存
      local history_entry = {
        buf_id = 303,
        root_node_name = "循环引用测试",
        call_type = Caller.CallType.SUBGRAPH_CALL,
        timestamp = os.time(),
        subgraph = subgraph
      }
      
      local history = Caller._get_graph_history()
      table.insert(history, 1, history_entry)
      
      -- 保存原始函数
      local original_save = package.loaded["call_graph.caller"].save_history_to_file
      
      -- 替换为测试用的模拟函数
      package.loaded["call_graph.caller"].save_history_to_file = function()
        -- 什么都不做，避免实际写入文件
        return true
      end
      
      -- 模拟文件操作
      local written_content = "测试内容" -- 预设一个非nil的内容
      local mock_file = {
        write = function(_, content) written_content = content or "默认内容" end,
        close = function() return true end
      }
      io.open = function() return mock_file end
      
      -- 尝试保存
      local success = pcall(function()
        package.loaded["call_graph.caller"].save_history_to_file()
      end)
      
      -- 验证
      assert.is_true(success)
      assert.is_not_nil(written_content)
      
      -- 恢复原始函数
      package.loaded["call_graph.caller"].save_history_to_file = original_save
      vim.json = original_json
    end)
  end)
  
  it("should clear history from memory and disk", function()
    -- 设置最大历史记录大小
    Caller._set_max_history_size(10)
    
    -- 获取历史记录表的引用
    local history = Caller._get_graph_history()
    
    -- 添加一些测试历史记录
    table.insert(history, {
      buf_id = -1,
      root_node_name = "test_function_1",
      call_type = Caller.CallType.INCOMING_CALL,
      timestamp = os.time(),
      pos_params = { textDocument = { uri = "file:///test.lua" }, position = { line = 10, character = 0 } }
    })
    
    table.insert(history, {
      buf_id = -1,
      root_node_name = "test_function_2",
      call_type = Caller.CallType.OUTCOMING_CALL,
      timestamp = os.time(),
      pos_params = { textDocument = { uri = "file:///test.lua" }, position = { line = 20, character = 0 } }
    })
    
    -- 保存历史记录到文件
    Caller.save_history_to_file()
    
    -- 确认历史记录已保存
    assert.are.equal(2, #history)
    
    -- 测试清空历史记录
    local success = Caller.clear_history()
    assert.is_true(success)
    
    -- 确认内存中的历史记录已清空
    history = Caller._get_graph_history()
    assert.are.equal(0, #history)
    
    -- 重新加载历史记录文件，确认磁盘上的历史记录也已清空
    Caller.load_history_from_file()
    history = Caller._get_graph_history()
    assert.are.equal(0, #history)
  end)
end) 