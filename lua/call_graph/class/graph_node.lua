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
    parent = {},   -- this node calls who?   table of |call_pos_params(TextDocumentPositionParams), GraphNode|
    children = {}, -- who calls this node?   table of GraphNode
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
