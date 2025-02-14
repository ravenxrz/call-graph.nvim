--- @class Edge
local Edge = {
  edgeid = 1
}
Edge.__index = Edge

--- @param callee_node Node
--- @param caller_node Node
--- @param attr table
--- @return Edge the new edge
function Edge:new(callee_node, caller_node, attr)
  local e = setmetatable({}, Edge)
  e = {
    callee_node = callee_node,
    caller_node = caller_node,
    attr = attr,
    edgeid = self.edgeid 
  }
  self.edgeid = self.edgeid + 1
  return e
end

return Edge
