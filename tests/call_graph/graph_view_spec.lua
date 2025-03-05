local CallGraphView = require("call_graph.view.graph_view")
local plenary = require("plenary")
local Edge = require("call_graph.class.edge")

local mock_Log = {
  debug = function(...) end,
  info = function(...) end,
  error = function(...) end,
  warn = function(...) end,
}
package.loaded["call_graph.utils.log"] = mock_Log

local mock_Events = {
  regist_press_cb = function(...) end,
  regist_cursor_hold_cb = function(...) end,
}
package.loaded["call_graph.utils.events"] = mock_Events

local mock_Drawer = {
  new = function(...)
    return {
      set_modifiable = function(...) end,
      draw = function(...) end,
    }
  end,
}
package.loaded["call_graph.view.graph_drawer"] = mock_Drawer

describe("CallGraphView", function()
  local view
  local node1 = {
    row = 0,
    col = 0,
    text = "RootNode",
    level = 1,
    incoming_edges = {},
    outcoming_edges = {},
    nodeid = 1,
    usr_data = {},
  }
  local node2 = {
    row = 0,
    col = 0,
    text = "ChildNode",
    level = 2,
    incoming_edges = {},
    outcoming_edges = {},
    nodeid = 2,
    usr_data = {},
  }
  local root_node = node1
  local edge = Edge:new(node1, node2, nil, {})
  table.insert(node1.outcoming_edges, edge)
  table.insert(node2.incoming_edges, edge)

  before_each(function()
    view = CallGraphView:new(200, true)
  end)

  it("should create a new CallGraphView instance", function()
    assert.is.truthy(view)
    assert.equal(view.hl_delay_ms, 200)
    assert.is.True(view.toggle_auto_hl)
  end)

  it("should clear the view", function()
    view:clear_view()
    assert.equal(view.last_hl_time_ms, 0)
    assert.same(view.ext_marks_id, { edge = {} })
  end)

  it("should set the highlight delay", function()
    view:set_hl_delay_ms(300)
    assert.equal(view.hl_delay_ms, 300)
  end)

  it("should set the toggle auto highlight", function()
    view:set_toggle_auto_hl(false)
    assert.is.False(view.toggle_auto_hl)

    view:set_toggle_auto_hl(true)
    assert.is.True(view.toggle_auto_hl)
  end)

  it("should reuse a buffer", function()
    local bufid = 123
    view:reuse_buf(bufid)
    assert.equal(view.buf.bufid, bufid)
  end)

  it("should draw the graph", function()
    local bufid = view:draw(root_node, nodes, edges, false)
    assert.is.truthy(bufid)
  end)
end)
