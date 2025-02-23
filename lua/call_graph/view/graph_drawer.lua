-- NOTE: 自实现的所有绘图函数采用左开右闭的区间描述
local GraphDrawer = {}
local Edge = require("call_graph.class.edge")
local SubEdge = require("call_graph.class.subedge")
local log = require("call_graph.utils.log")
---@class GraphDrawer
-- Module for drawing graphs in Neovim buffers.
--- Creates a new GraphDrawer instance.
---@param bufnr integer The buffer number to draw the graph in.
---@return GraphDrawer
function GraphDrawer:new(bufnr, draw_edge_cb)
  local g = {
    bufnr = bufnr,
    row_spacing = 3,
    col_spacing = 5,
    draw_edge_cb = draw_edge_cb, --- @type table {cb = func, cb_ctx: any}
    modifiable = true
  }
  setmetatable(g, { __index = GraphDrawer })
  return g
end

function GraphDrawer:set_modifiable(enable)
  self.modifiable = enable
  vim.api.nvim_set_option_value("modifiable", enable, { buf = self.bufnr })
end

function GraphDrawer:clear_buf()
  local enable = self.modifiable
  if not enable then
    self:set_modifiable(true)
  end
  local bufid = self.bufnr
  vim.api.nvim_buf_set_lines(bufid, 0, -1, false, {})
  if not enable then
    self:set_modifiable(false)
  end
end

-- 确保缓冲区有足够的行
---@param self
---@param target_line_cnt integer, row number, zero-based indexing, inclusive
local function ensure_buffer_has_lines(self, target_line_cnt)
  local line_count = vim.api.nvim_buf_line_count(self.bufnr)
  if target_line_cnt > line_count then
    local new_lines = {}
    for _ = line_count + 1, target_line_cnt do
      table.insert(new_lines, "")
    end
    vim.api.nvim_buf_set_lines(self.bufnr, line_count, -1, false, new_lines)
  end
end

-- 确保缓冲区行有足够的列
---@param self
---@param line integer, row number, zoer-based indexing , inclusive
---@param required_col integer, column number, zero-based indexing, exclusive
local function ensure_buffer_line_has_cols(self, line, required_col)
  local line_text = vim.api.nvim_buf_get_lines(self.bufnr, line, line + 1, false)[1] or ""
  local line_length = #line_text
  if required_col > line_length then
    local padding = string.rep(" ", required_col - line_length)
    vim.api.nvim_buf_set_text(self.bufnr, line, line_length, line, line_length, { padding })
  end
end

local function draw_node(self, node)
  if node.panted then
    return
  end
  node.panted = true
  ensure_buffer_has_lines(self, node.row + 1)
  ensure_buffer_line_has_cols(self, node.row, node.col + #node.text)
  vim.api.nvim_buf_set_text(self.bufnr, node.row, node.col, node.row, node.col + #node.text, { node.text })
end


---@class Direction
local Direction = {
  UP = "up",
  DOWN = "down",
  LEFT = "left",
  RIGHT = "right",
}

--- @param start_row integer, start row
--- @param end_row integer, exclusive
--- @param col integer, column
--- @param direction string, which direction
local function draw_v_line(self, start_row, end_row, col, direction)
  assert(start_row <= end_row, string.format("start_row: %d, end_row: %d", start_row, end_row))

  ensure_buffer_has_lines(self, end_row)

  for line = start_row, end_row - 1 do
    ensure_buffer_line_has_cols(self, line, col + 1)

    -- 获取当前行的文本
    local current_line = vim.api.nvim_buf_get_lines(self.bufnr, line, line + 1, false)[1] or ""
    local current_char = string.sub(current_line, col + 1, col + 1) or ""

    -- 只有当当前字符为空字符串时才进行覆盖
    if current_char == " " or current_char == '|' then
      -- 处理箭头样式
      local fill = "|"
      if direction == Direction.UP and line == start_row then
        fill = "^"
      elseif direction == Direction.DOWN and line == end_row - 1 then
        fill = "v"
      end
      vim.api.nvim_buf_set_text(self.bufnr, line, col, line, col + 1, { fill })
    end
  end
end

--- @param row integer, which row
--- @param start_col integer, start of col
--- @param end_col integer, end of cold , exclusive
--- @param direction string, which direction
local function draw_h_line(self, row, start_col, end_col, direction)
  assert(start_col <= end_col, string.format("start_col: %d, end_col: %d", start_col, end_col))

  local length = end_col - start_col
  if length <= 0 then return end

  ensure_buffer_has_lines(self, row + 1)
  ensure_buffer_line_has_cols(self, row, end_col)

  -- 获取当前行的文本
  local current_line = vim.api.nvim_buf_get_lines(self.bufnr, row, row + 1, false)[1] or ""
  local fill_table = {}
  for i = start_col, end_col - 1 do
    local current_char = string.sub(current_line, i + 1, i + 1) or ""
    if current_char == " " or current_char == "-" then
      local fill = "-"
      if direction == Direction.LEFT and i == start_col then
        fill = "<"
      elseif direction == Direction.RIGHT and i == end_col - 1 then
        fill = ">"
      end
      table.insert(fill_table, fill)
    else
      table.insert(fill_table, current_char) -- 保留当前字符
    end
  end

  local fill = table.concat(fill_table)
  vim.api.nvim_buf_set_text(self.bufnr, row, start_col, row, end_col, { fill })
end

---@param sub_edges table<SubEdge>
local function call_draw_edge_cb(self, from_node, to_node, sub_edges)
  if self.draw_edge_cb ~= nil then
    local edge = Edge:new(from_node, to_node, nil, sub_edges)
    self.draw_edge_cb.cb(edge, self.draw_edge_cb.cb_ctx)
  end
end

local function draw_edge(self, lhs, rhs, point_to_lhs, lhs_level_max_col)
  assert(lhs.col <= rhs.col, string.format("lhs.col: %d, rhs.col: %d", lhs.col, rhs.col))
  local fill_start_col = 0
  local fill_start_row = 0
  local fill_end_col = 0
  local fill_end_row = 0

  local sub_edges = {}
  -- 是否是同一行
  if lhs.row == rhs.row then
    table.insert(sub_edges, SubEdge:new(lhs.row, lhs.col + #lhs.text, lhs.row + 1, rhs.col))
    if point_to_lhs then
      log.debug(string.format(
        "draw h line(point to lhs), lhs %s, rhs %s, row %d, from col %d to col %d", lhs.text, rhs.text,
        lhs.row, lhs.col + #lhs.text, rhs.col))
      draw_h_line(self, lhs.row, lhs.col + #lhs.text, rhs.col, Direction.LEFT)
      call_draw_edge_cb(self, rhs, lhs, sub_edges)
    else
      log.debug(string.format(
        "draw h line(point to rhs), lhs %s, rhs %s, row %d, from col %d to col %d", lhs.text, rhs.text,
        lhs.row, lhs.col + #lhs.text, rhs.col))
      draw_h_line(self, lhs.row, lhs.col + #lhs.text, rhs.col, Direction.RIGHT)
      call_draw_edge_cb(self, lhs, rhs, sub_edges)
    end
    return
  end

  --是否是同一列
  if lhs.col == rhs.col then
    assert(lhs.row ~= rhs.row, "lhs.row: %d, rhs.row: %d", lhs.row, rhs.row)
    if lhs.row < rhs.row then
      log.debug(string.format(
        "draw v line(point to lhs), lhs %s, rhs %s, col %d, from row %d to row %d", lhs.text, rhs.text,
        lhs.col, lhs.row + 1, rhs.row))
      draw_v_line(self, lhs.row + 1, rhs.row, lhs.col, Direction.UP)
      table.insert(sub_edges, SubEdge:new(lhs.row + 1, lhs.col, rhs.row, rhs.col + 1))
    else
      log.debug(string.format(
        "draw v line (point to rhs), lhs %s, rhs %s, col %d, from row %d to row %d", lhs.text, rhs.text,
        lhs.col, rhs.row + 1, lhs.row))
      draw_v_line(self, rhs.row + 1, lhs.row, lhs.col, Direction.DOWN)
      table.insert(sub_edges, SubEdge:new(rhs.row + 1, lhs.col, lhs.row, rhs.col + 1))
    end
    if point_to_lhs then
      call_draw_edge_cb(self, rhs, lhs, sub_edges)
    else
      call_draw_edge_cb(self, lhs, rhs, sub_edges)
    end
    return
  end

  -- 处理不同行不同列的情况：绘制L型连线
  local lhs_end_col = lhs.col + #lhs.text
  local rhs_start_col = rhs.col
  local mid_col = math.max(math.floor((lhs_end_col + rhs_start_col) / 2), lhs_level_max_col + 1) + 1

  -- 绘制lhs到中间列的水平线
  assert(mid_col > lhs_end_col, string.format("mid_col: %d, lhs_end_col: %d", mid_col, lhs_end_col))
  table.insert(sub_edges, SubEdge:new(lhs.row, lhs_end_col, lhs.row + 1, mid_col))
  if point_to_lhs then
    log.debug(string.format(
      "draw h line from lhs to mid col, (point to lhs), lhs %s, rhs %s, row %d, from col %d to col %d", lhs.text,
      rhs.text,
      lhs.row, lhs_end_col, mid_col))
    draw_h_line(self, lhs.row, lhs_end_col, mid_col, Direction.LEFT)
  else
    log.debug(string.format(
      "draw h line from lhs to mid col (point to rhs), lhs %s, rhs %s, row %d, from col %d to col %d", lhs.text, rhs
      .text,
      lhs.row, lhs_end_col, mid_col))
    draw_h_line(self, lhs.row, lhs_end_col, mid_col)
  end

  -- 绘制中间列的垂直线
  local v_start = math.min(lhs.row, rhs.row)
  local v_end = math.max(lhs.row, rhs.row)
  assert(v_start ~= v_end, "v_start: %d, v_end: %d", v_start, v_end)
  log.debug(string.format("draw v line, v_start: %d, v_end: %d, mid_col: %d", v_start, v_end, mid_col - 1))
  draw_v_line(self, v_start + 1, v_end, mid_col - 1)
  table.insert(sub_edges, SubEdge:new(v_start + 1, mid_col - 1, v_end, mid_col))

  -- 绘制中间列到rhs左侧的水平线
  assert(mid_col < rhs_start_col, string.format("mid_col: %d, rhs_start_col: %d", mid_col, rhs_start_col))
  table.insert(sub_edges, SubEdge:new(rhs.row, mid_col - 1, rhs.row + 1, rhs_start_col))
  if point_to_lhs then
    log.debug(string.format(
      "draw h line from mid col to rhs, (point to lhs), lhs %s, rhs %s, row %d, from col %d to col %d", lhs.text,
      rhs.text,
      rhs.row, mid_col - 1, rhs_start_col))
    draw_h_line(self, rhs.row, mid_col - 1, rhs_start_col)
    call_draw_edge_cb(self, rhs, lhs, sub_edges)
  else
    log.debug(string.format(
      "draw h line from mid col to rhs, (point to rhs), lhs %s, rhs %s, row %d, from col %d to col %d", lhs.text,
      rhs.text,
      rhs.row, mid_col - 1, rhs_start_col))
    draw_h_line(self, rhs.row, mid_col - 1, rhs_start_col, Direction.RIGHT)
    call_draw_edge_cb(self, lhs, rhs, sub_edges)
  end
end

---
---@param root_node GraphNode
function GraphDrawer:draw(root_node)
  local queue = { root_node } -- for bfs
  local cur_level = 1
  local cur_level_nodes = {}
  local cur_level_max_col = {}
  local cur_row = 0
  local cur_col = 0
  assert(self.col_spacing >= 5)

  -- 第一轮：绘制所有节点
  local added = {}
  added[root_node.nodeid] = true
  while #queue > 0 do
    local current = table.remove(queue, 1)

    if cur_level ~= current.level then
      -- draw pre level nodes
      for _, n in ipairs(cur_level_nodes) do
        draw_node(self, n)
      end
      -- uadate this level position
      cur_row = 0
      cur_col = self.col_spacing + cur_level_max_col[cur_level]
      cur_level = current.level
      cur_level_nodes = {}
      log.debug("level", cur_level, "start col", cur_col, "the first node", current.text)
    end
    current.row = cur_row
    current.col = cur_col
    log.debug("set node pos", current.text, "level", current.level, "row", current.row, "col", current.col)
    table.insert(cur_level_nodes, current)
    cur_level_max_col[cur_level] = math.max(cur_level_max_col[cur_level] or 0, cur_col + #current.text)
    cur_row = cur_row + self.row_spacing

    -- push bfs next level
    for _, child in ipairs(current.children) do
      if not added[child.nodeid] then
        added[child.nodeid] = true
        child.level = current.level + 1
        table.insert(queue, child)
      end
    end
  end
  for _, n in ipairs(cur_level_nodes) do
    draw_node(self, n)
  end
  cur_level_nodes = nil

  -- 第二轮：绘制所有边
  local visit = {}
  local function traverse(node)
    log.debug("traverse of node", node.text, "node id", node.nodeid)
    visit[node.nodeid] = true
    log.debug("mark node", node.text, "node id", node.nodeid, "visited")
    for _, child in ipairs(node.children) do
      log.debug("child of node", node.text, "node id", node.nodeid, "child", child.text, "node id", child.nodeid,
        "draw edge between", node.text, child.text,
        string.format("row %d col %d, row %d col %d", node.row, node.col, child.row, child.col))
      -- if node.text == child.text then
      --   log.warn("node", node.text, "node id", node.nodeid, "has same text with child", child.text, "node id")
      --   child.text = string.format("%s[%d]", child.text, child.nodeid) -- TODO: this will invalidate edge between `node` and `child`
      -- end

      if node.col <= child.col then
        draw_edge(self, node, child, true, cur_level_max_col[node.level])
      else
        draw_edge(self, child, node, false, cur_level_max_col[child.level])
      end
      if not visit[child.nodeid] then
        traverse(child)
      end
    end
    visit[node.nodeid] = false
    log.debug("unmark node", node.text, "node id", node.nodeid, "visited")
  end
  traverse(root_node)
  log.debug("draw graph done")
end

return GraphDrawer
