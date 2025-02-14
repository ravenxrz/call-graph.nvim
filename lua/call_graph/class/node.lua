--- @class Node
local Node = {
  nodeid = 1
}
Node.__index = Node

---@param text string
---@param attr table
---@return Node
function Node:new(text, attr)
  local n = setmetatable({}, Node)
  n = {
      text = text,
      attr = attr,
      nodeid = self.nodeid,
      children = {}
  }
  self.nodeid = self.nodeid + 1
  return n
end

return Node
