local Caller = require("call_graph.caller")
local base_mock = require("tests.base_mock")

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

  describe("基本持久化功能", function()
    it("添加调用图时应更新历史记录", function()
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
  
  describe("图重新生成功能", function()
    it("应能从历史记录重新生成调用图", function()
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
    
    it("应处理无效的历史记录条目", function()
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
  
  describe("历史记录管理", function()
    it("应当尊重最大历史记录大小设置", function()
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
end) 