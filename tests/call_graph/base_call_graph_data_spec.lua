local BaseCallGraphData = require("call_graph.data.base_call_graph_data")
local GraphNode = require("call_graph.class.graph_node")
local FuncNode = require("call_graph.class.func_node")
local Edge = require("call_graph.class.edge")

-- 创建BaseCallGraphData的子类用于测试
local TestCallGraphData = {}
TestCallGraphData.__index = TestCallGraphData
setmetatable(TestCallGraphData, {
  __index = BaseCallGraphData
})

function TestCallGraphData:new(max_depth)
  local o = BaseCallGraphData.new(self, max_depth)
  o.request_method = "test/method"
  return o
end

function TestCallGraphData:get_request_params(fnode)
  return {}
end

function TestCallGraphData:call_handler(err, result, _, my_ctx)
  -- 空实现
end

-- 模拟vim相关函数，避免测试依赖neovim环境
vim = vim or {}
vim.api = vim.api or {}
vim.api.nvim_get_current_buf = vim.api.nvim_get_current_buf or function() return 1 end
vim.lsp = vim.lsp or {}
vim.lsp.get_clients = vim.lsp.get_clients or function() return {} end
vim.lsp.util = vim.lsp.util or {}
vim.lsp.util.make_position_params = vim.lsp.util.make_position_params or function() return { textDocument = { uri = "file:///test.lua" }, position = { line = 0, character = 0 } } end
vim.fn = vim.fn or {}
vim.fn.expand = vim.fn.expand or function() return "test_function" end
vim.uri_to_fname = vim.uri_to_fname or function(uri) return uri:gsub("file://", "") end
vim.fn.fnamemodify = vim.fn.fnamemodify or function(path, mod) return path end
vim.notify = vim.notify or function() end

describe("BaseCallGraphData", function()
  describe("gen_call_graph_done", function()
    it("should pass root_node, nodes, and edges to callback function", function()
      -- 创建测试实例
      local data = TestCallGraphData:new(3)
      
      -- 创建测试节点和边
      local root_node = data:make_graph_node("root/test.lua:1", { pos_params = {} })
      local node1 = data:make_graph_node("node1/test.lua:2", { pos_params = {} })
      local node2 = data:make_graph_node("node2/test.lua:3", { pos_params = {} })
      
      -- 设置root_node和注册节点
      data.root_node = root_node
      data:regist_gnode("root/test.lua:1", root_node)
      data:regist_gnode("node1/test.lua:2", node1)
      data:regist_gnode("node2/test.lua:3", node2)
      
      -- 创建测试边
      local edge1 = Edge:new(root_node, node1, nil, {})
      local edge2 = Edge:new(root_node, node2, nil, {})
      
      -- 注册边
      data:regist_edge(edge1)
      data:regist_edge(edge2)
      
      -- 设置pending_request为1，这样调用gen_call_graph_done会触发回调
      data._pending_request = 1
      
      -- 创建spy回调函数
      local callback_params = {}
      data.gen_graph_done_cb = function(root, nodes, edges)
        callback_params.root = root
        callback_params.nodes = nodes
        callback_params.edges = edges
      end
      
      -- 调用gen_call_graph_done
      data:gen_call_graph_done()
      
      -- 验证回调函数接收到正确的参数
      assert.are.equal(root_node, callback_params.root)
      assert.are.equal(3, #callback_params.nodes) -- 应该有3个节点
      assert.are.equal(2, #callback_params.edges) -- 应该有2条边
      
      -- 验证nodes包含所有注册的节点
      local node_ids = {}
      for _, node in ipairs(callback_params.nodes) do
        node_ids[node.text] = true
      end
      assert.is_true(node_ids["root/test.lua:1"])
      assert.is_true(node_ids["node1/test.lua:2"])
      assert.is_true(node_ids["node2/test.lua:3"])
      
      -- 验证edges包含所有注册的边
      assert.are.equal(edge1, callback_params.edges[1])
      assert.are.equal(edge2, callback_params.edges[2])
    end)
    
    it("should not call callback when pending_request is not zero", function()
      -- 创建测试实例
      local data = TestCallGraphData:new(3)
      
      -- 设置pending_request为2
      data._pending_request = 2
      
      -- 创建spy回调函数
      local callback_called = false
      data.gen_graph_done_cb = function()
        callback_called = true
      end
      
      -- 调用gen_call_graph_done一次，使pending_request变为1
      data:gen_call_graph_done()
      
      -- 验证回调函数没有被调用
      assert.is_false(callback_called)
      assert.are.equal(1, data._pending_request)
    end)
  end)
end) 