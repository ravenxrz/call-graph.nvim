local mock = require("tests.base_mock")
local Caller = require("call_graph.caller")
local Edge = require("call_graph.class.edge")
local SubEdge = require("call_graph.class.subedge")
local GraphNode = require("call_graph.class.graph_node")

-- 创建一个带有序列化与反序列化处理的测试套件
describe("Subgraph serialization and restoration", function()
  local mock_fs = {}
  local history_file_path = "/Users/leo/Projects/call-graph.nvim/.call_graph_history.json"
  local original_history_path_func
  local test_history_data = nil
  
  -- 初始化测试环境
  before_each(function()
    -- 备份原始函数
    original_history_path_func = Caller._get_history_file_path_func()
    
    -- Mock文件系统操作
    mock_fs.files = {}
    -- 确保测试历史文件路径存在，注意这个路径要和后面的history_file_path()函数返回值一致
    mock_fs.files[history_file_path] = ""
    
    -- 重写io.open用于测试
    _G.io.open = function(path, mode)
      print("io.open被调用，路径: " .. path .. ", 模式: " .. mode)
      if mode == "w" then
        mock_fs.files[path] = ""
        return {
          write = function(_, content)
            print("写入文件 " .. path .. "，内容长度: " .. #content)
            mock_fs.files[path] = content
          end,
          close = function() 
            print("关闭文件: " .. path)
          end
        }
      elseif mode == "r" then
        if mock_fs.files[path] then
          print("读取文件: " .. path .. ", 文件存在")
          return {
            read = function(_)
              return mock_fs.files[path]
            end,
            close = function() end
          }
        else
          print("读取文件: " .. path .. ", 文件不存在")
          return nil
        end
      end
    end
    
    -- 修改历史文件路径函数，返回固定的测试文件路径
    Caller._get_history_file_path_func = function()
      return function()
        print("获取历史文件路径: " .. history_file_path)
        return history_file_path
      end
    end
    
    -- 确保测试开始前清空历史
    Caller._set_max_history_size(20)
    local history = Caller._get_graph_history()
    while #history > 0 do
      table.remove(history)
    end
  end)
  
  -- 清理测试环境
  after_each(function()
    -- 恢复原始函数
    Caller._get_history_file_path_func = original_history_path_func
    -- 重置文件模拟
    mock_fs.files = {}
    -- 清空历史
    local history = Caller._get_graph_history()
    while #history > 0 do
      table.remove(history)
    end
  end)
  
  -- 在每个测试用例前重置测试数据
  before_each(function()
    -- 清空歷史
    local history = Caller._get_graph_history()
    while #history > 0 do
      table.remove(history)
    end
    -- 清空模拟文件系统
    mock_fs.files = {}
  end)
  
  -- 创建一个测试图结构（带有节点、边和子边）
  local function create_test_graph()
    -- 创建节点
    local node1 = GraphNode:new("function1", {
      attr = { 
        pos_params = {
          textDocument = { uri = "file:///test/source1.lua" },
          position = { line = 10, character = 5 }
        }
      }
    })
    
    local node2 = GraphNode:new("function2", {
      attr = { 
        pos_params = {
          textDocument = { uri = "file:///test/source2.lua" },
          position = { line = 20, character = 15 }
        }
      }
    })
    
    local node3 = GraphNode:new("function3", {
      attr = { 
        pos_params = {
          textDocument = { uri = "file:///test/source3.lua" },
          position = { line = 30, character = 25 }
        }
      }
    })
    
    -- 创建子边
    local sub_edge1 = SubEdge:new(0, 10, 1, 20)
    local sub_edge2 = SubEdge:new(1, 15, 2, 25)
    
    -- 创建边并关联子边
    local edge1 = Edge:new(node1, node2, {
      textDocument = { uri = "file:///test/edge1.lua" },
      position = { line = 15, character = 10 }
    }, {sub_edge1})
    
    local edge2 = Edge:new(node2, node3, {
      textDocument = { uri = "file:///test/edge2.lua" },
      position = { line = 25, character = 20 }
    }, {sub_edge2})
    
    -- 设置节点之间的连接关系
    table.insert(node1.outcoming_edges, edge1)
    table.insert(node2.incoming_edges, edge1)
    table.insert(node2.outcoming_edges, edge2)
    table.insert(node3.incoming_edges, edge2)
    
    -- 返回完整图结构
    return {
      nodes_map = {
        [node1.nodeid] = node1,
        [node2.nodeid] = node2,
        [node3.nodeid] = node3
      },
      edges = {edge1, edge2},
      root_node = node1
    }
  end
  
  -- 验证两个图结构是否相等
  local function assert_graphs_equal(graph1, graph2)
    -- 检查节点数量是否相同
    assert.are.equal(vim.tbl_count(graph1.nodes_map), vim.tbl_count(graph2.nodes_map))
    
    -- 检查边数量是否相同
    assert.are.equal(#graph1.edges, #graph2.edges)
    
    -- 检查根节点是否相同（通过文本比较）
    assert.are.equal(graph1.root_node.text, graph2.root_node.text)
    
    -- 检查每个节点的文本和位置信息
    for id, node1 in pairs(graph1.nodes_map) do
      local node2 = graph2.nodes_map[id]
      assert.is_not_nil(node2, "Node with ID " .. id .. " not found in second graph")
      assert.are.equal(node1.text, node2.text)
      
      -- 检查入边和出边数量
      assert.are.equal(#node1.incoming_edges, #node2.incoming_edges)
      assert.are.equal(#node1.outcoming_edges, #node2.outcoming_edges)
    end
    
    -- 检查每条边的属性
    for i, edge1 in ipairs(graph1.edges) do
      local edge2 = graph2.edges[i]
      
      -- 检查边的from_node和to_node
      assert.are.equal(edge1.from_node.text, edge2.from_node.text)
      assert.are.equal(edge1.to_node.text, edge2.to_node.text)
      
      -- 最重要：检查sub_edges的数量和内容
      assert.is_not_nil(edge1.sub_edges, "Edge1 sub_edges is nil")
      assert.is_not_nil(edge2.sub_edges, "Edge2 sub_edges is nil")
      assert.are.equal(#edge1.sub_edges, #edge2.sub_edges)
      
      for j, sub_edge1 in ipairs(edge1.sub_edges) do
        local sub_edge2 = edge2.sub_edges[j]
        
        -- 确保两个子边都有to_string方法
        assert.is_not_nil(sub_edge1.to_string, "SubEdge1 missing to_string method")
        assert.is_not_nil(sub_edge2.to_string, "SubEdge2 missing to_string method")
        
        -- 验证子边的坐标属性
        assert.are.equal(sub_edge1.start_row, sub_edge2.start_row)
        assert.are.equal(sub_edge1.start_col, sub_edge2.start_col)
        assert.are.equal(sub_edge1.end_row, sub_edge2.end_row)
        assert.are.equal(sub_edge1.end_col, sub_edge2.end_col)
      end
    end
  end
  
  -- 测试子图序列化和反序列化的完整流程
  it("should correctly serialize and restore subgraph with SubEdge objects", function()
    -- 1. 创建测试图
    local test_graph = create_test_graph()
    
    -- 2. 模拟添加到历史记录
    local history_entry = {
      buf_id = 101,
      root_node_name = test_graph.root_node.text,
      call_type = Caller.CallType.SUBGRAPH_CALL,
      timestamp = os.time(),
      subgraph = test_graph
    }
    
    local history = Caller._get_graph_history()
    table.insert(history, 1, history_entry)
    
    -- 3. 保存历史记录到"文件"
    print("开始保存历史记录...")
    Caller.save_history_to_file()
    
    -- 确保数据被正确写入到模拟文件系统
    print("检查文件是否存在: " .. tostring(mock_fs.files[history_file_path] ~= nil))
    print("文件内容长度: " .. (mock_fs.files[history_file_path] and #mock_fs.files[history_file_path] or 0))
    assert.is_not_nil(mock_fs.files[history_file_path])
    assert.is_not.equal(mock_fs.files[history_file_path], "")
    
    -- 4. 清空内存中的历史记录
    while #history > 0 do
      table.remove(history)
    end
    assert.are.equal(0, #history)
    
    -- 5. 从"文件"重新加载历史记录
    print("开始加载历史记录...")
    assert.is_not_nil(mock_fs.files[history_file_path], "历史文件应该已创建")
    assert.is_not.equal(mock_fs.files[history_file_path], "", "历史文件不应为空")
    Caller.load_history_from_file()
    
    -- 重新获取历史记录引用
    history = Caller._get_graph_history()
    
    -- 6. 验证是否正确加载了历史记录
    print("加载后的历史记录数量: " .. #history)
    assert.are.equal(1, #history)
    assert.are.equal(Caller.CallType.SUBGRAPH_CALL, history[1].call_type)
    assert.are.equal(test_graph.root_node.text, history[1].root_node_name)
    
    -- 7. 获取恢复的子图
    local restored_subgraph = history[1].subgraph
    print("恢复的子图是否为nil: " .. tostring(restored_subgraph == nil))
    assert.is_not_nil(restored_subgraph, "恢复的子图不应为nil")
    
    -- 8. 验证恢复的子图结构是否正确
    assert_graphs_equal(test_graph, restored_subgraph)
    
    -- 9. 特别验证子边的to_string方法可以正常调用
    for _, edge in ipairs(restored_subgraph.edges) do
      assert.is_not_nil(edge.sub_edges)
      for _, sub_edge in ipairs(edge.sub_edges) do
        local to_string_result = sub_edge:to_string()
        assert.is_not_nil(to_string_result)
        assert.is_not.equal(to_string_result, "")
      end
    end
  end)
  
  -- 测试完整的使用流程：生成子图 -> 保存 -> 重启 -> 加载
  it("should correctly handle the complete workflow of subgraph generation, save, and restore", function()
    -- 模拟整个过程
    
    -- 1. 创建原始图
    local original_graph = create_test_graph()
    
    -- 2. 选择节点以生成子图（这里我们选择节点1和节点2）
    local marked_node_ids = {}
    for id, node in pairs(original_graph.nodes_map) do
      if node.text == "function1" or node.text == "function2" then
        table.insert(marked_node_ids, id)
      end
    end
    
    -- 3. 生成子图
    local generated_subgraph = Caller.generate_subgraph(
      marked_node_ids,
      original_graph.nodes_map,
      original_graph.edges
    )
    
    assert.is_not_nil(generated_subgraph)
    assert.is_not_nil(generated_subgraph.root_node)
    
    -- 4. 添加子图到历史记录
    local history_entry = {
      buf_id = 102,
      root_node_name = generated_subgraph.root_node.text,
      call_type = Caller.CallType.SUBGRAPH_CALL,
      timestamp = os.time(),
      subgraph = generated_subgraph
    }
    
    local history = Caller._get_graph_history()
    table.insert(history, 1, history_entry)
    
    -- 5. 保存历史记录到"文件"（模拟重启前保存状态）
    print("测试2: 开始保存历史记录...")
    Caller.save_history_to_file()
    
    -- 检查文件是否正确写入
    print("测试2: 检查文件是否存在: " .. tostring(mock_fs.files[history_file_path] ~= nil))
    print("测试2: 文件内容长度: " .. (mock_fs.files[history_file_path] and #mock_fs.files[history_file_path] or 0))
    
    -- 6. 清空内存中的历史记录（模拟重启）
    while #history > 0 do
      table.remove(history)
    end
    
    -- 7. 从"文件"加载历史记录（模拟重启后）
    print("测试2: 开始加载历史记录...")
    assert.is_not_nil(mock_fs.files[history_file_path], "历史文件应该已创建")
    assert.is_not.equal(mock_fs.files[history_file_path], "", "历史文件不应为空")
    Caller.load_history_from_file()
    
    -- 重新获取历史记录引用
    history = Caller._get_graph_history()
    
    -- 8. 确认历史记录被正确加载
    print("测试2: 加载后的历史记录数量: " .. #history)
    assert.are.equal(1, #history)
    
    -- 9. 获取恢复的子图
    local restored_subgraph = history[1].subgraph
    print("测试2: 恢复的子图是否为nil: " .. tostring(restored_subgraph == nil))
    assert.is_not_nil(restored_subgraph, "恢复的子图不应为nil")
    
    -- 10. 比较原始子图和恢复的子图是否一致
    assert_graphs_equal(generated_subgraph, restored_subgraph)
    
    -- 11. 再次测试Edge对象和SubEdge对象的方法可用性
    for _, edge in ipairs(restored_subgraph.edges) do
      -- 测试Edge:to_string方法
      local edge_to_string = edge:to_string()
      assert.is_not_nil(edge_to_string)
      
      -- 测试Edge:is_same_edge方法
      local is_same = edge:is_same_edge(edge)
      assert.is_true(is_same)
      
      -- 测试SubEdge:to_string方法
      for _, sub_edge in ipairs(edge.sub_edges) do
        local sub_edge_to_string = sub_edge:to_string()
        assert.is_not_nil(sub_edge_to_string)
      end
    end
  end)
end) 