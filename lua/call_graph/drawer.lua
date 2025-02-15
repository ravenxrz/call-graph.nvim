local GraphDrawer = {}

local log = require("call_graph.utils.log")

---@class GraphDrawer
-- Module for drawing graphs in Neovim buffers.
--- Creates a new GraphDrawer instance.
---@param bufnr integer The buffer number to draw the graph in.
---@return GraphDrawer
function GraphDrawer:new(bufnr)
  local self = {
    bufnr = bufnr,
    node_positions = {}, -- { [node_id: integer]: {row: integer, col: integer} }
    row_spacing = 3,
    col_spacing = 5,
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

local function draw_node(self, node, row, col, level)
  if self.node_positions[node.nodeid] then -- drawed before
    return
  end
  ensure_buffer_has_lines(self, row + 1)
  ensure_buffer_line_has_cols(self, row, col + #node.text)
  vim.api.nvim_buf_set_text(self.bufnr, row, col, row, col + #node.text, { node.text })
  self.node_positions[node.nodeid] = { row = row, col = col, level = level }
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

local function draw_edge(self, lhs, rhs, lhs_level_max_col)
  local lhs_pos = self.node_positions[lhs.nodeid]
  local rhs_pos = self.node_positions[rhs.nodeid]
  assert(lhs_pos.col <= rhs_pos.col, string.format("lhs_col: %d, rhs_col: %d", lhs_pos.col, rhs_pos.col))
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
    local lhs_end_col = lhs_pos.col + #lhs.text
    local rhs_start_col = rhs_pos.col
    local mid_col = math.max(math.floor((lhs_end_col + rhs_start_col) / 2), lhs_level_max_col + 1)

    -- 绘制lhs到中间列的水平线
    if mid_col > lhs_end_col then
      draw_h_line(self, lhs_pos.row, lhs_end_col, mid_col, Direction.LEFT)
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
    if rhs_start_col > mid_col then
      draw_h_line(self, rhs_pos.row, mid_col, rhs_start_col)
    end
  end
end

function GraphDrawer:draw(root_node)
  local queue = { { node = root_node, level = 1 } } -- for bfs
  local cur_level = 1
  local cur_level_nodes = {}
  local cur_level_max_col = {}
  local cur_row = 0
  local cur_col = 0
  assert(self.col_spacing >= 5)

  -- 第一轮：绘制所有节点
  drawed = {}
  ::continue::
  while #queue > 0 do
    local current = table.remove(queue, 1)
    if drawed[current.node.node_id] then
      goto continue
    end
    drawed[current.node.nodeid] = true

    local node_level = current.level
    local cur_node = current.node

    if cur_level ~= node_level then
      -- draw pre level nodes
      for _, n in ipairs(cur_level_nodes) do
        draw_node(self, n.node, n.row, n.col, cur_level)
      end
      -- update this level position
      cur_row = 0
      cur_col = self.col_spacing + cur_level_max_col[cur_level]
      cur_level = node_level
      cur_level_max_col[cur_level] = cur_col + #cur_node.text
      cur_level_nodes = { { node = cur_node, level = node_level, row = cur_row, col = cur_col } }
    else
      table.insert(cur_level_nodes, { node = cur_node, level = node_level, row = cur_row, col = cur_col })
      cur_level_max_col[cur_level] = math.max(cur_level_max_col[cur_level] or 0, cur_col + #cur_node.text)
    end
    cur_row = cur_row + self.row_spacing

    -- push bfs next level
    for _, child in ipairs(cur_node.children) do
      if not drawed[child.nodeid] then
        table.insert(queue, { node = child, level = node_level + 1 })
      end
    end
  end
  for _, n in ipairs(cur_level_nodes) do
    draw_node(self, n.node, n.row, n.col)
  end
  cur_level_nodes = nil

  -- 第二轮：绘制所有边
  drawed = {}
  local function traverse(node)
    for _, child in ipairs(node.children) do
      if not drawed[child.nodeid] then
        drawed[node.nodeid] = true
        local level = self.node_positions[node.nodeid].level
        draw_edge(self, node, child, cur_level_max_col[level])
        traverse(child)
      end
    end
  end
  traverse(root_node)
end

return GraphDrawer

