local InComingCall = {}
InComingCall.__index = InComingCall

local log = require("call_graph.utils.log")
local FuncNode = require("call_graph.class.func_node")
local GraphNode = require("call_graph.class.graph_node")
local Events = require("call_graph.utils.events")
-- local Edge = require("call_graph.class.edge")

function InComingCall:new()
  local o = setmetatable({}, InComingCall)
  o.root_node = nil   --- @type FuncNode
  o.nodes = {}        --@type { [node_key: string] : GraphNode }, record the generated node to dedup
  o.parsed_nodes = {} -- record the node has been called generate call graph
  o.edges = {}        --@type { [edge_id: string] :  Edge }
  o.buf = {
    bufid = -1,
    graph = nil
  }
  o.pending_request = 0
  o.namespace_id = vim.api.nvim_create_namespace('call_graph_hl') -- for highlight
  o.last_cursor_hold = {
    node = nil,
  }
  return o
end

local genrate_call_graph_from_node

---@param edge Edge
local function hl_edge(self, edge)
  for _, sub_edge in pairs(edge.sub_edges) do
    log.debug(string.format("hl sub edge: start_row:%d start_col:%d end_row:%d end_col:%d", sub_edge.start_row,
      sub_edge.start_col, sub_edge.end_row, sub_edge.end_col))
    -- hl by line
    for i = sub_edge.start_row, sub_edge.end_row - 1 do
      local line_text = vim.api.nvim_buf_get_lines(0, i, i + 1, false)[1] or ""
      local r = vim.api.nvim_buf_set_extmark(self.buf.bufid, self.namespace_id, i, sub_edge.start_col, {
        end_row = i,
        end_col = sub_edge.end_col,
        hl_group = "MyHighlight"
      })
    end
  end
end

local function make_node_key(uri, line, func_name)
  local file_path = vim.uri_to_fname(uri)
  local file_name = vim.fn.fnamemodify(file_path, ":t")
  local node_text = string.format("%s@%s:%d", func_name, file_name, line + 1)
  return node_text
end

---@param node_key string
---@return boolean
local function is_node_exist(self, node_key)
  return self.nodes[node_key] ~= nil
end

---@param node_key string
---@param node GraphNode
local function regist_node(self, node_key, node)
  assert(not is_node_exist(self, node_key), "node already exist")
  self.nodes[node_key] = node
end

---@param node_key string
local function is_parsed_node_exsit(self, node_key)
  return self.parsed_nodes[node_key] ~= nil
end

---@param node_key string
---@param pasred_node GraphNode
local function regist_parsed_node(self, node_key, pasred_node)
  assert(not is_parsed_node_exsit(self, node_key), "node already exist")
  self.parsed_nodes[node_key] = pasred_node
end


---@param node_text string
---@param attr any
---@return GraphNode
local function make_graph_node(node_text, attr)
  local func_node = FuncNode:new(node_text, attr)
  local graph_node = GraphNode:new(node_text, func_node)
  return graph_node
end

local function overlap_node(row, col, node)
  return node.row == row and node.col <= col and col < node.col + #node.text
end

local function overlap_edge(row, col, edge)
  for _, sub_edge in ipairs(edge.sub_edges) do
    if (row == sub_edge.start_row and sub_edge.start_col <= col and col < sub_edge.end_col) or
        (col == sub_edge.start_col and sub_edge.start_row <= row and row < sub_edge.end_row) then
      return true
    end
  end
  return false
end

local function find_overlaps_nodes(self, row, col)
  local overlaps_nodes = {}
  for _, node in pairs(self.nodes) do
    if overlap_node(row, col, node) then
      table.insert(overlaps_nodes, node)
    end
  end
  return overlaps_nodes
end

local function find_overlaps_edges(self, row, col)
  local overlaps_edges = {}
  for _, edge in pairs(self.edges) do
    if overlap_edge(row, col, edge) then
      table.insert(overlaps_edges, edge)
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
local function goto_event_cb(row, col, ctx)
  log.debug("user press", row, col)
  local self = ctx
  assert(self ~= nil, "")

  -- overlap with nodes?
  log.debug("compare node")
  local overlaps_nodes = find_overlaps_nodes(self, row, col)
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
  log.debug("compare edge", vim.inspect(self.edges))
  local overlaps_edges = find_overlaps_edges(self, row, col)
  if #overlaps_edges ~= 0 then
    if #overlaps_edges ~= 1 then
      -- todo(zhangxingrui): 超过1个edge，由用户选择
      log.warn("find overlaps edges num is", #overlaps_edges, ",use the first edge as default")
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


local function cursor_hold_cb(row, col, ctx)
  local self = ctx
  -- check overlap with last node or not
  if self.last_cursor_hold.node ~= nil and overlap_node(row, col, self.last_cursor_hold.node) then
    return
  end
  -- clear hl, redraw hl
  vim.api.nvim_buf_clear_namespace(self.buf.bufid, self.namespace_id, 0, -1)
  -- check node
  local overlaps_nodes = find_overlaps_nodes(self, row, col)
  if #overlaps_nodes ~= 0 then -- find node
    if #overlaps_nodes ~= 1 then
      log.warn("find overlaps nodes num is not 1, use the first node as default")
    end
    local target_node = overlaps_nodes[1]
    self.last_cursor_hold_node = target_node
    -- hl incoming
    for _, edge in pairs(target_node.incoming_edges) do
      hl_edge(self, edge)
    end
    -- hl outcoming
    for _, edge in pairs(target_node.outcoming_edges) do
      hl_edge(self, edge)
    end
    return
  end
  -- check edge
  local overlaps_edges = find_overlaps_edges(self, row, col)
  if #overlaps_edges ~= 0 then
    for _, edge in ipairs(overlaps_edges) do
      hl_edge(self, edge)
    end
  end
end

---@param edge Edge
local function draw_edge_cb(edge, ctx)
  local self = ctx -- TODO: fix this
  assert(self ~= nil, "")
  log.debug("from node", edge.from_node.text, "to node", edge.to_node.text)
  for _, sub_edge in ipairs(edge.sub_edges) do
    log.debug("edge id", edge.edgeid, "sub edge", sub_edge.start_row, sub_edge.start_col, sub_edge.end_row,
      sub_edge.end_col)
    if self.edges[tostring(edge.edgeid)] == nil then
      self.edges[tostring(edge.edgeid)] = edge
      -- update node edges info
      table.insert(edge.from_node.outcoming_edges, edge)
      table.insert(edge.to_node.incoming_edges, edge)
      break
    end
  end
end

local function draw(self)
  local Drawer = require("call_graph.drawer")
  if self.buf.bufid == -1 or not vim.api.nvim_buf_is_valid(self.buf.bufid) then
    self.buf.bufid = vim.api.nvim_create_buf(true, true)
  end
  Events.setup_buffer_press_cursor_cb(self.buf.bufid, goto_event_cb, self, "gd")
  Events.regist_cursor_hold_cb(self.buf.bufid, cursor_hold_cb, self)
  self.buf.graph = Drawer:new(self.buf.bufid)
  log.info("genrate graph of", self.root_node.text, "has child num", #self.root_node.children)
  self.buf.graph.draw_edge_cb = {
    cb = draw_edge_cb,
    cb_ctx = self
  }
  self.buf.graph:draw(self.root_node) -- draw函数完成node在buf中的位置计算（后续可在`goto_event_cb`中判定跳转到哪个node), 和node与edge绘制
  vim.api.nvim_set_current_buf(self.buf.bufid)
end

local function gen_call_graph_done(self)
  self.pending_request = self.pending_request - 1
  if self.pending_request == 0 then
    draw(self)
  end
end

-- 该接口为异步回调
-- TODO(zhangxingrui): 是否会有并发问题？不熟悉lua和nvim的线程模型是啥样的
-- Answer: 查了下，nvim是单线程模型，所以没有并发问题
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
    if is_node_exist(self, node_text) then
      node = self.nodes[node_text]
    else
      node = make_graph_node(node_text, {
        params = {
          textDocument = {
            uri = from_uri,
          },
          position = node_pos
        }
      })
      regist_node(self, node_text, node)
    end
    table.insert(node.parent, { call_pos_params = call_pos_params, node = from_node })
    table.insert(from_node.children, node)
  end
  -- for caller, call generate agian until depth is deep enough
  -- if depth < 3 then
  for _, child in ipairs(from_node.children) do
    if not is_parsed_node_exsit(self, child.text) then
      self.pending_request = self.pending_request + 1
      genrate_call_graph_from_node(self, child, depth + 1)
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
genrate_call_graph_from_node = function(self, gnode, depth)
  local fnode = gnode.usr_data
  assert(not is_parsed_node_exsit(self, fnode.node_key), "node already parsed")
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
  client.request("textDocument/prepareCallHierarchy", fnode.attr.params, function(err, result, ctx)
    if err then
      gen_call_graph_done(self)
      log.warn("Error preparing call hierarchy: " .. err.message, "call info", fnode.node_key)
      -- local uri = fnode.attr.params.textDocument.uri
      -- local file_path = vim.uri_to_fname(uri)
      -- vim.cmd("e " .. file_path)
      return
    end
    if not result or #result == 0 then
      gen_call_graph_done(self)
      vim.notify("No call hierarchy items found", vim.log.levels.WARN)
      return
    end
    local item = result[1]
    client.request("callHierarchy/incomingCalls", { item = item },
      function(err, result, ctx)
        incoming_call_handler(err, result, ctx, {
          depth = depth,
          from_node = gnode,
          self = self
        })
      end
    )
  end)
end

function InComingCall:reset_graph()
  if self.buf.graph ~= nil then
    self.buf.graph:clear_buf()
  end
  local bufid = self.buf.bufid
  self = InComingCall:new()
  self.buf.bufid = bufid
  return self
end

function InComingCall:generate_call_graph()
  local params = vim.lsp.util.make_position_params()
  local func_name = vim.fn.expand("<cword>")
  local root_text = make_node_key(params.textDocument.uri, params.position.line, func_name)
  self.root_node = make_graph_node(root_text, { params = params })
  regist_node(self, root_text, self.root_node)
  self.pending_request = self.pending_request + 1
  genrate_call_graph_from_node(self, self.root_node, 1)
end

return InComingCall
