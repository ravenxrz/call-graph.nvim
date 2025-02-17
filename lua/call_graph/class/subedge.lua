--- @class SubEdge
local SubEdge = {
  sub_edgeid = 1
}
SubEdge.__index = SubEdge

function SubEdge:new(start_row, start_col, end_row, end_col)
  local e = setmetatable({
    start_row = start_row,
    start_col = start_col,
    end_row = end_row,
    end_col = end_col,
    sub_edgeid = SubEdge.sub_edgeid,
  }, SubEdge)
  SubEdge.sub_edgeid = SubEdge.sub_edgeid + 1
  return e
end

function SubEdge:to_string()
  local str = { "sub_edgeid:" .. self.sub_edgeid, "start_row:" .. self.start_row, "start_col:" .. self.start_col,
    "end_row:" .. self.end_row, "end_col:" .. self.end_col }
  return table.concat(str, " ")
end

return SubEdge
