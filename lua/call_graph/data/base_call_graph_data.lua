-- 基类，用于构建绘图数据结构
local log = require("call_graph.utils.log")
local FuncNode = require("call_graph.class.func_node")
local GraphNode = require("call_graph.class.graph_node")
local Edge = require("call_graph.class.edge")

local BaseCallGraphData = {}
BaseCallGraphData.__index = BaseCallGraphData

function BaseCallGraphData:new(max_depth)
  local o = setmetatable({}, self)
  o.root_node = nil --- @type FuncNode
  o.nodes = {}      --@type { [node_key: string] : GraphNode }, record the generated node to dedup
  o.max_depth = max_depth

  o._pending_request = 0
  o._parsednodes = {} -- record the node has been called generate call graph
  return o
end

function BaseCallGraphData:clear_data()
  self.root_node = nil
  self.nodes = {}
  self._pending_request = 0
  self._parsednodes = {}
end

function BaseCallGraphData:make_node_key(uri, line, func_name)
  local file_path = vim.uri_to_fname(uri)
  local file_name = vim.fn.fnamemodify(file_path, ":t")
  return string.format("%s/%s:%d", func_name, file_name, line + 1)
end

function BaseCallGraphData:is_gnode_exist(node_key)
  return self.nodes[node_key] ~= nil
end

function BaseCallGraphData:regist_gnode(node_key, node)
  assert(not self:is_gnode_exist(node_key), "node already exist")
  self.nodes[node_key] = node
end

function BaseCallGraphData:is_parsed_node_exsit(node_key)
  return self._parsednodes[node_key] ~= nil
end

function BaseCallGraphData:regist_parsed_node(node_key, parsed_node)
  assert(not self:is_parsed_node_exsit(node_key), "node already exist")
  self._parsednodes[node_key] = parsed_node
end

function BaseCallGraphData:make_graph_node(node_text, attr)
  local func_node = FuncNode:new(node_text, attr)
  return GraphNode:new(node_text, func_node)
end

function BaseCallGraphData:gen_call_graph_done()
  self._pending_request = self._pending_request - 1
  if self._pending_request == 0 then
    if self.gen_graph_done_cb then
      self.gen_graph_done_cb(self.root_node)
    end
  end
end

function BaseCallGraphData:find_buf_client(method)
  local bufnr = vim.api.nvim_get_current_buf()
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  if #clients == 0 then
    return nil
  end
  -- found one client support the given method
  local client = nil
  for _, c in ipairs(clients) do
    if c.supports_method(method) then
      client = c
      break
    end
  end
  return client
end

function BaseCallGraphData:generate_call_graph_from_node(gnode, depth)
  local fnode = gnode.usr_data
  if self:is_parsed_node_exsit(fnode.node_key) then
    self:gen_call_graph_done()
    return
  end
  self:regist_parsed_node(fnode.node_key, gnode)
  log.info("generate call graph of node", gnode.text)
  -- find client
  local client = self:find_buf_client(self.request_method)
  if client == nil then
    vim.notify("No LSP client found or current lsp does not support this operation", vim.log.levels.WARN)
    self:gen_call_graph_done()
    return
  end

  local params = self:get_request_params(fnode)
  client.request(self.request_method, params, function(err, result, _)
    self:call_handler(err, result, nil, {
      from_node = gnode,
      depth = depth,
    })
  end)
end

function BaseCallGraphData:generate_call_graph(gen_graph_done_cb, reuse_data)
  local client = self:find_buf_client(self.request_method)
  if client == nil then
    vim.notify("No LSP client found or current lsp does not support this operation", vim.log.levels.WARN)
    return
  end
  local pos_params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  self.gen_graph_done_cb = gen_graph_done_cb
  local func_name = vim.fn.expand("<cword>")
  local root_text = self:make_node_key(pos_params.textDocument.uri, pos_params.position.line, func_name)
  local from_node
  if reuse_data then
    from_node = self.nodes[root_text]
    if not from_node then
      self:clear_data()
      self.root_node = self:make_graph_node(root_text, { pos_params = pos_params })
      self:regist_gnode(root_text, self.root_node)
      from_node = self.root_node
    end
  else
    self:clear_data()
    self.root_node = self:make_graph_node(root_text, { pos_params = pos_params })
    self:regist_gnode(root_text, self.root_node)
    from_node = self.root_node
  end
  self._pending_request = self._pending_request + 1
  self:generate_call_graph_from_node(from_node, 1)
end

-- 抽象方法，需要子类实现
function BaseCallGraphData:get_request_params(fnode)
  error("Subclass must implement get_request_params method")
end

function BaseCallGraphData:call_handler(err, result, _, my_ctx)
  error("Subclass must implement call_handler method")
end

return BaseCallGraphData
