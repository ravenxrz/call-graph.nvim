--- @class SubEdge
local SubEdge = {
  sub_edgeid = 1
}

function SubEdge:new(start_row, start_col, end_row, end_col)
  local e = {
    start_row = start_row,
    start_col = start_col,
    end_row = end_row,
    end_col = end_col,
    sub_edgeid = SubEdge.sub_edgeid,
  }
  SubEdge.sub_edgeid = SubEdge.sub_edgeid + 1
  return e
end

return SubEdge
