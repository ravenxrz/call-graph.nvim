--- @classEdge
local Edge = {
  edegid = 1
}

--- 一条边可能由多个子边构成
---@param from_node GraphNode
---@param to_node GraphNode
---@param sub_edges table<SubEdge>
---@return Edge
function Edge:new(from_node, to_node, sub_edges)
  local e = {}
  e.from_node = from_node
  e.to_node = to_node
  e.sub_edges = sub_edges
  e.edgeid = self.edegid

  self.edegid = self.edegid + 1
  return e
end
return Edge
