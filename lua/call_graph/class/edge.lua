--- @classEdge
local Edge = {
  edgeid = 1,
}
Edge.__index = Edge

--- 一条边可能由多个子边构成
---@param from_node GraphNode
---@param to_node GraphNode
---@param pos_params table<SubEdge>
---@return Edge
function Edge:new(from_node, to_node, pos_params, sub_edges)
  local e = setmetatable({
    from_node = from_node,
    to_node = to_node,
    pos_params = pos_params,
    sub_edges = sub_edges,
    edgeid = self.edgeid,
  }, Edge)
  self.edgeid = self.edgeid + 1
  return e
end

function Edge:is_same_edge(edge)
  return self.from_node.text == edge.from_node.text and self.to_node.text == edge.to_node.text
end

function Edge:to_string()
  local str = {
    "edgeid:" .. self.edgeid,
    "from node:" .. (self.from_node ~= nil and self.from_node.text or "nil"),
    "to node:" .. (self.to_node ~= nil and self.to_node.text or "nil"),
  }
  if self.sub_edges then
    for _, sub_edge in pairs(self.sub_edges) do
      table.insert(str, sub_edge:to_string())
    end
  end
  return table.concat(str, " ")
end

return Edge
