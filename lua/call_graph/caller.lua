local M = {
  --- @type FuncNode
  root_node = nil,
  nodes = {}, ---@type { [node_key: string] : GraphNode }, record the generated node to dedup
  parsed_nodes = {}, -- record the node has been called generate call graph
  edges = {}, ---@type { [edge_id: integer] :  Edge}
  buf = {
    bufid = -1,
    graph = nil
  },
  pending_request = 0
}

local log = require("call_graph.utils.log")
local FuncNode = require("call_graph.class.func_node")
local GraphNode = require("call_graph.class.graph_node")
local BufGotoEvent = require("call_graph.utils.buf_goto_event")
local Edge = require("call_graph.class.edge")


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

local function find_overlaps_nodes(row, col)
  local overlaps_nodes = {}
  for k, node in pairs(M.nodes) do
    if node.row == row and node.col <= col and col < node.col + #node.text then
      table.insert(overlaps_nodes, node)
    end
  end
  return overlaps_nodes
end

local function find_overlaps_edges(row, col)
  local overlaps_edges = {}
  for _, edge in pairs(M.edges) do
    for _, sub_edge in ipairs(edge.sub_edges) do
      if row == sub_edge.start_row and sub_edge.start_col <= col and col < sub_edge.end_col then
        table.insert(overlaps_edges, edge)
        break
      else
        if col == sub_edge.start_col and sub_edge.start_row <= row and row < sub_edge.end_row then
          table.insert(overlaps_edges, edge)
          break
        end
      end
    end
  end
  return overlaps_edges
end


local function jumpto(pos_params)
  local uri = pos_params.textDocument.uri
  local line = pos_params.position.line + 1       -- Neovim 的行号从 0 开始
  local character = pos_params.position.character -- Neovim 的列号从 1 开始
  -- 将 URI 转换为文件路径
  local file_path = vim.uri_to_fname(uri)
  -- 打开文件
  vim.cmd("edit " .. file_path)
  -- 跳转到指定位置
  vim.api.nvim_win_set_cursor(0, { line, character })
end


---@param row integer
---@param col integer
local function goto_event_cb(row, col)
  log.debug("user press", row, col)

  -- overlap with nodes?
  log.debug("compare node")
  local overlaps_nodes = find_overlaps_nodes(row, col)
  if #overlaps_nodes ~= 0 then -- find node
    if #overlaps_nodes ~= 1 then
      -- todo(zhangxingrui): 超过1个node，由用户选择
      log.warn("find overlaps nodes num is not 1, use the first node as default")
    end
    local target_node = overlaps_nodes[1]
    local fnode = target_node.usr_data
    local params = fnode.attr.params
    log.debug("pos overlaps with node", target_node.text)
    jumpto(params)
    return
  end

  -- overlap with edges?
  log.debug("compare edge", vim.inspect(M.edges))
  local overlaps_edges = find_overlaps_edges(row, col)
  if #overlaps_edges ~= 0 then
    if #overlaps_edges ~= 1 then
      -- todo(zhangxingrui): 超过1个edge，由用户选择
      log.warn("find overlaps edges num is", #overlaps_edges, "use the first edge as default")
      -- log.info("all overlaps edges", vim.inspect(overlaps_edges))
    end
    local target_edge = overlaps_edges[1]
    log.debug(string.format("pos overlaps with edge [%s->%s]", target_edge.from_node.text, target_edge.to_node.text))
    for _, p in ipairs(target_edge.from_node.parent) do
      if p.node.nodeid == target_edge.to_node.nodeid then
        if p.call_pos_params.position == nil then
          vim.notify("find the overlaps edge, but no position info provided", vim.log.levels.WARN)
        else
          jumpto(p.call_pos_params)
        end
        break
      end
    end
  end
end

---@param edge Edge
local function draw_edge_cb(edge)
  log.debug("from node", edge.from_node.text, "to node", edge.to_node.text)
  for _, sub_edge in ipairs(edge.sub_edges) do
    log.debug("edge id", edge.edgeid, "sub edge", sub_edge.start_row, sub_edge.start_col, sub_edge.end_row,
      sub_edge.end_col)
    if M.edges[tostring(edge.edgeid)] == nil then
      M.edges[tostring(edge.edgeid)] = edge
      break
    end
  end
end

local function draw()
  local Drawer = require("call_graph.drawer")
  if M.buf.bufid == -1 or not vim.api.nvim_buf_is_valid(M.buf.bufid) then
    M.buf.bufid = vim.api.nvim_create_buf(true, true)
    BufGotoEvent.setup_buffer(M.buf.bufid, goto_event_cb, "gd")
    M.buf.graph = Drawer:new(M.buf.bufid)
  end
  log.info("genrate graph of", M.root_node.text, "has child num", #M.root_node.children)
  M.buf.graph.draw_edge_cb = draw_edge_cb
  M.buf.graph:draw(M.root_node) -- draw函数完成node在buf中的位置计算（后续可在`goto_event_cb`中判定跳转到哪个node), 和node与edge绘制
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
-- Answer: 查了下，nvim是单线程模型，所以没有并发问题
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
  local fnode = from_node.usr_data
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
    table.insert(node.parent, { call_pos_params = call_pos_params, node = from_node })
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
    vim.notify("No LSP client found or current lsp does not support this operation", vim.log.levels.WARN)
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
      vim.cmd("e " .. file_path)
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
  M.edges = {}
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
