local MermaidGraph = {}

local log = require("call_graph.utils.log")
local alias_counter = 0 -- 别名计数器

local function generate_alias(node_text)
  alias_counter = alias_counter + 1
  return "node" .. tostring(alias_counter)
end

function MermaidGraph.export(root_node, output_path)
  local graph = {
    "flowchart RL",
    "classDef startNode fill:#D0F6D0,stroke:#333,stroke-width:2px",
    "classDef endNode fill:#fcc,stroke:#333,stroke-width:2px"
  }

  local visited_nodes = {}
  local processed_edges = {}
  local node_aliases = {}
  local node_names = {}

  alias_counter = 0

  local function process_node(node)
    if visited_nodes[node.nodeid] then
      return
    end
    visited_nodes[node.nodeid] = true

    local node_name = node.text
    if not node_name or node_name == "" then
      return
    end

    -- 为节点生成别名
    if not node_aliases[node.nodeid] then
      node_aliases[node.nodeid] = generate_alias(node_name)
    end
    local node_alias = node_aliases[node.nodeid]

    -- 添加节点定义
    if not node_names[node_name] then
      node_names[node_name] = true
      table.insert(graph, string.format("%s[\"%s\"]", node_alias, node_name))
    end

    -- 判断是否为结束节点
    if #node.incoming_edges == 0 and #node.outcoming_edges == 0 then
      table.insert(graph, string.format("class %s endNode", node_alias))
    end

    -- 处理出边
    for _, edge in ipairs(node.outcoming_edges) do
      local target_node = edge.to_node
      local target_name = target_node.text
      if target_name and target_name ~= "" and not target_name:find('test') then
        -- 为目标节点生成别名
        if not node_aliases[target_node.nodeid] then
          node_aliases[target_node.nodeid] = generate_alias(target_name)
        end
        local target_alias = node_aliases[target_node.nodeid]

        -- 添加目标节点定义
        if not node_names[target_name] then
          node_names[target_name] = true
          table.insert(graph, string.format("%s[\"%s\"]", target_alias, target_name))
        end

        -- 构建边的字符串
        local edge_str = string.format("%s --> %s", node_alias, target_alias)
        if not processed_edges[edge_str] then
          processed_edges[edge_str] = true
          table.insert(graph, edge_str)
          process_node(target_node)
        end
      end
    end

    -- 处理入边
    for _, edge in ipairs(node.incoming_edges) do
      local source_node = edge.from_node
      local source_name = source_node.text
      if source_name and source_name ~= "" and not source_name:find('test') then
        -- 为源节点生成别名
        if not node_aliases[source_node.nodeid] then
          node_aliases[source_node.nodeid] = generate_alias(source_name)
        end
        local source_alias = node_aliases[source_node.nodeid]

        -- 添加源节点定义
        if not node_names[source_name] then
          node_names[source_name] = true
          table.insert(graph, string.format("%s[\"%s\"]", source_alias, source_name))
        end

        -- 构建边的字符串
        local edge_str = string.format("%s --> %s", source_alias, node_alias)
        if not processed_edges[edge_str] then
          processed_edges[edge_str] = true
          table.insert(graph, edge_str)
          process_node(source_node)
        end
      end
    end
  end

  -- 处理根节点
  local root_name = root_node.text
  if root_name and root_name ~= "" then
    -- 为根节点生成别名
    if not node_aliases[root_node.nodeid] then
      node_aliases[root_node.nodeid] = generate_alias(root_name)
    end
    local root_alias = node_aliases[root_node.nodeid]

    -- 添加根节点定义
    if not node_names[root_name] then
      node_names[root_name] = true
      table.insert(graph, string.format("%s[\"%s\"]", root_alias, root_name))
    end

    table.insert(graph, string.format("class %s startNode", root_alias))

    process_node(root_node)
  end

  -- 输出到文件
  output_path = output_path or ".call_graph.mermaid"
  local file = io.open(output_path, "w")
  if file then
    file:write(table.concat(graph, "\n"))
    file:close()
  end
end

return MermaidGraph

