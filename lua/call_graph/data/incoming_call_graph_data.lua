-- 发起lsp incoming call请求，构建绘图数据结构
local log = require("call_graph.utils.log")
local FuncNode = require("call_graph.class.func_node")
local GraphNode = require("call_graph.class.graph_node")
local Edge = require("call_graph.class.edge")

local CallGraphData = {}
CallGraphData.__index = CallGraphData


-- forward declare
local generate_call_graph_from_node

function CallGraphData:new()
  local o = setmetatable({}, CallGraphData)
  o.root_node = nil --- @type FuncNode
  o.edges = {}      --@type { [edge_id: string] :  Edge }
  o.nodes = {}      --@type { [node_key: string] : GraphNode }, record the generated node to dedup

  o._pending_request = 0
  o._parsednodes = {} -- record the node has been called generate call graph
  return o
end

-- TODO(zhangxingrui): any way not to rewrite this again?
function CallGraphData:clear_data()
  self.root_node = nil   --- @type FuncNode
  self.edges = {}        --@type { [edge_id: string] :  Edge }
  self.nodes = {}        --@type { [node_key: string] : GraphNode }, record the generated node to dedup
  self._pending_request = 0
  self._parsednodes = {} -- record the node has been called generate call graph
end

local function make_node_key(uri, line, func_name)
  local file_path = vim.uri_to_fname(uri)
  local file_name = vim.fn.fnamemodify(file_path, ":t")
  local node_text = string.format("%s@%s:%d", func_name, file_name, line + 1)
  return node_text
end

---@param node_key string
---@return boolean
local function is_gnode_exist(self, node_key)
  return self.nodes[node_key] ~= nil
end

---@param node_key string
---@param node GraphNode
local function regist_gnode(self, node_key, node)
  assert(not is_gnode_exist(self, node_key), "node already exist")
  self.nodes[node_key] = node
end

---@param node_key string
local function is_parsed_node_exsit(self, node_key)
  return self._parsednodes[node_key] ~= nil
end

---@param node_key string
---@param pasred_node GraphNode
local function regist_parsed_node(self, node_key, pasred_node)
  assert(not is_parsed_node_exsit(self, node_key), "node already exist")
  self._parsednodes[node_key] = pasred_node
end

---@param node_text string
---@param attr any
---@return GraphNode
local function make_graph_node(node_text, attr)
  local func_node = FuncNode:new(node_text, attr)
  local graph_node = GraphNode:new(node_text, func_node)
  return graph_node
end

local function gen_call_graph_done(self)
  self._pending_request = self._pending_request - 1
  if self._pending_request == 0 then
    if self.gen_graph_done_cb then
      self.gen_graph_done_cb(self.root_node, self.nodes, self.edges)
    end
  end
end

-- 该接口为异步回调
local function incoming_call_handler(err, result, _, my_ctx)
  local from_node = my_ctx.from_node
  local depth = my_ctx.depth
  local self = my_ctx.self
  if err then
    vim.notify("Error getting incoming calls: " .. err.message, vim.log.levels.ERROR)
    gen_call_graph_done(self)
    return
  end
  if not result then
    vim.notify("No incoming calls found, result is nil", vim.log.levels.WARN)
    gen_call_graph_done(self)
    return
  end
  log.info("incoming call handler of", from_node.text, "reuslt num", #result)
  if #result == 0 then
    gen_call_graph_done(self)
    return
  end
  -- we have results, genrate node
  for _, call in ipairs(result) do
    local from_uri = call.from.uri
    local node_pos = call.from.range.start
    local call_pos_params
    if #call.fromRanges == 0 then
      call_pos_params = {
        position = nil,
        textDocument = {
          uri = from_uri,
        }
      }
    else
      call_pos_params = {
        position = call.fromRanges[1].start,
        textDocument = {
          uri = from_uri,
        }
      }
    end

    local node_text = make_node_key(from_uri, node_pos.line, call.from.name)
    local node
    if is_gnode_exist(self, node_text) then
      node = self.nodes[node_text]
    else
      node = make_graph_node(node_text, {
        pos_params = { -- node itself
          textDocument = {
            uri = from_uri,
          },
          position = node_pos
        }
      })
      regist_gnode(self, node_text, node)
    end
    -- build node connections
    table.insert(node.calls, from_node)
    table.insert(from_node.children, node)
    -- generate edges
    -- In GraphData's view, from_node is the callee, node is the caller
    -- but in Edge class' view, from_node is the caller, node is the callee
    local edge = Edge:new(node, from_node, call_pos_params)
    -- from_node is the callee, node is the caller
    table.insert(from_node.incoming_edges, edge)
    table.insert(node.outcoming_edges, edge)
    table.insert(self.edges, edge)
  end
  -- for caller, call generate agian until depth is deep enough
  -- if depth < 3 then
  for _, child in ipairs(from_node.children) do
    local child_node_key = child.usr_data.node_key
    if not is_parsed_node_exsit(self, child_node_key) then
      self._pending_request = self._pending_request + 1
      generate_call_graph_from_node(self, child, depth + 1)
    end
  end
  -- end
  gen_call_graph_done(self)
end

local function find_buf_client()
  local bufnr = vim.api.nvim_get_current_buf()
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  if #clients == 0 then
    return nil
  end
  -- found one client support callHierarchy/incomingCalls
  local client = nil
  for _, c in ipairs(clients) do
    if c.supports_method("callHierarchy/incomingCalls") then
      client = c
      break
    end
  end
  return client
end

---@param node GraphNode
---@param depth integer
generate_call_graph_from_node = function(self, gnode, depth)
  local fnode = gnode.usr_data
  if is_parsed_node_exsit(self, fnode.node_key) then
    gen_call_graph_done(self)
    return
  end
  regist_parsed_node(self, fnode.node_key, gnode)
  log.info("generate call graph of node", gnode.text)
  -- find client
  local client = find_buf_client()
  if client == nil then
    vim.notify("No LSP client found or current lsp does not support this operation", vim.log.levels.WARN)
    gen_call_graph_done(self)
    return
  end
  -- convert posistion to callHierarchy item
  client.request("textDocument/prepareCallHierarchy", fnode.attr.pos_params, function(err, result, ctx)
    if err then
      gen_call_graph_done(self)
      log.warn("Error preparing call hierarchy: " .. err.message, "call info", fnode.node_key)
      return
    end
    if not result or #result == 0 then
      gen_call_graph_done(self)
      vim.notify("No call hierarchy items found", vim.log.levels.WARN)
      return
    end
    local item = result[1]
    client.request("callHierarchy/incomingCalls", { item = item },
      function(err, result, _)
        incoming_call_handler(err, result, ctx, {
          depth = depth,
          from_node = gnode,
          self = self
        })
      end
    )
  end)
end

function CallGraphData:generate_call_graph(gen_graph_done_cb, reuse_data)
  self.gen_graph_done_cb = gen_graph_done_cb
  local pos_params = vim.lsp.util.make_position_params()
  local func_name = vim.fn.expand("<cword>")
  local root_text = make_node_key(pos_params.textDocument.uri, pos_params.position.line, func_name)
  local from_node
  if reuse_data and is_gnode_exist(self, root_text) then
    from_node = self.nodes[root_text]
  else
    self:clear_data()
    self.root_node = make_graph_node(root_text, { pos_params = pos_params })
    regist_gnode(self, root_text, self.root_node)
    from_node = self.root_node
  end
  self._pending_request = self._pending_request + 1
  generate_call_graph_from_node(self, from_node, 1)
end

return CallGraphData
