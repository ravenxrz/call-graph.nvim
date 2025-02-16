--- @class GraphNode
local GraphNode = {
  nodeid = 1
}
GraphNode.__index = GraphNode

---@param usr_data any
---@return GraphNode
function GraphNode:new(node_text, usr_data)
  local n = setmetatable({}, GraphNode)
  n = {
    nodeid = self.nodeid,
    text = node_text,
    children = {},
    level = 1,
    row = 0,
    col = 0,
    panted = false,

    usr_data = usr_data,
  }
  self.nodeid = self.nodeid + 1
  return n
end

return GraphNode
