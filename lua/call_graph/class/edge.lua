--- @classEdge
local Edge = {
  edegid = 1
}
Edge.__index = Edge

--- 一条边可能由多个子边构成
---@param from_node GraphNode
---@param to_node GraphNode
---@param sub_edges table<SubEdge>
---@return Edge
function Edge:new(from_node, to_node, sub_edges)
  local e = setmetatable({
    from_node = from_node,
    to_node = to_node,
    sub_edges = sub_edges,
    edgeid = self.edegid
  }, Edge)
  self.edegid = self.edegid + 1
  return e
end

function Edge:to_string()
  local str = { "edgeid:" .. self.edegid, "from node:" .. (self.from_node ~= nil and self.from_node.text or "nil"),
    "to node:" ..
    (self.to_node ~= nil and self.to_node.text or "nil") }
  for _, sub_edge in pairs(self.sub_edges) do
    table.insert(str, sub_edge:to_string())
  end
  return table.concat(str, " ")
end

return Edge
