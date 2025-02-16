local M = {
  --- @type FuncNode
  root_node = nil,
  nodes = {}, ---@type { [node_key: string] : GraphNode }, record the generated node to dedup
  parsed_nodes = {}, -- record which node has been called generate call graph
  buf = {
    bufid = -1,
    graph = nil
  },
  pending_request = 0
}

local log = require("call_graph.utils.log")
local FuncNode = require("call_graph.class.func_node")
local GraphNode = require("call_graph.class.graph_node")

local genrate_call_graph_from_node

local function make_node_key(uri, line, func_name)
  local file_path = vim.uri_to_fname(uri)
  local file_name = vim.fn.fnamemodify(file_path, ":t")
  local node_text = string.format("%s@%s:%d", func_name, file_name, line + 1)
  return node_text
end

---@param node_key string
---@return boolean
local function is_node_exist(node_key)
  return M.nodes[node_key] ~= nil
end

---@param node_key string
---@param node GraphNode
local function regist_node(node_key, node)
  assert(not is_node_exist(node_key), "node already exist")
  M.nodes[node_key] = node
end

---@param node_key string
local function is_parsed_node_exsit(node_key)
  return M.parsed_nodes[node_key] ~= nil
end

---@param node_key string
---@param pasred_node GraphNode
local function regist_parsed_node(node_key, pasred_node)
  assert(not is_parsed_node_exsit(node_key), "node already exist")
  M.parsed_nodes[node_key] = pasred_node
end


---@param node_text string
---@param attr any
---@return GraphNode
local function make_graph_node(node_text, attr)
  local func_node = FuncNode:new(node_text, attr)
  local graph_node = GraphNode:new(node_text, func_node)
  return graph_node
end

local function draw()
  local Drawer = require("call_graph.drawer")
  if M.buf.bufid == -1 or not vim.api.nvim_buf_is_valid(M.buf.bufid) then
    M.buf.bufid = vim.api.nvim_create_buf(true, true)
    M.buf.graph = Drawer:new(M.buf.bufid)
  end
  log.info("genrate graph of", M.root_node.text, "has child num", #M.root_node.children)
  for i, node in ipairs(M.root_node.children) do
    log.debug("child", i, node.text)
  end
  M.buf.graph:draw(M.root_node)
  vim.api.nvim_set_current_buf(M.buf.bufid)
end

local function gen_call_graph_done()
  M.pending_request = M.pending_request - 1
  if M.pending_request == 0 then
    draw()
  end
end

-- 该接口为异步回调
-- TODO(zhangxingrui): 是否会有并发问题？不熟悉lua和nvim的线程模型是啥样的
local function incoming_call_handler(err, result, _, my_ctx)
  local from_node = my_ctx.from_node
  local depth = my_ctx.depth
  if err then
    vim.notify("Error getting incoming calls: " .. err.message, vim.log.levels.ERROR)
    gen_call_graph_done()
    return
  end
  if not result then
    vim.notify("No incoming calls found, result is nil", vim.log.levels.WARN)
    gen_call_graph_done()
    return
  end

  log.info("incoming call handler of", from_node.text, "reuslt num", #result)

  if #result == 0 then
    gen_call_graph_done()
    return
  end

  -- we have results, genrate node
  for _, call in ipairs(result) do
    local from_uri = call.from.uri
    local node_pos = call.from.range.start
    local node_text = make_node_key(from_uri, node_pos.line, call.from.name)
    local node
    if is_node_exist(node_text) then
      node = M.nodes[node_text]
    else
      node = make_graph_node(node_text, {
        params = {
          textDocument = {
            uri = from_uri,
          },
          position = node_pos
        }
      })
      regist_node(node_text, node)
    end
    table.insert(from_node.children, node)
  end
  -- for caller, call generate agian until depth is deep enough
  -- if depth < 3 then
  for _, child in ipairs(from_node.children) do
    if not is_parsed_node_exsit(child.text) then
      M.pending_request = M.pending_request + 1
      genrate_call_graph_from_node(child, depth + 1)
    end
  end
  -- end
  gen_call_graph_done()
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
genrate_call_graph_from_node = function(gnode, depth)
  local fnode = gnode.usr_data
  assert(not is_parsed_node_exsit(fnode.node_key), "node already parsed")
  regist_parsed_node(fnode.node_key, gnode)

  log.info("generate call graph of node", gnode.text)

  -- find client
  local client = find_buf_client()
  if client == nil then
    vim.notify("No LSP client found", vim.log.levels.WARN)
    gen_call_graph_done()
    return
  end

  -- convert posistion to callHierarchy item
  client.request("textDocument/prepareCallHierarchy", fnode.attr.params, function(err, result, ctx)
    if err then
      gen_call_graph_done()
      log.warn("Error preparing call hierarchy: " .. err.message, "call info", fnode.node_key)
      local uri = fnode.attr.params.textDocument.uri
      local file_path = vim.uri_to_fname(uri)
      vim.cmd("e ".. file_path)
      return
    end
    if not result or #result == 0 then
      gen_call_graph_done()
      vim.notify("No call hierarchy items found", vim.log.levels.WARN)
      return
    end
    local item = result[1]
    client.request("callHierarchy/incomingCalls", { item = item },
      function(err, result, ctx)
        incoming_call_handler(err, result, ctx, {
          depth = depth,
          from_node = gnode
        })
      end
    )
  end)
end

local function reset_graph()
  M.root_node = nil
  M.buf = {
    bufid = -1,
    graph = nil
  }
  M.nodes = {}
  M.parsed_nodes = {}
end

function M.generate_call_graph()
  if M.pending_request ~= 0 then
    vim.notify(string.format("Pending request is not finished, please wait, pending request num:%d", M.pending_request),
      vim.log.levels.WARN)
    return
  end
  reset_graph()
  local params = vim.lsp.util.make_position_params()
  local func_name = vim.fn.expand("<cword>")
  local root_text = make_node_key(params.textDocument.uri, params.position.line, func_name)
  M.root_node = make_graph_node(root_text, { params = params })
  regist_node(root_text, M.root_node)
  M.pending_request = M.pending_request + 1
  genrate_call_graph_from_node(M.root_node, 1)
end

return M

