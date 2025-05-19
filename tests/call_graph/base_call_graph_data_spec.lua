local BaseCallGraphData = require("call_graph.data.base_call_graph_data")
local Edge = require("call_graph.class.edge")

-- Create a subclass of BaseCallGraphData for testing
local TestCallGraphData = {}
TestCallGraphData.__index = TestCallGraphData
setmetatable(TestCallGraphData, {
  __index = BaseCallGraphData,
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
  -- Empty implementation
end

-- Mock vim-related functions to avoid neovim environment dependency
vim = vim or {}
vim.api = vim.api or {}
vim.api.nvim_get_current_buf = vim.api.nvim_get_current_buf or function()
  return 1
end
vim.lsp = vim.lsp or {}
vim.lsp.get_clients = vim.lsp.get_clients or function()
  return {}
end
vim.lsp.util = vim.lsp.util or {}
vim.lsp.util.make_position_params = vim.lsp.util.make_position_params
  or function()
    return { textDocument = { uri = "file:///test.lua" }, position = { line = 0, character = 0 } }
  end
vim.fn = vim.fn or {}
vim.fn.expand = vim.fn.expand or function()
  return "test_function"
end
vim.uri_to_fname = vim.uri_to_fname or function(uri)
  return uri:gsub("file://", "")
end
vim.fn.fnamemodify = vim.fn.fnamemodify or function(path, mod)
  return path
end
vim.notify = vim.notify or function() end

describe("BaseCallGraphData", function()
  describe("gen_call_graph_done", function()
    it("should pass root_node, nodes, and edges to callback function", function()
      -- Create test instance
      local data = TestCallGraphData:new(3)

      -- Create test nodes and edges
      local root_node = data:make_graph_node("root/test.lua:1", { pos_params = {} })
      local node1 = data:make_graph_node("node1/test.lua:2", { pos_params = {} })
      local node2 = data:make_graph_node("node2/test.lua:3", { pos_params = {} })

      -- Set root_node and register nodes
      data.root_node = root_node
      data:regist_gnode("root/test.lua:1", root_node)
      data:regist_gnode("node1/test.lua:2", node1)
      data:regist_gnode("node2/test.lua:3", node2)

      -- Create test edges
      local edge1 = Edge:new(root_node, node1, nil, {})
      local edge2 = Edge:new(root_node, node2, nil, {})

      -- Register edges
      data:regist_edge(edge1)
      data:regist_edge(edge2)

      -- Set pending_request to 1, this way calling gen_call_graph_done will trigger callback
      data._pending_request = 1

      -- Create spy callback function
      local callback_params = {}
      data.gen_graph_done_cb = function(root, nodes, edges)
        callback_params.root = root
        callback_params.nodes = nodes
        callback_params.edges = edges
      end

      -- Call gen_call_graph_done
      data:gen_call_graph_done()

      -- Verify callback function received correct parameters
      assert.are.equal(root_node, callback_params.root)
      assert.are.equal(3, #callback_params.nodes) -- Should have 3 nodes
      assert.are.equal(2, #callback_params.edges) -- Should have 2 edges

      -- Verify nodes contain all registered nodes
      local node_ids = {}
      for _, node in ipairs(callback_params.nodes) do
        node_ids[node.text] = true
      end
      assert.is_true(node_ids["root/test.lua:1"])
      assert.is_true(node_ids["node1/test.lua:2"])
      assert.is_true(node_ids["node2/test.lua:3"])

      -- Verify edges contain all registered edges
      assert.are.equal(edge1, callback_params.edges[1])
      assert.are.equal(edge2, callback_params.edges[2])
    end)

    it("should not call callback when pending_request is not zero", function()
      -- Create test instance
      local data = TestCallGraphData:new(3)

      -- Set pending_request to 2
      data._pending_request = 2

      -- Create spy callback function
      local callback_called = false
      data.gen_graph_done_cb = function()
        callback_called = true
      end

      -- Call gen_call_graph_done once, making pending_request become 1
      data:gen_call_graph_done()

      -- Verify callback function was not called
      assert.is_false(callback_called)
      assert.are.equal(1, data._pending_request)
    end)
  end)
end)
