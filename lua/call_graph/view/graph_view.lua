-- graph_view.lua
-- 负责监听用户事件，高亮边，节点，浮动窗口等绘制
local log = require("call_graph.utils.log")
local Events = require("call_graph.utils.events")

local CallGraphView = {
  view_id = 1,
}
CallGraphView.__index = CallGraphView

function CallGraphView:new(hl_delay_ms, toogle_hl)
  local defaultConfig = {
    buf = {
      bufid = -1,
      graph = nil,
    },
    namespace_id = vim.api.nvim_create_namespace("call_graph"), -- for highlight
    hl_delay_ms = hl_delay_ms or 200,
    toggle_auto_hl = toogle_hl,
    last_hl_time_ms = 0,
    ext_marks_id = {
      edge = {},
    },
    view_id = self.view_id,
  }
  self.view_id = self.view_id + 1
  local o = setmetatable(defaultConfig, CallGraphView)
  return o
end

local function clear_all_hl_edge(self)
  log.debug("clear all edges, ", vim.inspect(self.ext_marks_id))
  vim.api.nvim_buf_clear_namespace(self.buf.bufid, self.namespace_id, 0, -1)
  self.ext_marks_id.edge = {}
end

local function clear_all_lines(self)
  local line_count = vim.api.nvim_buf_line_count(self.buf.bufid)
  vim.api.nvim_buf_set_lines(self.buf.bufid, 0, line_count, false, {})
end

function CallGraphView:clear_view()
  if self.buf.graph then
    self.buf.graph:set_modifiable(true)
    clear_all_lines(self)
    clear_all_hl_edge(self)
    self.buf.graph:set_modifiable(false)
  end
  self.last_hl_time_ms = 0
  self.ext_marks_id = {
    edge = {},
  }
end

function CallGraphView:set_hl_delay_ms(delay_ms)
  self.hl_delay_ms = delay_ms
end

function CallGraphView:set_toggle_auto_hl(toggle)
  self.toggle_auto_hl = toggle
end

function CallGraphView:reuse_buf(bufid)
  self.buf.bufid = bufid
end

local function hl_edge(self, edge)
  if edge.sub_edges == nil then
    log.error("hl: find nil sub edges", edge:to_string())
    return false
  end
  for _, sub_edge in pairs(edge.sub_edges) do
    -- hl by line
    for i = sub_edge.start_row, sub_edge.end_row - 1 do
      local id = vim.api.nvim_buf_set_extmark(self.buf.bufid, self.namespace_id, i, sub_edge.start_col, {
        end_row = i,
        end_col = sub_edge.end_col,
        hl_group = "CallGraphLine",
      })
      log.debug("sub edge", sub_edge:to_string(), "id", id)
      table.insert(self.ext_marks_id.edge, id)
    end
  end
  return true
end

local function overlap_node(row, col, node)
  return node.row == row and node.col <= col and col < node.col + #node.text
end

local function overlap_edge(row, col, edge)
  for _, sub_edge in ipairs(edge.sub_edges) do
    if
      (row == sub_edge.start_row and sub_edge.start_col <= col and col < sub_edge.end_col)
      or (col == sub_edge.start_col and sub_edge.start_row <= row and row < sub_edge.end_row)
    then
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
    if edge.sub_edges ~= nil then
      if overlap_edge(row, col, edge) then
        table.insert(overlaps_edges, edge)
      else
        log.error("find a nil sub edges", edge:to_string())
      end
    end
  end
  return overlaps_edges
end

local function jumpto(pos_params)
  local uri = pos_params.textDocument.uri
  local line = pos_params.position.line + 1 -- Neovim 的行号从 0 开始
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
  -- 提取获取边文本的函数
  local function get_edge_text(edge)
    return edge.to_node.text .. "<-" .. edge.from_node.text
  end

  -- 构建选择项和跳转参数列表
  local function build_jump_choices(target_node)
    local jump_choice = {}
    local jump_item = {}

    -- 添加节点本身的跳转选项
    table.insert(jump_item, target_node.text)
    table.insert(jump_choice, target_node.usr_data.attr.pos_params)

    -- 收集入边
    for _, edge in ipairs(target_node.incoming_edges) do
      table.insert(jump_item, get_edge_text(edge))
      table.insert(jump_choice, edge.pos_params)
    end

    -- 收集出边
    for _, edge in ipairs(target_node.outcoming_edges) do
      table.insert(jump_item, get_edge_text(edge))
      table.insert(jump_choice, edge.pos_params)
    end

    return jump_item, jump_choice
  end

  -- 创建选择回调函数
  local function create_jump_callback(jump_choice)
    return function(_, idx)
      if idx == nil then
        return
      end
      local pos_params = jump_choice[idx]
      log.debug("Jumping to position based on selection")
      jumpto(pos_params)
    end
  end

  -- 处理重叠情况（节点或边）
  local function handle_overlap(items, choices)
    if #items == 1 then
      jumpto(choices[1])
    else
      local callback = create_jump_callback(choices)
      vim.ui.select(items, {}, callback)
    end
  end

  log.debug("user press", row, col)
  local nodes = ctx.nodes
  local edges = ctx.edges

  -- 检查是否与节点重叠
  log.debug("compare node")
  local overlaps_nodes = find_overlaps_nodes(nodes, row, col)
  if #overlaps_nodes ~= 0 then
    if #overlaps_nodes ~= 1 then
      assert(false, string.format("find overlaps nodes num is larger than 1: %d", #overlaps_nodes))
      return
    end
    local target_node = overlaps_nodes[1]
    log.debug("pos overlaps with node", target_node.text)

    -- 构建选择项和跳转参数列表
    local jump_item, jump_choice = build_jump_choices(target_node)
    handle_overlap(jump_item, jump_choice)
    return
  end

  -- 检查是否与边重叠
  local overlaps_edges = find_overlaps_edges(edges, row, col)
  if #overlaps_edges ~= 0 then
    local edge_items = {}
    local edge_choices = {}
    for _, edge in ipairs(overlaps_edges) do
      table.insert(edge_items, get_edge_text(edge))
      table.insert(edge_choices, edge.pos_params)
    end
    handle_overlap(edge_items, edge_choices)
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
    for _, edge in ipairs(node.incoming_edges) do
      table.insert(callers, "- " .. edge.from_node.text)
    end
    return callers
  end

  -- node calls who?
  local get_callees = function(node)
    local callees = {}
    for _, edge in ipairs(node.outcoming_edges) do
      table.insert(callees, " - " .. edge.to_node.text)
    end
    return callees
  end

  -- overlap with nodes?
  log.debug("compare node")
  local overlaps_nodes = find_overlaps_nodes(nodes, row, col)
  if #overlaps_nodes ~= 0 then -- find node
    if #overlaps_nodes ~= 1 then
      vim.notify(
        string.format("find overlap nodes num is not 1, skip show full path, actual num %d", #overlaps_nodes),
        vim.log.levels.WARN
      )
      return
    end
    local target_node = overlaps_nodes[1]
    local fnode = target_node.usr_data
    local pos_params = fnode.attr.pos_params
    local uri = pos_params.textDocument.uri
    local line = pos_params.position.line + 1 -- Neovim 的行号从 0 开始
    local character = pos_params.position.character -- Neovim 的列号从 1 开始
    local file_path = vim.uri_to_fname(uri)
    local text = string.format("%s:%d:%d", file_path, line, character)
    local callers = get_callers(target_node)
    if #callers ~= 0 then
      text = string.format("%s\ncallers(%d)\n%s", text, #callers, table.concat(callers, "\n"))
    end
    local callees = get_callees(target_node)
    if #callees ~= 0 then
      text = string.format("%s\ncalls(%d)\n%s", text, #callees, table.concat(callees, "\n"))
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
  self.last_hl_time_ms = now
  -- clear hl, redraw hl
  clear_all_hl_edge(self)
  -- check node
  local nodes = ctx.nodes
  local overlaps_nodes = find_overlaps_nodes(nodes, row, col)
  log.info("find overlap node num", #overlaps_nodes)
  if #overlaps_nodes ~= 0 then -- find node
    if #overlaps_nodes ~= 1 then
      log.warn("find overlaps nodes num is not 1, use the first node as default")
    end
    local target_node = overlaps_nodes[1]
    log.info(
      string.format(
        "row:%d col:%d overlap with node:%s node position:%d,%d,%d,%d",
        row,
        col,
        target_node.text,
        target_node.row,
        target_node.col,
        target_node.row + 1,
        target_node.col + #target_node.text
      )
    )
    -- hl incoming
    for _, edge in pairs(target_node.incoming_edges) do
      if not hl_edge(self, edge) then
        log.error("highlight edge of node", target_node.text, "incoming edges", edge:to_string())
      end
    end
    -- hl outcoming
    for _, edge in pairs(target_node.outcoming_edges) do
      if not hl_edge(self, edge) then
        log.error("highlight edge of node", target_node.text, "outcoming edges", edge:to_string())
      end
    end
    return
  end
  -- check edge
  local edges = ctx.edges
  log.info("find overlap edge num", #edges)
  local overlaps_edges = find_overlaps_edges(edges, row, col)
  if #overlaps_edges ~= 0 then
    for _, edge in ipairs(overlaps_edges) do
      log.info(string.format("row:%d col:%d overlap with edge:%s", row, col, edge:to_string()))
      hl_edge(self, edge)
    end
  end
end

--- update edge subedge info
---@param edge Edge
local function draw_edge_cb(edge, ctx)
  log.info("draw edge cb", edge:to_string())
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
  if target_e == nil then
    log.error("not find edge", edge:to_string(), "in global edges")
    assert(target_e ~= nil, "not found edge from drawer in view")
  end
  target_e.sub_edges = edge.sub_edges
  log.info("setup edge", target_e:to_string(), "sub edges")
end

local function setup_buf(self, nodes, edges)
  Events.regist_press_cb(self.buf.bufid, goto_event_cb, { nodes = nodes, edges = edges }, "gd")
  Events.regist_cursor_hold_cb(self.buf.bufid, cursor_hold_cb, { self = self, nodes = nodes, edges = edges })
  Events.regist_press_cb(self.buf.bufid, show_node_info, { self = self, nodes = nodes }, "K")
end

local function collect_nodes_and_edges(root_node)
  local nodes = {}
  local edges = {}
  local visited_nodes_incoming = {}
  local visited_nodes_outcoming = {}
  local visited_edges = {}
  local added_nodes = {}

  -- 辅助函数：添加节点到结果集
  local function add_node(node)
    if not added_nodes[node.nodeid] then
      table.insert(nodes, node)
      added_nodes[node.nodeid] = true
    end
  end

  -- 辅助函数：添加边到结果集
  local function add_edge(edge)
    if not visited_edges[edge.edgeid] then
      table.insert(edges, edge)
      visited_edges[edge.edgeid] = true
    end
  end

  -- 按照 incoming_edges 遍历
  local function traverse_incoming(node)
    if visited_nodes_incoming[node.nodeid] then
      return
    end
    visited_nodes_incoming[node.nodeid] = true
    add_node(node)

    for _, edge in ipairs(node.incoming_edges or {}) do
      add_edge(edge)
      traverse_incoming(edge.from_node)
    end
  end

  -- 按照 outcoming_edges 遍历
  local function traverse_outcoming(node)
    if visited_nodes_outcoming[node.nodeid] then
      return
    end
    visited_nodes_outcoming[node.nodeid] = true
    add_node(node)

    for _, edge in pairs(node.outcoming_edges or {}) do
      add_edge(edge)
      traverse_outcoming(edge.to_node)
    end
  end

  -- 先按 incoming_edges 遍历
  traverse_incoming(root_node)

  -- 再按 outcoming_edges 遍历
  traverse_outcoming(root_node)

  return nodes, edges
end

function CallGraphView:draw(root_node, reuse_buf)
  if root_node == nil then
    vim.notify("root node is empty", vim.log.levels.WARN)
    return
  end

  -- 检查 root_node 的入边和出边情况
  local has_incoming_edges = #(root_node.incoming_edges or {}) > 0
  local has_outcoming_edges = #(root_node.outcoming_edges or {}) > 0

  -- 断言同时有入边和出边的场景
  -- assert(not (has_incoming_edges and has_outcoming_edges),
  --   "Root node should have either incoming edges or outcoming edges, not both.")

  -- 从 root_node 中收集 nodes 和 edges
  local nodes, edges = collect_nodes_and_edges(root_node)

  local Drawer = require("call_graph.view.graph_drawer")
  self:clear_view() -- always redraw everything

  if reuse_buf and self.buf.bufid ~= -1 and vim.api.nvim_buf_is_valid(self.buf.bufid) then
    -- 复用已有缓冲区，不重新创建
  else
    self.buf.bufid = vim.api.nvim_create_buf(true, true)
  end

  local target_buf_name = root_node.text .. "-" .. tonumber(self.view_id)
  local full_path = vim.api.nvim_buf_get_name(self.buf.bufid)
  local file_name = vim.fn.fnamemodify(full_path, ":t")
  if file_name ~= target_buf_name then
    vim.api.nvim_buf_set_name(self.buf.bufid, target_buf_name)
  end
  setup_buf(self, nodes, edges)

  log.info("generate graph of", root_node.text)
  log.info("all edge info")
  for _, edge in ipairs(edges) do
    log.info("edge", edge:to_string())
  end

  self.buf.graph = Drawer:new(self.buf.bufid, {
    cb = draw_edge_cb,
    cb_ctx = { edges = edges },
  })
  self.buf.graph:set_modifiable(true)

  -- 根据入边和出边情况调用 draw 函数
  if has_incoming_edges then
    self.buf.graph:draw(root_node, true) -- 只有入边，使用传入边遍历
  else
    self.buf.graph:draw(root_node, false) -- 其余场景
  end

  vim.api.nvim_set_current_buf(self.buf.bufid)
  self.buf.graph:set_modifiable(false)
  return self.buf.bufid
end

return CallGraphView
