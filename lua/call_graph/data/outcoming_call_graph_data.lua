-- 导入必要的模块
local BaseCallGraphData = require("call_graph.data.base_call_graph_data")
local log = require("call_graph.utils.log")
local Edge = require("call_graph.class.edge")
local vim_lsp = vim.lsp

local OutcomingCall = setmetatable({}, { __index = BaseCallGraphData })
OutcomingCall.__index = OutcomingCall

function OutcomingCall:new()
  return BaseCallGraphData.new(self)
end

-- 定义不同语言的查询语句
local language_queries = {
  cpp = {
    function_call = [[
    [
        ; 基本的函数调用
        (call_expression
          function: (identifier) @func_name)

        ; 带有命名空间限定符的函数调用
        (call_expression
          function: (qualified_identifier
            scope: (namespace_identifier)
            name: (identifier) @func_name))

        ; 成员函数调用，参数为另一个函数调用
        (call_expression
          function: (field_expression
            argument: (call_expression
              function: (qualified_identifier
                scope: (namespace_identifier)
                name: (identifier))
              arguments: (argument_list))
            field: (field_identifier) @func_name))

        ; 嵌套多层的成员函数调用
        (call_expression
          function: (field_expression
            argument: (call_expression
              function: (field_expression
                argument: (call_expression
                  function: (qualified_identifier
                    scope: (namespace_identifier)
                    name: (identifier))
                  arguments: (argument_list))
                field: (field_identifier))
              arguments: (argument_list))
            field: (field_identifier) @func_name))

        ; 带有模板类型的命名空间限定函数调用
        (call_expression
          function: (qualified_identifier
            scope: (namespace_identifier)
            name: (qualified_identifier
              scope: (template_type
                name: (type_identifier)
                arguments: (template_argument_list
                  (type_descriptor
                    type: (type_identifier))))
              name: (identifier) @func_name)))

        ; 简单的成员函数调用，参数为标识符
        (call_expression
          function: (field_expression
            argument: (identifier)
            field: (field_identifier) @func_name))
    ]
        ]],
  },
  -- 可以在这里添加其他语言的查询语句
  -- other_language = {
  --     function_definition = "...",
  --     function_call = "..."
  -- }
}

function OutcomingCall:find_containing_function(cursor_row, cursor_col, lang)
  local bufnr = vim.api.nvim_get_current_buf()
  local clients = vim_lsp.get_active_clients({ bufnr = bufnr })
  if #clients == 0 then
    log.warn("No LSP client is attached to this buffer.")
    return nil
  end

  local params = { textDocument = vim_lsp.util.make_text_document_params(bufnr) }
  local result = nil
  for _, client in ipairs(clients) do
    result = client.request_sync("textDocument/documentSymbol", params, 2000, bufnr)
    if result and result.result then
      break
    end
  end

  if not result or not result.result then
    log.warn("Failed to get document symbols from LSP.")
    return nil
  end

  local function find_function_symbol(symbols)
    local kind = vim_lsp.protocol.SymbolKind
    local expect_kind = {
      kind.Constructor,
      kind.Function,
      kind.Method,
    }
    for _, symbol in ipairs(symbols) do
      if vim.tbl_contains(expect_kind, symbol.kind) then
        local range = symbol.location and symbol.location.range or symbol.range
        if
          range
          and range.start.line <= cursor_row
          and range["end"].line >= cursor_row
          and (
            range.start.line ~= range["end"].line
            or (range.start.character <= cursor_col and range["end"].character >= cursor_col)
          )
        then
          -- 模拟一个 Tree-sitter 节点
          local mock_node = {
            range = function()
              return range.start.line, range.start.character, range["end"].line, range["end"].character
            end,
            name = symbol.name,
          }
          return mock_node
        end
      end
      if symbol.children then
        local child_result = find_function_symbol(symbol.children)
        if child_result then
          return child_result
        end
      end
    end
    return nil
  end

  return find_function_symbol(result.result)
end

function OutcomingCall:find_function_calls(func_node, lang)
  local bufnr = vim.api.nvim_get_current_buf()
  local calls = {}
  local parser = vim.treesitter.get_parser(bufnr, lang)
  if not parser then
    log.warn("Failed to get parser for language: " .. lang)
    return calls
  end

  local tree = parser:parse()[1]
  local root = tree:root()

  local query_str = language_queries[lang].function_call
  local ok, query = pcall(vim.treesitter.query.parse, lang, query_str)
  if not ok then
    log.warn("Failed to parse query for language: " .. lang .. ". Error: " .. query)
    return calls
  end

  -- 获取 func_node 的范围
  local func_start_row, func_start_col, func_end_row, func_end_col = func_node:range()

  for id, node in query:iter_captures(root, bufnr) do
    local capture_name = query.captures[id]
    if capture_name == "func_name" then
      -- 获取当前节点的范围
      local node_start_row, node_start_col = node:start()
      local node_end_row, node_end_col = node:end_()

      -- 检查节点范围是否在 func_node 范围内
      if
        node_start_row >= func_start_row
        and node_end_row <= func_end_row
        and (node_start_row > func_start_row or node_start_col >= func_start_col)
        and (node_end_row < func_end_row or node_end_col <= func_end_col)
      then
        local name = vim.treesitter.get_node_text(node, bufnr)
        local mock_node = {
          range = function()
            return node_start_row, node_start_col, node_end_row, node_end_col
          end,
          name = name,
        }

        table.insert(calls, mock_node)
      end
    end
  end
  return calls
end

function OutcomingCall:generate_call_graph(gen_graph_done_cb, reuse_data)
  assert(reuse_data == false, "OutcomingCall:generate_call_graph only support reuse_data=false")
  self.gen_graph_done_cb = gen_graph_done_cb
  self:clear_data()

  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_row = cursor[1] - 1
  local cursor_col = cursor[2]
  local bufnr = vim.api.nvim_get_current_buf()
  local lang = vim.bo[bufnr].filetype
  if not language_queries[lang] then
    vim.notify("Unsupported language: " .. lang, vim.log.levels.WARN)
    return
  end

  local func_node = self:find_containing_function(cursor_row, cursor_col, lang)
  if not func_node then
    vim.notify("No function found at the cursor position", vim.log.levels.WARN)
    return
  end
  log.info("cursor in func:", vim.inspect(func_node))

  local uri = vim.uri_from_bufnr(bufnr)
  local start_row, start_col, _, _ = func_node:range()
  local func_name = func_node.name
  local root_text = self:make_node_key(uri, start_row, func_name)
  local root_node = self:make_graph_node(root_text, {
    pos_params = {
      textDocument = {
        uri = uri,
      },
      position = {
        line = start_row,
        character = start_col,
      },
    },
  })
  self.root_node = root_node
  self:regist_gnode(root_text, root_node)

  local call_nodes = self:find_function_calls(func_node, lang)
  log.info("calls nodes:", vim.inspect(call_nodes))
  for _, call_node in ipairs(call_nodes) do
    local call_start_row, call_start_col, _, _ = call_node:range()
    local call_name = vim.treesitter.get_node_text(call_node, bufnr)
    local node_text = self:make_node_key(uri, call_start_row, call_name)
    local node
    if self:is_gnode_exist(node_text) then
      node = self.nodes[node_text]
    else
      node = self:make_graph_node(node_text, {
        pos_params = {
          textDocument = {
            uri = uri,
          },
          position = {
            line = call_start_row,
            character = call_start_col,
          },
        },
      })
      self:regist_gnode(node_text, node)
    end

    -- 生成边
    local call_pos_params = {
      position = {
        line = call_start_row,
        character = call_start_col,
      },
      textDocument = {
        uri = uri,
      },
    }
    local edge = Edge:new(root_node, node, call_pos_params)
    table.insert(root_node.outcoming_edges, edge)
    table.insert(node.incoming_edges, edge)
  end
  self._pending_request = self._pending_request + 1
  self:gen_call_graph_done()
end

return OutcomingCall
