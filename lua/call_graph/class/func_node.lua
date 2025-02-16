--- @class FuncNode
local FuncNode = {
}
FuncNode.__index = FuncNode

---@param node_key string
---@param attr table
---@return FuncNode
function FuncNode:new(node_key, attr)
  local n = setmetatable({}, FuncNode)
  n = {
    node_key = node_key,
    attr = attr,
  }
  return n
end

return FuncNode
