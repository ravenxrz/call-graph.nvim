local GraphDrawer = {}

local log = require("call_graph.utils.log")
local GraphNode = require("call_graph.class.graph_node")

---@class GraphDrawer
-- Module for drawing graphs in Neovim buffers.
--- Creates a new GraphDrawer instance.
---@param bufnr integer The buffer number to draw the graph in.
---@return GraphDrawer
function GraphDrawer:new(bufnr)
  local g = {
    bufnr = bufnr,
    row_spacing = 3,
    col_spacing = 5,
  }
  setmetatable(g, { __index = GraphDrawer })
  return g
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
  local fill
  if direction == Direction.LEFT then
    fill = "<" .. string.rep("-", math.max(length - 1, 0))
  elseif direction == Direction.RIGHT then
    fill = string.rep("-", math.max(length - 1, 0)) .. ">"
  else
    fill = string.rep("-", length)
  end
  vim.api.nvim_buf_set_text(self.bufnr, row, start_col, row, end_col, { fill })
end

local function draw_edge(self, lhs, rhs, point_to_lhs, lhs_level_max_col)
  assert(lhs.col <= rhs.col, string.format("lhs.col: %d, rhs.col: %d", lhs.col, rhs.col))
  local fill_start_col = 0
  local fill_start_row = 0
  local fill_end_col = 0
  local fill_end_row = 0

  -- 是否是同一行
  if lhs.row == rhs.row then
    if point_to_lhs then
      draw_h_line(self, lhs.row, lhs.col + #lhs.text, rhs.col, Direction.LEFT)
    else
      draw_h_line(self, lhs.row, lhs.col + #lhs.text, rhs.col, Direction.RIGHT)
    end
    return
  end

  --是否是同一列
  if lhs.col == rhs.col then
    assert(lhs.row ~= rhs.row, "lhs.row: %d, rhs.row: %d", lhs.row, rhs.row)
    if lhs.row < rhs.row then
      draw_v_line(self, lhs.row + 1, rhs.row, lhs.col, Direction.UP)
    else
      draw_v_line(self, rhs.row - 1, lhs.row, lhs.col, Direction.DOWN)
    end
    return
  end

  -- 处理不同行不同列的情况：绘制L型连线
  local lhs_end_col = lhs.col + #lhs.text
  local rhs_start_col = rhs.col
  local mid_col = math.max(math.floor((lhs_end_col + rhs_start_col) / 2), lhs_level_max_col + 1)

  -- 绘制lhs到中间列的水平线
  assert(mid_col > lhs_end_col,string.format("mid_col: %d, lhs_end_col: %d", mid_col, lhs_end_col))
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
  draw_v_line(self, v_start + 1, v_end, mid_col)

  -- 绘制中间列到rhs左侧的水平线
  assert(mid_col < rhs_start_col, string.format("mid_col: %d, rhs_start_col: %d", mid_col, rhs_start_col))
  if point_to_lhs then
    log.debug(vim.inspect((lhs)))
    log.debug(vim.inspect((rhs)))
    log.debug(string.format(
    "draw h line from mid col to rhs, (point to lhs), lhs %s, rhs %s, row %d, from col %d to col %d", lhs.text, rhs.text,
      rhs.row, mid_col, rhs_start_col))
    draw_h_line(self, rhs.row, mid_col, rhs_start_col)
  else
    log.debug(string.format(
    "draw h line from mid col to rhs, (point to rhs), lhs %s, rhs %s, row %d, from col %d to col %d", lhs.text, rhs.text,
      rhs.row, mid_col, rhs_start_col))
    draw_h_line(self, rhs.row, mid_col, rhs_start_col, Direction.RIGHT)
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
    for _, child in ipairs(node.children) do
      if not visit[child.nodeid] then
        log.debug("child of node", node.text, "node id", node.nodeid, "child", child.text, "node id", child.nodeid,
          "draw edge between", node.text, child.text,
          string.format("row %d col %d, row %d col %d", node.row, node.col, child.row, child.col))
        if node.col <= child.col then
          draw_edge(self, node, child, true, cur_level_max_col[node.level])  -- 环图只绘制一条边
        else
          draw_edge(self, child, node, false, cur_level_max_col[child.level]) -- 环图只绘制一条边
        end
        traverse(child)
      end
    end
    visit[node.nodeid] = false
  end
  traverse(root_node)
end

return GraphDrawer

