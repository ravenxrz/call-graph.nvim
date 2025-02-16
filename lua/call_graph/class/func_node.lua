--- @class FuncNode
local FuncNode = {
}

---@param node_key string
---@param attr table
---@return FuncNode
function FuncNode:new(node_key, attr)
  local n = {}
  n.node_key = node_key
  n.attr = attr
  return n
end

return FuncNode
