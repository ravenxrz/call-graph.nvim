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
  o.nodes = {} --@type { [node_key: string] : GraphNode }, record the generated node to dedup
  o.edges = {} --@type Edge[], record all edges in the call graph
  o.max_depth = max_depth

  o._pending_request = 0
  o._parsednodes = {} -- record the node has been called generate call graph
  return o
end

function BaseCallGraphData:clear_data()
  self.root_node = nil
  self.nodes = {}
  self.edges = {}
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
      -- 传递nodes和edges给回调函数
      local nodes_list = {}
      for _, node in pairs(self.nodes) do
        table.insert(nodes_list, node)
      end
      self.gen_graph_done_cb(self.root_node, nodes_list, self.edges)
    end
  end
end

function BaseCallGraphData:find_buf_client(method)
  local bufnr = vim.api.nvim_get_current_buf()
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  if #clients == 0 then
    log.warn("No LSP clients found for buffer " .. bufnr)
    return nil
  end
  
  -- 1. 在日志中输出所有可用的客户端信息
  log.info("Found " .. #clients .. " LSP clients for buffer " .. bufnr)
  for i, c in ipairs(clients) do
    log.info(string.format("Client %d: id=%d, name=%s", i, c.id, c.name or "unknown"))
  end
  
  -- 2. 更强大的客户端支持检测方法
  for _, c in ipairs(clients) do
    -- 检查是否有supports_method函数
    if c.supports_method then
      local supports = c.supports_method(method)
      log.info(string.format("Client %s supports method %s: %s", c.name or c.id, method, tostring(supports)))
      if supports then
        log.info("Using client " .. (c.name or tostring(c.id)) .. " for method " .. method)
        return c
      end
    -- 向后兼容：某些LSP客户端可能没有supports_method函数
    elseif c.server_capabilities then
      -- 如果是请求callHierarchy相关的方法，检查相应的能力
      if method:find("callHierarchy") then
        if c.server_capabilities.callHierarchyProvider then
          log.info("Client " .. (c.name or tostring(c.id)) .. " has callHierarchyProvider capability")
          return c
        end
      end
    end
  end
  
  -- 3. 兜底方案：如果找不到支持的客户端，但这是incoming calls请求，尝试使用第一个客户端
  if method == "callHierarchy/incomingCalls" and #clients > 0 then
    log.warn("No client explicitly supports " .. method .. ", but trying with first client as fallback")
    return clients[1]
  end
  
  log.warn("No LSP client found that supports method: " .. method)
  return nil
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

-- 添加新方法：注册边到edges数组中
function BaseCallGraphData:regist_edge(edge)
  table.insert(self.edges, edge)
end

return BaseCallGraphData
