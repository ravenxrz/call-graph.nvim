--- @class GraphNode
local GraphNode = {
  nodeid = 1
}
GraphNode.__index = GraphNode

---@param usr_data any
---@return GraphNode
function GraphNode:new(node_text, usr_data)
  local n = {
    nodeid = self.nodeid,
    text = node_text,
    calls = {}, ---@type table<GraphNode > -- this node calls who?   table of |call_pos_params(TextDocumentPositionParams), GraphNode|
    children = {}, ---@type table<GraphNode> -- who calls this node?   table of GraphNode
    incoming_edges = {}, ---@type table<Edge>
    outcoming_edges = {}, ---@type table<Edge>
    level = 1,
    row = 0,
    col = 0,
    panted = false,
    usr_data = usr_data,
  }
  n = setmetatable(n, self)
  self.nodeid = self.nodeid + 1
  return n
end

function GraphNode:to_string()
  local str = {
    "nodeid:", self.nodeid, "text", self.text
  }
  return table.concat(str, " ")
end

return GraphNode
