-- 负责监听用户事件，高亮边，节点，浮动窗口等绘制
local log = require("call_graph.utils.log")
local Events = require("call_graph.utils.events")

local CallGraphView = {}
CallGraphView.__index = CallGraphView

function CallGraphView:new(hl_delay_ms, toogle_hl)
  local defaultConfig = {
    buf = {
      bufid = -1,
    },
    namespace_id = vim.api.nvim_create_namespace('call_graph'), -- for highlight
    last_cursor_hold = {
      node = nil
    },
    hl_delay_ms = hl_delay_ms or 200,
    toggle_auto_hl = toogle_hl,
    last_hl_time_ms = 0,
    ext_marks_id = {
      edge = {}
    }
  }
  local o = setmetatable(defaultConfig, CallGraphView)
  return o
end

function CallGraphView:clear_view()
  self.last_cursor_hold = { node = nil }
  self.last_hl_time_ms = 0
  self.ext_marks_id = {
    edge = {}
  }
end

function CallGraphView:set_hl_delay_ms(delay_ms)
  self.hl_delay_ms = delay_ms
end

function CallGraphView:set_toggle_auto_hl(toggle)
  self.toggle_auto_hl = toggle
end

local function hl_edge(self, edge)
  for _, sub_edge in pairs(edge.sub_edges) do
    -- hl by line
    for i = sub_edge.start_row, sub_edge.end_row - 1 do
      local id = vim.api.nvim_buf_set_extmark(self.buf.bufid, self.namespace_id, i, sub_edge.start_col, {
        end_row = i,
        end_col = sub_edge.end_col,
        hl_group = "CallGraphLine"
      })
      log.debug("sub edge", sub_edge:to_string(), "id", id)
      table.insert(self.ext_marks_id.edge, id)
    end
  end
end

local function clear_all_hl_edge(self)
  log.debug("clear all edges, ", vim.inspect(self.ext_marks_id))
  for _, id in ipairs(self.ext_marks_id.edge) do
    vim.api.nvim_buf_del_extmark(self.buf.bufid, self.namespace_id, id)
  end
  self.ext_marks_id.edge = {}
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

local function find_overlaps_nodes(nodes, row, col)
  local overlaps_nodes = {}
  for _, node in pairs(nodes) do
    if overlap_node(row, col, node) then
      table.insert(overlaps_nodes, node)
    end
  end
  return overlaps_nodes
end

local function find_overlaps_edges(edges, row, col)
  local overlaps_edges = {}
  for _, edge in pairs(edges) do
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
  log.debug(string.format("goto :%s", vim.inspect(ctx)))
  log.debug("user press", row, col)
  local nodes = ctx.nodes
  local edges = ctx.edges
  -- overlap with nodes?
  log.debug("compare node")
  local overlaps_nodes = find_overlaps_nodes(nodes, row, col)
  if #overlaps_nodes ~= 0 then -- find node
    if #overlaps_nodes ~= 1 then
      assert(false, string.format("find overlaps nodes num is larger than 1", #overlaps_nodes))
      return
    end
    local target_node = overlaps_nodes[1]
    local fnode = target_node.usr_data
    local pos_params = fnode.attr.pos_params
    log.debug("pos overlaps with node", target_node.text)
    jumpto(pos_params)
    return
  end
  -- overlap with edges?
  local function jump_to_edge(edge)
    log.debug(string.format("pos overlaps with edge [%s->%s]", edge.from_node.text, edge.to_node.text))
    jumpto(edge.pos_params)
  end
  local overlaps_edges = find_overlaps_edges(edges, row, col)
  local on_choice = function(_, idx)
    if idx == nil then
      return
    end
    local edge = overlaps_edges[idx]
    jump_to_edge(edge)
  end
  local function get_edge_text(edge)
    local text = edge.to_node.text .. "<-" .. edge.from_node.text
    return text
  end
  if #overlaps_edges ~= 0 then
    if #overlaps_edges ~= 1 then
      -- build choice
      local edge_items = {}
      for _, edge in ipairs(overlaps_edges) do
        table.insert(edge_items, get_edge_text(edge))
      end
      vim.ui.select(edge_items, {}, on_choice)
      return
    end
    jump_to_edge(overlaps_edges[1])
  end
end

-- 创建悬浮窗口的函数
local function create_floating_window(cur_buf, text)
  -- 创建缓冲区
  local buf = vim.api.nvim_create_buf(false, true)
  -- 设置缓冲区内容
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, vim.split(text, "\n"))
  -- 计算窗口位置和大小
  local text_max_width = function()
    local max_width = 0
    for _, line in ipairs(vim.split(text, "\n")) do
      max_width = math.max(max_width, #line)
    end
    return max_width
  end
  local text_max_height = function()
    return #vim.split(text, "\n")
  end
  local width = text_max_width()
  local height = text_max_height()
  -- 打开悬浮窗口
  local config = {
    relative = "cursor",
    row = 1,
    col = 1,
    width = width,
    height = height,
    border = "rounded",
    style = "minimal",
  }
  local winid = vim.api.nvim_open_win(buf, false, config)
  vim.api.nvim_create_autocmd({ "CursorMoved", "BufLeave", "BufWipeout" }, {
    buffer = cur_buf,
    callback = function(_)
      if vim.api.nvim_win_is_valid(winid) then
        vim.api.nvim_win_close(winid, true)
      end
    end,
    desc = "Close floating window on cursor move",
  })
end

local function show_node_info(row, col, ctx)
  log.debug("user press", row, col)
  local self = ctx.self
  local nodes = ctx.nodes
  assert(self ~= nil, "")
  -- who calls this node
  local get_callers = function(node)
    local callers = {}
    for _, c in ipairs(node.children) do
      table.insert(callers, "- " .. c.text)
    end
    return callers
  end
  -- node calls who?
  local get_calls = function(node)
    local calls = {}
    for _, c in ipairs(node.calls) do
      table.insert(calls, " - " .. c.text)
    end
    return calls
  end
  -- overlap with nodes?
  log.debug("compare node")
  local overlaps_nodes = find_overlaps_nodes(nodes, row, col)
  if #overlaps_nodes ~= 0 then -- find node
    if #overlaps_nodes ~= 1 then
      vim.notify(string.format("find overlap nodes num is not 1, skip show full path, actual num", #overlaps_nodes),
        vim.log.levels.WARN)
      return
    end
    local target_node = overlaps_nodes[1]
    local fnode = target_node.usr_data
    local pos_params = fnode.attr.pos_params
    local uri = pos_params.textDocument.uri
    local line = pos_params.position.line + 1       -- Neovim 的行号从 0 开始
    local character = pos_params.position.character -- Neovim 的列号从 1 开始
    local file_path = vim.uri_to_fname(uri)
    local text = string.format("%s:%d:%d", file_path, line, character)
    local callers = get_callers(target_node)
    if #callers ~= 0 then
      text = string.format("%s\ncallers(%d)\n%s", text, #callers, table.concat(callers, '\n'))
    end
    log.info("target node show", vim.inspect(target_node))
    local callees = get_calls(target_node)
    if #callees ~= 0 then
      text = string.format("%s\ncalls(%d)\n%s", text, #callees, table.concat(callees, '\n'))
    end
    create_floating_window(self.buf.bufid, text)
    return
  end
end

local function cursor_hold_cb(row, col, ctx)
  local self = ctx.self
  if not self.toggle_auto_hl then
    return
  end
  local now = os.time() * 1000
  if now - self.last_hl_time_ms < self.hl_delay_ms then
    return
  end
  -- check overlap with last node or not
  if self.last_cursor_hold.node ~= nil and overlap_node(row, col, self.last_cursor_hold.node) then
    log.debug(string.format("row:%d col:%d overlap with node:%s, node position:%d,%d,%d,%d", row, col,
      self.last_cursor_hold.node.text, self.last_cursor_hold.node.row, self.last_cursor_hold.node.col,
      self.last_cursor_hold.node.row + 1,
      self.last_cursor_hold.node.col + #self.last_cursor_hold.node.text))
    return
  end
  self.last_cursor_hold.node = nil
  self.last_hl_time_ms = now
  -- clear hl, redraw hl
  clear_all_hl_edge(self)
  -- check node
  local nodes = ctx.nodes
  local overlaps_nodes = find_overlaps_nodes(nodes, row, col)
  if #overlaps_nodes ~= 0 then -- find node
    if #overlaps_nodes ~= 1 then
      log.warn("find overlaps nodes num is not 1, use the first node as default")
    end
    local target_node = overlaps_nodes[1]
    log.debug(string.format("row:%d col:%d overlap with node:%s node position:%d,%d,%d,%d", row, col, target_node.text,
      target_node
      .row, target_node.col, target_node.row + 1, target_node.col + #target_node.text))
    self.last_cursor_hold.node = target_node
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
  local edges = ctx.edges
  local overlaps_edges = find_overlaps_edges(edges, row, col)
  if #overlaps_edges ~= 0 then
    for _, edge in ipairs(overlaps_edges) do
      log.debug(string.format("row:%d col:%d overlap with edge:%s", row, col, edge:to_string()))
      hl_edge(self, edge)
    end
  end
end

--- update edge subedge info
---@param edge Edge
local function draw_edge_cb(edge, ctx)
  local dst_edges = ctx.edges
  -- TODO(zhangxingrui): this is really slow, O(n^2)
  local function find_edge(e)
    for _, dst_edge in ipairs(dst_edges) do
      if e:is_same_edge(dst_edge) then
        return dst_edge
      end
    end
    return nil
  end
  local target_e = find_edge(edge)
  assert(target_e ~= nil, "not found edge from drawer in view")
  target_e.sub_edges = edge.sub_edges
end

local function setup_buf(self, nodes, edges)
  Events.regist_press_cb(self.buf.bufid, goto_event_cb, { nodes = nodes, edges = edges }, "gd")
  Events.regist_cursor_hold_cb(self.buf.bufid, cursor_hold_cb, { self = self,  nodes = nodes, edges = edges })
  Events.regist_press_cb(self.buf.bufid, show_node_info, { self = self, nodes = nodes }, "K")
end

function CallGraphView:draw(root_node, nodes, edges)
  local Drawer = require("call_graph.graph_drawer")
  if self.buf.bufid == -1 or not vim.api.nvim_buf_is_valid(self.buf.bufid) then
    self.buf.bufid = vim.api.nvim_create_buf(true, true)
  end
  setup_buf(self, nodes, edges)
  log.info("genrate graph of", root_node.text, "has child num", #root_node.children)
  local graph = Drawer:new(self.buf.bufid,
    {
      cb = draw_edge_cb,
      cb_ctx = { edges = edges }
    }
  )
  graph:set_modifiable(true)
  graph:draw(root_node) -- draw函数完成node在buf中的位置计算（后续可在`goto_event_cb`中判定跳转到哪个node), 和node与edge绘制
  vim.api.nvim_set_current_buf(self.buf.bufid)
  graph:set_modifiable(false)
end

return CallGraphView
