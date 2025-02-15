local M = {
  --- @type Node
  root_node = {},
  buf = {
    bufid = -1,
    graph = nil
  },
  pending_request = 0
}

local genrate_call_graph_from_node

local function draw()
  local Drawer = require("call_graph.drawer")
  if M.buf.bufid == -1 or not vim.api.nvim_buf_is_valid(M.buf.bufid) then
    M.buf.bufid = vim.api.nvim_create_buf(true, true)
    M.buf.graph = Drawer:new(M.buf.bufid)
  end
  M.buf.graph:draw(M.root_node)
  vim.api.nvim_set_current_buf(M.buf.bufid)
end

local function incoming_call_done()
  M.pending_request = M.pending_request - 1
  if M.pending_request == 0 then
    draw()
  end
end

local function incoming_call_handler(err, result, _, my_ctx)
  if err then
    vim.notify("Error getting incoming calls: " .. err, vim.log.levels.ERROR)
    incoming_call_done()
    return
  end
  if not result then
    vim.notify("No incoming calls found, result is nil", vim.log.levels.WARN)
    incoming_call_done()
    return
  end

  local from_node = my_ctx.from_node
  local depth = my_ctx.depth
  if #result == 0 then
    incoming_call_done()
    return
  end

  -- we have results, genrate node
  local Node = require("call_graph.class.node")
  local nodes = {}
  for _, call in ipairs(result) do
    local node_text = call.from.name
    local node_pos = call.from.range.start
    local from_uri = call.from.uri
    local node = Node:new(node_text, {
      params = {
        textDocument = {
          uri = from_uri,
        },
        position = node_pos
      }
    })
    table.insert(from_node.children, node)
  end
  -- for caller, call generate agian until depth is deep enough
  -- if depth < 3 then
  for _, child in ipairs(from_node.children) do
    M.pending_request = M.pending_request + 1
    genrate_call_graph_from_node(child, depth + 1)
  end
  -- end
  incoming_call_done()
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

---@param node Node
---@param depth integer
genrate_call_graph_from_node = function(node, depth)
  -- find client
  local client = find_buf_client()
  if client == nil then
    vim.notify("No LSP client found", vim.log.levels.WARN)
    return
  end
  -- convert posistion to callHierarchy item
  client.request("textDocument/prepareCallHierarchy", node.attr.params, function(err, result, ctx)
    if err then
      vim.notify("Error preparing call hierarchy: " .. err, vim.log.levels.ERROR)
      return
    end
    if not result or #result == 0 then
      vim.notify("No call hierarchy items found", vim.log.levels.WARN)
      return
    end
    local item = result[1]
    client.request("callHierarchy/incomingCalls", { item = item },
      function(err, result, ctx)
        incoming_call_handler(ress, result, ctx, {
          depth = depth,
          from_node = node
        })
      end
    )
  end)
end

function M.generate_call_graph()
  if M.pending_request ~= 0 then
    vim.notify("Pending request is not finished, please wait", vim.log.levels.WARN)
    return
  end
  local params = vim.lsp.util.make_position_params()
  local Node = require("call_graph.class.node")
  local root_text = vim.fn.expand("<cword>")
  M.root_node = Node:new(root_text, {
    params = params
  })
  M.pending_request = M.pending_request + 1
  genrate_call_graph_from_node(M.root_node, 1)
end

return M
