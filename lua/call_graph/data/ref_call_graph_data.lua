-- 发起lsp reference call请求，构建绘图数据结构
local BaseCallGraphData = require("call_graph.data.base_call_graph_data")
local log = require("call_graph.utils.log")
local Edge = require("call_graph.class.edge")

local ReferenceCallGraphData = setmetatable({}, { __index = BaseCallGraphData })
ReferenceCallGraphData.__index = ReferenceCallGraphData

ReferenceCallGraphData.request_method = "textDocument/references"

function ReferenceCallGraphData:new(max_depth)
  return BaseCallGraphData.new(self, max_depth)
end

function ReferenceCallGraphData:get_request_params(fnode)
  return {
    textDocument = fnode.attr.pos_params.textDocument,
    position = fnode.attr.pos_params.position,
    context = {
      includeDeclaration = false -- 是否包含声明信息
    }
  }
end

local function get_ref_func_symbol(uri, range)
  local parser_configs = require "nvim-treesitter.parsers".get_parser_configs()
  local parsers = require "nvim-treesitter.parsers"

  -- 将 file:// 协议的 URI 转换为本地文件路径
  local file_path = vim.uri_to_fname(uri) -- 使用 vim.uri_to_fname

  -- 获取文件的语言类型，这里简单根据文件扩展名判断
  local lang = "cpp"

  if not parser_configs[lang] then
    log.warn("Unsupported language: " .. lang, "uri", uri)
    return nil
  end

  -- 解析文件内容
  local bufnr = vim.uri_to_bufnr(uri)
  local ok, parser = pcall(parsers.get_parser, bufnr, lang)

  if not ok then
    log.warn("Failed to get parser for file: " .. file_path, "uri", uri)
    return nil
  end

  local tree = parser:parse()[1]
  local root = tree:root()

  -- 遍历语法树，查找函数定义节点
  local query = vim.treesitter.query.parse(lang, [[
        [
          ;; 普通函数定义
          (function_definition
            type: (primitive_type)
            declarator: (function_declarator
              declarator: (identifier) @function.name
              parameters: (parameter_list))
            ) @function.def

          ;; 带命名空间的普通函数定义
          (function_definition
            declarator: (function_declarator
              declarator: (qualified_identifier
                scope: (namespace_identifier)
                name: (identifier) @function.name))
            ) @function.def

          ;; 多层嵌套命名空间函数定义
          (function_definition
            type: (primitive_type)
            declarator: (function_declarator
              declarator: (qualified_identifier
                scope: (namespace_identifier)
                name: (qualified_identifier
                  scope: (namespace_identifier)
                  name: (identifier) @function.name)))
            ) @function.def

          ;; 析构函数定义
          (function_definition
                declarator: (function_declarator
                    declarator: (qualified_identifier
                        name: (destructor_name) @function.name
                    )
                )
            ) @function.def

          ;; 普通成员函数定义(out define)
          (function_definition
            type: (primitive_type)
            declarator: (function_declarator
              declarator: (field_identifier) @function.name
              )) @function.def

          ;; 类定义中的函数定义(inner define)
        (class_specifier
            body: (field_declaration_list
                (function_definition
                    declarator: (function_declarator
                        declarator: (identifier) @function.name
                    )
                )
            )
        ) @function.def
        ]
    ]])

  local current_function_def_node = nil
  for id, node in query:iter_captures(root, bufnr) do
    local capture_name = query.captures[id]
    if capture_name == "function.def" then -- TODO(zhangxingrui): 假设ts先返回最外层
      -- 记录当前函数定义节点
      current_function_def_node = node
    elseif capture_name == "function.name" then
      -- 获取函数名节点的信息
      local name = vim.treesitter.get_node_text(node, bufnr)
      local name_start_row, name_start_col = node:start()
      local name_end_row, name_end_col = node:end_()
      log.debug(vim.inspect(range))

      if current_function_def_node then
        local def_start_row, _ = current_function_def_node:start()
        local def_text = vim.treesitter.get_node_text(current_function_def_node, bufnr)
        local def_end_row = def_start_row + #vim.split(def_text, '\n')
        log.debug("fun_name", name, name_start_row, name_start_col, name_end_row, name_end_col)
        log.debug("whole func", def_start_row, 0, def_end_row, 0)

        -- 判断传入的 range 是否在函数定义范围内
        local range_start_row = range.start.line
        local range_end_row = range["end"].line
        local is_in_range = (
          range_start_row >= def_start_row and range_end_row < def_end_row
        )

        if is_in_range then
          log.info("find the calling symbol", name)
          return {
            name = name,
            range = {
              start = {
                line = name_start_row,
                character = name_start_col
              },
              ["end"] = {
                line = name_end_row,
                character = name_end_col
              }
            }

          }
        end
      end
    end
  end
  return nil
end

function ReferenceCallGraphData:call_handler(err, result, _, my_ctx)
  local from_node = my_ctx.from_node
  local fnode = from_node.usr_data
  local depth = my_ctx.depth

  if err then
    self:gen_call_graph_done()
    log.warn("Error getting references: " .. err.message, "call info", fnode.node_key)
    return
  end

  if not result or #result == 0 then
    self:gen_call_graph_done()
    vim.notify(string.format("No references found of %s", fnode.node_key), vim.log.levels.DEBUG)
    return
  end

  -- 处理引用结果
  local caller = {}
  local children = {}
  for i, ref in ipairs(result) do
    log.debug("references result", i, vim.inspect(ref))
    local uri = ref.uri
    local ref_start = ref.range.start

    -- 获取文件的函数符号信息
    local symbol = get_ref_func_symbol(uri, ref.range)
    if symbol then
      log.info("find symbols by ts", vim.inspect(symbol))
      local symbol_range = symbol.range
      local symbol_start = symbol_range.start

      -- 创建或获取目标节点
      local node_text = self:make_node_key(uri, symbol_start.line, symbol.name)
      local node
      if self:is_gnode_exist(node_text) then
        node = self.nodes[node_text]
      else
        node = self:make_graph_node(node_text, {
          pos_params = {
            textDocument = {
              uri = uri
            },
            position = symbol_start
          }
        })
        self:regist_gnode(node_text, node)
      end

      if caller[node_text] == nil then -- 避免重复分析同一个节点
        caller[node_text] = true
        -- 建立节点之间的连接关系
        table.insert(children, node)
        log.info(string.format("node:%s has child:%s", from_node.text, node.text))
        -- 生成边
        local call_pos_params = {
          position = ref_start,
          textDocument = {
            uri = uri
          }
        }
        local edge = Edge:new(node, from_node, call_pos_params)
        table.insert(from_node.incoming_edges, edge)
        table.insert(node.outcoming_edges, edge)
      end
    end
  end

  -- 递归生成调用图
  if depth < self.max_depth - 1 then
    for _, child in pairs(children) do
      local child_node_key = child.usr_data.node_key
      if not self:is_parsed_node_exsit(child_node_key) then
        log.info("try generate call graph of node", child_node_key)
        self._pending_request = self._pending_request + 1
        BaseCallGraphData.generate_call_graph_from_node(self, child, depth + 1)
      end
    end
  end
  self:gen_call_graph_done()
end

return ReferenceCallGraphData
