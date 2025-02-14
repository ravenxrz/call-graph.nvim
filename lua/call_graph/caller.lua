local M = {}

function M._incoming_call_handler(err, result, ctx)
  if err then
    vim.notify("Error getting incoming calls: " .. err, vim.log.levels.ERROR)
    return
  end
  if not result or #result == 0 then
    vim.notify("No incoming calls found", vim.log.levels.WARN)
    return
  end

  -- now we have results, genrate node
  -- lines = {}
  -- for _, call in ipairs(result) do
  --   local from_name = call.from.name
  --   local from_line = call.from.range.start.line + 1 -- Neovim 的行号从 1 开始
  --   local from_character = call.from.range.start.character + 1
  --   local from_uri = call.from.uri
  --   local line_text = string.format("%s (%s:%d:%d)", from_name, from_uri, from_line, from_character)
  --   table.insert(lines, line_text)
  -- end
  -- P(lines)

  print("test..")
  local bufid = vim.api.nvim_create_buf(true, true)
  local drawer = require("call_graph.drawer")
  local node = require("call_graph.class.node")
  -- local edge = require("call_graph.class.edge")
  -- local file_pos = require("call_graph.class.file_pos")
  local graph = drawer:new(bufid)
  local node1 = node:new("main", {})
  local node2 = node:new("run1fjlsjfljsdlfjlsajfljablwr12ree", {})
  local node3 = node:new("run2fjxxx", {})

  node1.children = { node2, node3 }
  node2.children = { node3 }
  graph:draw(node1)
  -- local node3 = node:new("run2", {})
  -- graph:add_edge(node1, node2)
  -- graph:add_edge(node2, node3)
  vim.api.nvim_set_current_buf(bufid)
end

function M._find_buf_client()
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

function M.generate_call_graph()
  -- find client
  local client = M._find_buf_client()
  if client == nil then
    vim.notify("No LSP client found", vim.log.levels.WARN)
    return
  end
  -- do requset
  local bufnr = vim.api.nvim_get_current_buf()
  local pos = vim.lsp.util.make_position_params()
  -- convert posistion to callHierarchy item
  client.request("textDocument/prepareCallHierarchy", pos, function(err, result, ctx)
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
      M._incoming_call_handler, bufnr)
  end, bufnr)
end

return M
