local Node = require("call_graph.class.node")
local Edge = require("call_graph.class.edge")
local FilePos = require("call_graph.class.file_pos")

local GraphDrawer = {}

---@class GraphDrawer
-- Module for drawing graphs in Neovim buffers.
--- Creates a new GraphDrawer instance.
---@param bufnr integer The buffer number to draw the graph in.
---@return GraphDrawer
function GraphDrawer:new(bufnr)
  local self = {
    bufnr = bufnr,
    node_positions = {}, -- { [node_id: integer]: {row: integer, col: integer} }
  }
  setmetatable(self, { __index = GraphDrawer })
  return self
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

-- 绘制节点
local function draw_node(self, node, row, col)
  if self.node_positions[node.nodeid] then -- drawed before
    return
  end
  ensure_buffer_has_lines(self, row + 1)
  ensure_buffer_line_has_cols(self, row, col + #node.text)
  vim.api.nvim_buf_set_text(self.bufnr, row, col, row, col + #node.text, { node.text })
  self.node_positions[node.nodeid] = { row = row, col = col }
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
--- @param direction Direction, which direction
local function draw_v_line(self, start_row, end_row, col, direction)
  assert(start_row <= end_row, string.format("start_row: %d, end_row: %d", start_row, end_row))
  ensure_buffer_has_lines(self, end_row)

  for line = start_row, end_row - 1 do
    ensure_buffer_line_has_cols(self, line, col)

    -- 处理箭头样式
    local fill = "|"
    if direction == Direction.UP and line == start_row then
      fill = "^"
    elseif direction == Direction.DOWN and line == end_row - 1 then
      fill = "v"
    end
    vim.api.nvim_buf_set_text(self.bufnr, line, col, line, col, { fill })
  end
end

--- @param row integer, which row
--- @param start_col integer, start of col
--- @param end_col integer, end of cold , exclusive
--- @param direction Direction, which direction
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

local function draw_edge(self, lhs, rhs)
  local lhs_pos = self.node_positions[lhs.nodeid]
  local rhs_pos = self.node_positions[rhs.nodeid]
  local h_direction = Direction.LEFT
  local v_direction = Direction.DOWN
  if lhs_pos.col > rhs_pos.col then
    lhs, rhs = rhs, lhs
    lhs_pos, rhs_pos = rhs_pos, lhs_pos
  end
  local fill_start_col = 0
  local fill_start_row = 0
  local fill_end_col = 0
  local fill_end_row = 0

  if lhs_pos and rhs_pos then
    -- 是否是同一行
    if lhs_pos.row == rhs_pos.row then
      fill_start_row = lhs_pos.row
      fill_start_col = lhs_pos.col + #lhs.text
      fill_end_row = rhs_pos.row
      fill_end_col = rhs_pos.col
      draw_h_line(self, fill_start_row, fill_start_col, fill_end_col, Direction.LEFT)
      return
    end

    --是否是同一列
    if lhs_pos.col == rhs_pos.col then
      fill_start_row = lhs_pos.row + 1
      fill_start_col = lhs_pos.col
      fill_end_row = rhs_pos.row
      fill_end_col = rhs_pos.col
      draw_v_line(self, fill_start_row, fill_end_row, fill_start_col, Direction.UP)
      return
    end

    -- 处理不同行不同列的情况：绘制L型连线
    local parent_end_col = lhs_pos.col + #lhs.text
    local child_start_col = rhs_pos.col
    local mid_col = math.floor((parent_end_col + child_start_col) / 2)

    -- 绘制lhs到中间列的水平线
    if mid_col > parent_end_col then
      draw_h_line(self, lhs_pos.row, parent_end_col, mid_col, Direction.LEFT)
    end

    -- 绘制中间列的垂直线
    local v_start = lhs_pos.row + 1
    local v_end = rhs_pos.row
    if v_end > v_start then
      draw_v_line(self, v_start, v_end, mid_col)
    elseif v_end < v_start then
      -- 处理子节点在父节点上方的情况
      draw_v_line(self, v_end, v_start, mid_col)
    end

    -- 绘制中间列到rhs左侧的水平线
    if child_start_col > mid_col then
      draw_h_line(self, rhs_pos.row, mid_col, child_start_col)
    end
  end
end

-- TODO(zhangxingrui): 成环图处理
function GraphDrawer:draw(root_node)
  local queue = { { node = root_node, level = 1, row = 0, col = 0 } }
  local level_max_width = {} -- 记录每一级别的最大节点宽度
  local row_spacing = 4
  local col_spacing = 10
  assert(col_spacing >= 5)

  -- 第一轮：绘制所有节点并记录每一级别的最大宽度
  while #queue > 0 do
    local current = table.remove(queue, 1)
    local node = current.node
    local level = current.level
    local row = current.row
    local col = current.col

    -- 绘制当前节点
    draw_node(self, node, row, col)

    -- 更新该级别的最大宽度
    level_max_width[level] = math.max(level_max_width[level] or 0, #node.text)

    -- 处理子节点
    local next_col = col + level_max_width[level] + col_spacing
    local next_y = 0
    for _, child in ipairs(node.children) do
      table.insert(queue, { node = child, level = level + 1, row = next_y, col = next_col })
      next_y = next_y + row_spacing
    end
  end

  -- 第二轮：绘制所有边
  local function traverse(node)
    for _, child in ipairs(node.children) do
      draw_edge(self, node, child)
      traverse(child)
    end
  end
  traverse(root_node)
end

return GraphDrawer
