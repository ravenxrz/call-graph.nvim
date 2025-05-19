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
      graph = nil, -- This seems to be used for buffer specific graph state, might not be nodes/edges directly
    },
    namespace_id = vim.api.nvim_create_namespace("call_graph"), -- for edge highlight
    marked_node_namespace_id = vim.api.nvim_create_namespace("call_graph_marked_node"), -- for marked node highlight
    hl_delay_ms = hl_delay_ms or 200,
    toggle_auto_hl = toogle_hl,
    last_hl_time_ms = 0,
    ext_marks_id = {
      edge = {},
      marked_nodes = {}, -- To store extmark IDs for marked nodes if needed for individual clearing, though namespace clearing is easier
    },
    view_id = self.view_id,
    nodes_cache = {}, -- Cache for drawn nodes (map: nodeid -> node object)
    edges_cache = {}, -- Cache for drawn edges (list or map)
    drawer = nil, -- Will be set later by draw method for GraphDrawer instance
  }
  self.view_id = self.view_id + 1
  local o = setmetatable(defaultConfig, CallGraphView)
  return o
end

local function clear_all_hl_edge(self)
  if self.buf.bufid == -1 or not vim.api.nvim_buf_is_valid(self.buf.bufid) then
    log.debug("clear_all_hl_edge: buffer is invalid, skipping")
    return
  end

  log.debug("clear all edges, ", vim.inspect(self.ext_marks_id))
  vim.api.nvim_buf_clear_namespace(self.buf.bufid, self.namespace_id, 0, -1)
  self.ext_marks_id.edge = {}
end

-- New function to clear marked node highlights
function CallGraphView:clear_marked_node_highlights()
  if self.buf.bufid == -1 or not vim.api.nvim_buf_is_valid(self.buf.bufid) then
    log.debug("clear_marked_node_highlights: buffer is invalid, skipping")
    return
  end

  log.debug("Clearing marked node highlights")
  vim.api.nvim_buf_clear_namespace(self.buf.bufid, self.marked_node_namespace_id, 0, -1)
  self.ext_marks_id.marked_nodes = {} -- Reset if we were storing individual mark IDs
end

local function clear_all_lines(self)
  if self.buf.bufid == -1 or not vim.api.nvim_buf_is_valid(self.buf.bufid) then
    log.debug("clear_all_lines: buffer is invalid, skipping")
    return
  end

  local line_count = vim.api.nvim_buf_line_count(self.buf.bufid)
  vim.api.nvim_buf_set_lines(self.buf.bufid, 0, line_count, false, {})
end

function CallGraphView:clear_view()
  if self.buf.bufid ~= -1 and vim.api.nvim_buf_is_valid(self.buf.bufid) then
    if self.buf.graph then
      self.buf.graph:set_modifiable(true)
      clear_all_lines(self)
      clear_all_hl_edge(self)
      self:clear_marked_node_highlights()
      self.buf.graph:set_modifiable(false)
    else
      clear_all_lines(self)
      clear_all_hl_edge(self)
      self:clear_marked_node_highlights()
    end
  end

  self.last_hl_time_ms = 0
  self.ext_marks_id = {
    edge = {},
    marked_nodes = {},
  }

  -- 不要清除缓存，而是保留它们
  -- self.nodes_cache = {}
  -- self.edges_cache = {}
end

function CallGraphView:set_hl_delay_ms(delay_ms)
  self.hl_delay_ms = delay_ms
end

function CallGraphView:set_toggle_auto_hl(toggle)
  self.toggle_auto_hl = toggle
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
  for _, sub_edge in ipairs(edge.sub_edges or {}) do
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
  -- 将 URI 转换为文件路径
  local file_path = vim.uri_to_fname(uri)
  -- 打开文件
  vim.cmd("edit " .. file_path)
  -- 如果有位置信息，则跳转到指定位置
  if pos_params.position then
    local line = pos_params.position.line + 1 -- Neovim 的行号从 0 开始
    local character = pos_params.position.character -- Neovim 的列号从 1 开始
    vim.api.nvim_win_set_cursor(0, { line, character })
  end
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
    if target_node.usr_data and target_node.usr_data.attr and target_node.usr_data.attr.pos_params then
      table.insert(jump_item, target_node.text)
      table.insert(jump_choice, target_node.usr_data.attr.pos_params)
    else
      log.warn("Node is missing position parameters:", target_node.text)
      return {}, {}
    end

    -- 收集入边
    for _, edge in ipairs(target_node.incoming_edges or {}) do
      if edge.pos_params then
        table.insert(jump_item, get_edge_text(edge))
        table.insert(jump_choice, edge.pos_params)
      end
    end

    -- 收集出边
    for _, edge in ipairs(target_node.outcoming_edges or {}) do
      if edge.pos_params then
        table.insert(jump_item, get_edge_text(edge))
        table.insert(jump_choice, edge.pos_params)
      end
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
    if #items == 0 or #choices == 0 then
      log.warn("No valid items to jump to")
      return
    end

    if #items == 1 then
      jumpto(choices[1])
    else
      local callback = create_jump_callback(choices)
      vim.ui.select(items, {}, callback)
    end
  end

  log.debug("user press", row, col)
  local nodes = ctx.nodes or {}
  local edges = ctx.edges or {}
  log.debug("all nodes", vim.inspect(nodes))
  log.debug("all edges", vim.inspect(edges))

  -- 检查是否与节点重叠
  log.debug("compare node")
  local overlaps_nodes = find_overlaps_nodes(nodes, row, col)
  if #overlaps_nodes ~= 0 then
    if #overlaps_nodes ~= 1 then
      log.warn(string.format("find overlaps nodes num is larger than 1: %d, using first one", #overlaps_nodes))
      -- 继续处理第一个节点，而不是中断
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
    for _, edge in ipairs(overlaps_edges or {}) do
      if edge.pos_params then
        table.insert(edge_items, get_edge_text(edge))
        table.insert(edge_choices, edge.pos_params)
      end
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
  local self = ctx.self
  local nodes = ctx.nodes or {}
  log.debug("user press", row, col)
  log.debug("all nodes", vim.inspect(nodes))
  assert(self ~= nil, "")

  -- who calls this node
  local get_callers = function(node)
    local callers = {}
    for _, edge in ipairs(node.incoming_edges or {}) do
      table.insert(callers, "- " .. edge.from_node.text)
    end
    return callers
  end

  -- node calls who?
  local get_callees = function(node)
    local callees = {}
    for _, edge in ipairs(node.outcoming_edges or {}) do
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

    -- 安全检查usr_data属性
    if not fnode or not fnode.attr or not fnode.attr.pos_params then
      vim.notify("Node missing position data", vim.log.levels.WARN)
      return
    end

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
  local nodes = ctx.nodes or {}
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
    for _, edge in pairs(target_node.incoming_edges or {}) do
      if not hl_edge(self, edge) then
        log.error("highlight edge of node", target_node.text, "incoming edges", edge:to_string())
      end
    end
    -- hl outcoming
    for _, edge in pairs(target_node.outcoming_edges or {}) do
      if not hl_edge(self, edge) then
        log.error("highlight edge of node", target_node.text, "outcoming edges", edge:to_string())
      end
    end
    return
  end
  -- check edge
  local edges = ctx.edges or {}
  log.info("find overlap edge num", #edges)
  local overlaps_edges = find_overlaps_edges(edges, row, col)
  if #overlaps_edges ~= 0 then
    for _, edge in ipairs(overlaps_edges or {}) do
      log.info(string.format("row:%d col:%d overlap with edge:%s", row, col, edge:to_string()))
      hl_edge(self, edge)
    end
  end
end

--- update edge subedge info
---@param edge Edge
local function draw_edge_cb(edge, ctx)
  log.info("draw edge cb", edge:to_string())
  local dst_edges = ctx.edges or {}
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
    log.warn("Edge not found in global edges:", edge:to_string(), "- Skipping update of sub_edges")
    return -- 找不到边时跳过更新，而不是断言失败
  end
  target_e.sub_edges = edge.sub_edges
  log.info("setup edge", target_e:to_string(), "sub edges")

  -- 更新 edges_cache
  if ctx.self and ctx.self.edges_cache then
    for i, cached_edge in ipairs(ctx.self.edges_cache) do
      if cached_edge:is_same_edge(edge) then
        ctx.self.edges_cache[i].sub_edges = edge.sub_edges
        log.debug("Updated edge in edges_cache: ", vim.inspect(edge))
        break
      end
    end
  end
end

-- 将本地函数setup_buf改为对象方法
function CallGraphView:setup_buf(nodes, edges)
  nodes = nodes or {}
  edges = edges or {}
  Events.regist_press_cb(self.buf.bufid, goto_event_cb, { nodes = nodes, edges = edges }, "gd")
  Events.regist_cursor_hold_cb(self.buf.bufid, cursor_hold_cb, { self = self, nodes = nodes, edges = edges })
  Events.regist_press_cb(self.buf.bufid, show_node_info, { self = self, nodes = nodes }, "K")
end

local GraphDrawer = require("call_graph.view.graph_drawer")

--- draw the call graph
---@param root_node GraphNode 图的根节点
---@param traverse_by_incoming boolean 是否通过入边遍历图
function CallGraphView:draw(root_node, traverse_by_incoming)
  log.debug("view draw call. root_node: ", root_node and root_node.text or "nil")

  -- 清除当前视图
  self:clear_view()

  -- 从root_node开始遍历构建完整的节点和边集合
  local nodes_map = {}
  local edges_list = {}

  -- 递归收集所有可达的节点和边
  local function collect_nodes_and_edges(node, visited)
    if not node or visited[node.nodeid] then
      return
    end

    -- 标记当前节点为已访问
    visited[node.nodeid] = true
    -- 添加到节点集合
    nodes_map[node.nodeid] = node

    -- 获取要遍历的边
    local edges = traverse_by_incoming and node.incoming_edges or node.outcoming_edges

    -- 处理每条边
    for _, edge in ipairs(edges or {}) do
      -- 添加到边集合
      table.insert(edges_list, edge)

      -- 递归处理下一个节点
      local next_node = traverse_by_incoming and edge.from_node or edge.to_node
      collect_nodes_and_edges(next_node, visited)
    end

    -- 确保另一方向的边也被记录（虽然不用于遍历）
    local other_edges = traverse_by_incoming and node.outcoming_edges or node.incoming_edges
    for _, edge in ipairs(other_edges or {}) do
      -- 只添加边到集合，不递归遍历
      table.insert(edges_list, edge)
    end
  end

  -- 只有当root_node不为nil时才收集节点和边
  if root_node then
    collect_nodes_and_edges(root_node, {})
  end

  -- 缓存构建的节点和边数据
  self.nodes_cache = nodes_map
  self.edges_cache = edges_list

  -- 如果缓冲区无效或未创建，则创建新缓冲区
  if self.buf.bufid == -1 or not vim.api.nvim_buf_is_valid(self.buf.bufid) then
    log.info("Creating new buffer for graph view")
    self.buf.bufid = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(self.buf.bufid, "buftype", "nofile")
    vim.api.nvim_buf_set_option(self.buf.bufid, "buflisted", false)
    vim.api.nvim_buf_set_option(self.buf.bufid, "swapfile", false)
    vim.api.nvim_buf_set_option(self.buf.bufid, "modifiable", true)
    vim.api.nvim_buf_set_option(self.buf.bufid, "filetype", "callgraph")
  end

  -- 设置缓冲区名称
  local target_buf_name = (root_node and root_node.text or "CallGraph") .. "-" .. tonumber(self.view_id)
  vim.api.nvim_buf_set_name(self.buf.bufid, target_buf_name)

  -- 设置缓冲区事件处理
  self:setup_buf(nodes_map, edges_list)

  -- 创建图形绘制器
  self.buf.graph = GraphDrawer:new(self.buf.bufid, {
    cb = draw_edge_cb,
    cb_ctx = { edges = edges_list, self = self },
  })
  self.buf.graph:set_modifiable(true)

  -- 设置 GraphDrawer 的节点集
  self.buf.graph.nodes = self.nodes_cache

  -- 只有当root_node不为nil时才调用GraphDrawer的draw函数
  if root_node then
    self.buf.graph:draw(root_node, traverse_by_incoming)
  end

  -- 切换到当前缓冲区
  vim.api.nvim_set_current_buf(self.buf.bufid)
  self.buf.graph:set_modifiable(false)
  return self.buf.bufid
end

-- New function to get node at current cursor line
function CallGraphView:get_node_at_cursor()
  if
    self.buf.bufid == -1
    or not vim.api.nvim_buf_is_valid(self.buf.bufid)
    or vim.api.nvim_get_current_buf() ~= self.buf.bufid
  then
    log.warn("get_node_at_cursor: Not in the correct buffer or buffer invalid.")
    return nil
  end

  local cursor_pos = vim.api.nvim_win_get_cursor(0) -- {row, col}, 1-indexed
  local current_line_one_indexed = cursor_pos[1]
  local current_col_one_indexed = cursor_pos[2]
  local current_row_zero_indexed = current_line_one_indexed - 1

  if not self.nodes_cache then
    log.warn("get_node_at_cursor: nodes_cache is nil")
    return nil
  end

  for _, node in pairs(self.nodes_cache) do -- nodes_cache is a map {nodeid = node_obj}
    if
      node.row == current_row_zero_indexed
      and current_col_one_indexed >= node.col
      and current_col_one_indexed < node.col + #node.text
    then
      log.debug(
        string.format(
          "Node found at line %d, col %d: %s (ID: %d)",
          current_line_one_indexed,
          current_col_one_indexed,
          node.text,
          node.nodeid
        )
      )
      return node
    end
  end
  log.debug(
    string.format(
      "No node found at line %d, col %d (row %d)",
      current_line_one_indexed,
      current_col_one_indexed,
      current_row_zero_indexed
    )
  )
  return nil
end

-- New function to apply highlights for marked nodes
function CallGraphView:apply_marked_node_highlights(marked_node_ids_list)
  if self.buf.bufid == -1 or not vim.api.nvim_buf_is_valid(self.buf.bufid) then
    log.warn("apply_marked_node_highlights: buffer invalid")
    return
  end

  self:clear_marked_node_highlights() -- Clear previous before applying new ones

  if not self.nodes_cache then
    log.warn("apply_marked_node_highlights: nodes_cache is nil")
    return
  end

  local marked_ids_set = {}
  for _, id in ipairs(marked_node_ids_list) do
    marked_ids_set[id] = true
  end

  for node_id, node in pairs(self.nodes_cache) do
    if marked_ids_set[node_id] then
      log.debug(
        string.format(
          "Highlighting marked node: %s (ID: %d) at row %d, col %d",
          node.text,
          node.nodeid,
          node.row,
          node.col
        )
      )
      -- Ensure node.col and node.text are valid
      if node.row ~= nil and node.col ~= nil and node.text ~= nil then
        local mark_id =
          vim.api.nvim_buf_set_extmark(self.buf.bufid, self.marked_node_namespace_id, node.row, node.col, {
            end_col = node.col + #node.text,
            hl_group = "CallGraphMarkedNode",
            priority = 110, -- Higher than edge highlights (typically 100 or default)
          })
        table.insert(self.ext_marks_id.marked_nodes, mark_id) -- Optional, if needed for individual management
      else
        log.warn(
          string.format(
            "Cannot highlight node %s (ID: %d) due to missing row/col/text info.",
            node.text or "N/A",
            node.nodeid or -1
          )
        )
      end
    end
  end
end

-- New function to get currently drawn graph data
function CallGraphView:get_drawn_graph_data()
  return {
    nodes = self.nodes_cache, -- This should be the map {nodeid = node_obj}
    edges = self.edges_cache, -- This should be the list/map of edge objects
  }
end

return CallGraphView
