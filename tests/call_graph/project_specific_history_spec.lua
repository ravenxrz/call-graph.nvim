local Caller = require("call_graph.caller")
local base_mock = require("tests.base_mock")

-- Test project-specific history file functionality
describe("Project-specific history file functionality", function()
  local original_io_popen, original_io_open

  -- Mock data
  local mock_file = {
    write = function()
      return true
    end,
    read = function()
      return "{}"
    end,
    close = function()
      return true
    end,
  }

  before_each(function()
    -- Save original functions
    original_io_popen = io.popen
    original_io_open = io.open

    -- Reset global state
    _G.path_checks = {}

    -- Mock io.popen for git command simulation
    io.popen = function(cmd)
      if cmd:match("git rev%-parse") then
        return {
          read = function()
            return "/mock/project/root\n"
          end,
          close = function()
            return true
          end,
        }
      end
      return original_io_popen(cmd)
    end

    -- Mock io.open to track opened files
    io.open = function(path, mode)
      table.insert(_G.path_checks, { path = path, mode = mode })
      return mock_file
    end

    -- Ensure vim.fn.getcwd is available
    vim.fn = vim.fn or {}
    vim.fn.getcwd = function()
      return "/fallback/cwd"
    end
  end)

  after_each(function()
    -- Restore original functions
    io.popen = original_io_popen
    io.open = original_io_open
  end)

  it("should use git command to get project root directory", function()
    -- Get history file path (by calling internal function)
    local get_history_file_path = Caller._get_history_file_path_func()
    local file_path = get_history_file_path()

    -- Verify path contains git project root directory
    assert.is_true(file_path:match("/mock/project/root") ~= nil)
    assert.equals("/mock/project/root/.call_graph_history.json", file_path)
  end)

  it("should use project-specific path when saving history", function()
    -- Ensure save history to file function is available
    assert.is_function(Caller.save_history_to_file)

    -- Call save function
    Caller.save_history_to_file()

    -- Verify saved path is project path
    assert.is_true(#_G.path_checks > 0)
    assert.is_true(_G.path_checks[1].path:match("/mock/project/root") ~= nil)
    assert.equals("w", _G.path_checks[1].mode) -- Verify opened in write mode
  end)

  it("should use project-specific path when loading history", function()
    -- Reset path checks
    _G.path_checks = {}

    -- Ensure load history from file function is available
    assert.is_function(Caller.load_history_from_file)

    -- Call load function
    Caller.load_history_from_file()

    -- Verify loaded path is project path
    assert.is_true(#_G.path_checks > 0)
    assert.is_true(_G.path_checks[1].path:match("/mock/project/root") ~= nil)
    assert.equals("r", _G.path_checks[1].mode) -- Verify opened in read mode
  end)

  it("should fallback to current working directory when git command fails", function()
    -- Modify io.popen to simulate git command failure
    io.popen = function(cmd)
      if cmd:match("git rev%-parse") then
        return nil
      end
      return original_io_popen(cmd)
    end

    -- Get history file path
    local get_history_file_path = Caller._get_history_file_path_func()
    local file_path = get_history_file_path()

    -- Verify path uses fallback working directory
    assert.is_true(file_path:match("/fallback/cwd") ~= nil)
  end)
end)
