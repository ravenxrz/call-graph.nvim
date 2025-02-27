local log = {}

-- 默认配置
log.config = {
  level = "info",                                                                       -- 日志级别：trace, debug, info, warn, error, fatal
  filepath = vim.fn.stdpath('state') .. "/call_grap_" .. os.date("%Y-%m-%d") .. ".log", -- 日志文件名
  append = true,                                                                        -- 是否追加到文件
  caller = true,                                                                        -- 是否显示调用者信息
}

local config = log.config

-- 日志级别映射
local levels = {
  trace = 1,
  debug = 2,
  info = 3,
  warn = 4,
  error = 5,
  fatal = 6,
}

-- 日志文件
local log_file

-- 获取当前时间字符串
local function get_timestamp()
  return os.date("%Y-%m-%d %H:%M:%S")
end

-- 获取调用者信息
local function get_caller_info()
  local info = debug.getinfo(4, "Sl")                         -- 4 表示调用 log.trace/debug/info/warn/error/fatal 的函数
  if info and info.short_src and info.currentline then
    local filename = string.match(info.short_src, "([^/]+)$") -- 提取文件名
    return string.format("%s:%d", filename, info.currentline)
  else
    return "unknown"
  end
end

-- 写入日志到文件
local function write_log(level, message)
  local log_level = levels[level] or 0
  local config_level = levels[config.level] or 3

  if log_level < config_level then
    return -- 日志级别不够，不写入
  end

  local caller_info = ""
  if config.caller then
    caller_info = string.format(" [%s]", get_caller_info())
  end
  local log_message = string.format("%s [%s]%s %s\n", get_timestamp(), string.upper(level), caller_info, message)
  if log_file then
    log_file:write(log_message)
    log_file:flush()
  end
end

local function _setup()
  local file, err = io.open(config.filepath, config.append and "a" or "w")
  if not file then
    print("[call_graph plugin]: Error opening log file:", err)
    return
  end
  log_file = file
end

-- 设置配置
function log.setup(options)
  if type(options) ~= "table" then
    _setup()
    return
  end

  for k, v in pairs(options) do
    config[k] = v
  end

  _setup()
end

-- 日志级别函数
log.trace = function(...)
  local message = table.concat({ ... }, " ")
  write_log("trace", message)
end

log.debug = function(...)
  local message = table.concat({ ... }, " ")
  write_log("debug", message)
end

log.info = function(...)
  local message = table.concat({ ... }, " ")
  write_log("info", message)
end

log.warn = function(...)
  local message = table.concat({ ... }, " ")
  write_log("warn", message)
end

log.error = function(...)
  local message = table.concat({ ... }, " ")
  write_log("error", message)
end

log.fatal = function(...)
  local message = table.concat({ ... }, " ")
  write_log("fatal", message)
end

return log
