--- @class GraphNode
local GraphNode = {
  nodeid = 1
}

---@param usr_data any
---@return GraphNode
function GraphNode:new(node_text, usr_data)
  local n = {
    nodeid = self.nodeid,
    text = node_text,
    calls = {},  ---@type table<| call_pos | GraphNode | > -- this node calls who?   table of |call_pos_params(TextDocumentPositionParams), GraphNode|
    children = {}, ---@type table<| call_pos | GraphNode |> -- who calls this node?   table of GraphNode
    incoming_edges = {}, ---@type table<Edge>
    outcoming_edges = {}, ---@type table<Edge>
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
