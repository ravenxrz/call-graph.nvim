local MermaidGraph = {}

local log = require("call_graph.utils.log")
local alias_counter = 0 -- 别名计数器

local function generate_alias(node_text)
  alias_counter = alias_counter + 1
  return "node" .. tostring(alias_counter)
end

function MermaidGraph.export(root_node, output_path)
  local graph = {
    "flowchart LR",
    "classDef startNode fill:#D0F6D0,stroke:#333,stroke-width:2px",
    "classDef endNode fill:#fcc,stroke:#333,stroke-width:2px"
  }

  local visit = {}
  local edge_traverse = {}
  local node_aliases = {} -- 存储节点别名
  local node_names = {}   -- 存储节点名称，用于避免重复定义
  alias_counter = 0

  local function traverse(node)
    if visit[node.nodeid] then
      return
    end
    visit[node.nodeid] = true

    local node_name = node.text
    if not node_name or node_name == "" then
      return
    end

    -- 为节点生成别名
    if not node_aliases[node.nodeid] then
      node_aliases[node.nodeid] = generate_alias(node_name)
    end
    local node_alias = node_aliases[node.nodeid]

    -- 添加节点定义，如果尚未定义
    if not node_names[node_name] then
      node_names[node_name] = true
      table.insert(graph, string.format("%s[\"%s\"]", node_alias, node_name))
    end

    if node.children == nil or #node.children == 0 then
      table.insert(graph, string.format("class %s endNode", node_alias))
    end

    for _, child in pairs(node.children) do
      local child_name = child.text
      if not child_name or child_name == "" then
        goto continue
      end

      if not child_name:find('test') then
        -- 为子节点生成别名
        if not node_aliases[child.nodeid] then
          node_aliases[child.nodeid] = generate_alias(child_name)
        end
        local child_alias = node_aliases[child.nodeid]
        -- 添加子节点定义，如果尚未定义
        if not node_names[child_name] then
          node_names[child_name] = true
          table.insert(graph, string.format("%s[\"%s\"]", child_alias, child_name))
        end
        log.info(string.format("node:%s has child:%s", node_name, child_name))
        local edge_text = string.format("%s --> %s", child_alias, node_alias) -- 使用别名连接
        if not edge_traverse[edge_text] then
          edge_traverse[edge_text] = true
          table.insert(graph, edge_text)
          traverse(child)
        end
      end

      ::continue::
    end

    visit[node.nodeid] = false
  end

  -- 处理根节点
  local root_node_name = root_node.text
  if not root_node_name or root_node_name == "" then
    return
  end

  -- 为根节点生成别名
  if not node_aliases[root_node.nodeid] then
    node_aliases[root_node.nodeid] = generate_alias(root_node_name)
  end
  local root_node_alias = node_aliases[root_node.nodeid]

  -- 添加根节点定义
  if not node_names[root_node_name] then
    node_names[root_node_name] = true
    table.insert(graph, string.format("%s[\"%s\"]", root_node_alias, root_node_name))
  end

  table.insert(graph, string.format("class %s startNode", root_node_alias))

  traverse(root_node)

  -- output to a file
  output_path = output_path or ".call_graph.mermaid"
  local file = io.open(output_path, "w")
  file:write(table.concat(graph, "\n"))
  file:close()
end

return MermaidGraph

