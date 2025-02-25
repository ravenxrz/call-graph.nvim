-- 导出mermaid类图
local MermaidGraph = {}
local log = require("call_graph.utils.log")

---@param node_text string
local function get_func_name(node_text)
  if node_text == nil or node_text == "" then
    return node_text
  end
  node_text = node_text:gsub('@', '/')
  return node_text
end

function MermaidGraph.export(root_node, output_path)
  local graph = { "flowchart" }
  local visit = {}
  local edge_traverse = {}
  local function traverse(node)
    if visit[node.nodeid] then
      return
    end
    visit[node.nodeid] = true
    for _, child in pairs(node.children) do
      local child_name = child.text
      if not child_name:find('test') then
        log.info(string.format("node:%s has child:%s", node.text, child_name))
        local edge_text = string.format("%s --> %s", get_func_name(child_name), get_func_name(node.text))
        if not edge_traverse[edge_text] then
          edge_traverse[edge_text] = true
          table.insert(graph, edge_text)
          traverse(child)
        end
      end
    end
    visit[node.nodeid] = false
  end
  traverse(root_node)
  -- output to a file
  output_path = output_path or ".calL_grap.mermaid"
  local file = io.open(output_path, "w")
  file:write(table.concat(graph, "\n"))
  file:close()
end

return MermaidGraph
