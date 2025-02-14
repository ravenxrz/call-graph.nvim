--- @class FilePos
local FilePos = {}
FilePos.__index = FilePos

--- @param file_uri string
--- @param line integer
--- @param col integer
--- @return FilePos
function FilePos:new(file_uri, line, col)
  local self = setmetatable({}, FilePos)
  self = {
      file_url = file_uri,
      line = line,
      col = col
  }
  return self
end

return FilePos
