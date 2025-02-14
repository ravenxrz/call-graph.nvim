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
    node_positions = {}, -- { [node_id: interger]: {row: integer, col: integer} }
  }
  setmetatable(self, { __index = GraphDrawer })
  return self
end

-- 确保缓冲区有足够的行
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
  local msg = string.format("draw node:%s row:%d col:%d", node.text, row, col)
  print(msg)
  ensure_buffer_has_lines(self, row + 1)
  ensure_buffer_line_has_cols(self, row, col + #node.text)
  vim.api.nvim_buf_set_text(self.bufnr, row, col, row, col + #node.text, { node.text })
  self.node_positions[node.nodeid] = { row = row, col = col }
end

--- @param start_row start row
--- @param end_row exclusive
--- @param which column
local function draw_vertical_line(self, start_row, end_row, col)
  for line = start_row, end_row - 1 do
    vim.api.nvim_buf_set_text(self.bufnr, line, col, line, col, { "|" })
  end
end

local function draw_edge(self, parent, child)
  local parent_pos = self.node_positions[parent.nodeid]
  local child_pos = self.node_positions[child.nodeid]
  local fill_start_col = 0
  local fill_start_row = 0
  local fill_end_col = 0
  local fill_end_row = 0

  if parent_pos and child_pos then
    -- 确保起始行和结束行有足够的列
    local start_line = math.min(parent_pos.row, child_pos.row)
    local end_line = math.max(parent_pos.row, child_pos.row)
    local max_line_len = math.max(parent_pos.col + #parent.text, child_pos.col + #child.text)
    for line = start_line, end_line do
      -- local msg = string.format("handle line:%d, parent:%s child:%s", line, parent.text, child.text)
      -- print(msg)
      ensure_buffer_line_has_cols(self, line, max_line_len)
    end

    -- 是否是同一行
    if parent_pos.row == child_pos.row then
      fill_start_row = parent_pos.row
      fill_start_col = parent_pos.col + #parent.text
      fill_end_row = child_pos.row
      fill_end_col = child_pos.col
      local fill = string.rep("-", fill_end_col - fill_start_col) 
      vim.api.nvim_buf_set_text(self.bufnr, fill_start_row, fill_start_col, fill_end_row, fill_end_col, { fill })
    end

    --是否是同一列
    if parent_pos.col == child_pos.col then
      fill_start_row = parent_pos.row + 1
      fill_start_col = parent_pos.col
      fill_end_row = child_pos.row
      fill_end_col = child_pos.col
      draw_vertical_line(self, fill_start_row, fill_end_row, fill_start_col)
    end

    -- 都不是
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
