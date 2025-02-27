-- 发起lsp incoming call请求，构建绘图数据结构
local BaseCallGraphData = require("call_graph.data.base_call_graph_data")
local log = require("call_graph.utils.log")
local FuncNode = require("call_graph.class.func_node")
local GraphNode = require("call_graph.class.graph_node")
local Edge = require("call_graph.class.edge")

local IncomingCallGraphData = setmetatable({}, { __index = BaseCallGraphData })
IncomingCallGraphData.__index = IncomingCallGraphData

IncomingCallGraphData.request_method = "textDocument/prepareCallHierarchy"

function IncomingCallGraphData:new(max_depth)
  return BaseCallGraphData.new(self, max_depth)
end

function IncomingCallGraphData:get_request_params(fnode)
  return fnode.attr.pos_params
end

function IncomingCallGraphData:call_handler(err, result, _, my_ctx)
  local from_node = my_ctx.from_node
  local depth = my_ctx.depth

  if err then
    vim.notify("Error preparing call hierarchy: " .. err.message, vim.log.levels.ERROR)
    self:gen_call_graph_done()
    return
  end

  if not result or #result == 0 then
    vim.notify("No call hierarchy items found", vim.log.levels.WARN)
    self:gen_call_graph_done()
    return
  end

  local item = result[1]
  local client = self:find_buf_client("callHierarchy/incomingCalls")
  if client == nil then
    vim.notify("No LSP client found or current lsp does not support callHierarchy/incomingCalls", vim.log.levels.WARN)
    self:gen_call_graph_done()
    return
  end

  client.request("callHierarchy/incomingCalls", { item = item }, function(err, result)
    if err then
      vim.notify("Error getting incoming calls: " .. err.message, vim.log.levels.ERROR)
      self:gen_call_graph_done()
      return
    end

    if not result then
      vim.notify("No incoming calls found, result is nil", vim.log.levels.WARN)
      self:gen_call_graph_done()
      return
    end

    log.info("incoming call handler of", from_node.text, "result num", #result)
    if #result == 0 then
      self:gen_call_graph_done()
      return
    end

    local children = {}
    -- we have results, generate node
    for _, call in ipairs(result) do
      local from_uri = call.from.uri
      local node_pos = call.from.range.start
      local call_pos_params
      if #call.fromRanges == 0 then
        call_pos_params = {
          position = nil,
          textDocument = {
            uri = from_uri,
          }
        }
      else
        call_pos_params = {
          position = call.fromRanges[1].start,
          textDocument = {
            uri = from_uri,
          }
        }
      end

      local node_text = self:make_node_key(from_uri, node_pos.line, call.from.name)
      local node
      if self:is_gnode_exist(node_text) then
        node = self.nodes[node_text]
      else
        node = self:make_graph_node(node_text, {
          pos_params = { -- node itself
            textDocument = {
              uri = from_uri,
            },
            position = node_pos
          }
        })
        self:regist_gnode(node_text, node)
      end
      table.insert(children, node)

      -- generate edges
      -- In GraphData's view, from_node is the callee, node is the caller
      -- but in Edge class' view, from_node is the caller, node is the callee
      local edge = Edge:new(node, from_node, call_pos_params)
      -- from_node is the callee, node is the caller
      table.insert(from_node.incoming_edges, edge)
      table.insert(node.outcoming_edges, edge)
    end

    -- for caller, call generate again until depth is deep enough
    if depth < self.max_depth then
      for _, child in ipairs(children) do
        local child_node_key = child.usr_data.node_key
        if not self:is_parsed_node_exsit(child_node_key) then
          self._pending_request = self._pending_request + 1
          self:generate_call_graph_from_node(child, depth + 1)
        end
      end
    end

    self:gen_call_graph_done()
  end)
end

return IncomingCallGraphData

