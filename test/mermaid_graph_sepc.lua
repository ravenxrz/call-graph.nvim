-- 加载要测试的模块
local MermaidGraph = require('call_graph.view.mermaid_graph')

-- 模拟节点和边的结构
local function create_node(nodeid, text)
  return {
    nodeid = nodeid,
    text = text,
    incoming_edges = {},
    outcoming_edges = {}
  }
end

local function create_edge(from_node, to_node)
  return {
    from_node = from_node,
    to_node = to_node
  }
end

-- 生成基于当前路径的绝对输出文件路径
local function generate_output_path(filename)
  local cwd = vim.loop.cwd()
  return cwd .. "/" .. filename
end

-- 检查文件是否存在
local function check_file_exists(file_path, should_exist)
  local file = io.open(file_path, "r")
  local file_exists = file ~= nil
  if file then
    file:close()
  end
  assert.is.equal(should_exist, file_exists,
    string.format("Output file %s exist as expected", should_exist and "should" or "should not"))
end

-- 逐行比较文件内容
local function compare_file_content(file_path, target_lines)
  local file = io.open(file_path, "r")
  assert.is_true(file ~= nil, "file open failed")

  local line_num = 1
  for line in file:lines() do
    if line_num > #target_lines then
      error(string.format("Extra line %d in output file: '%s'", line_num, line))
    end
    if line ~= target_lines[line_num] then
      error(string.format("Line %d does not match. Expected: '%s', Got: '%s'", line_num, target_lines[line_num], line))
    end
    line_num = line_num + 1
  end
  file:close()

  if line_num <= #target_lines then
    error(string.format("Missing line %d in output file: '%s'", line_num, target_lines[line_num]))
  end
end

-- 测试套件
describe('MermaidGraph', function()
  local output_path
  before_each(function()
    -- 在每个测试用例执行前生成输出文件路径
    output_path = generate_output_path("test_output.mermaid")
  end)

  after_each(function()
    -- 在每个测试用例执行后删除测试文件
    local file = io.open(output_path, "r")
    if file then
      file:close()
      os.remove(output_path)
    end
  end)

  it('should export a simple graph to a file', function()
    -- 创建节点
    local node1 = create_node(1, "Node1")
    local node2 = create_node(2, "Node2")

    -- 创建边
    local edge = create_edge(node1, node2)
    table.insert(node1.outcoming_edges, edge)
    table.insert(node2.incoming_edges, edge)

    -- 调用导出函数
    MermaidGraph.export(node1, output_path)

    -- 检查文件是否存在
    check_file_exists(output_path, true)

    -- 目标字符串
    local target_lines = {
      "flowchart RL",
      "classDef startNode fill:#D0F6D0,stroke:#333,stroke-width:2px",
      "classDef endNode fill:#fcc,stroke:#333,stroke-width:2px",
      'node1["Node1"]',
      "class node1 startNode",
      'node2["Node2"]',
      "node1 --> node2",
      "class node2 endNode",
    }

    -- 逐行比较文件内容
    compare_file_content(output_path, target_lines)
  end)

  -- 测试多个节点和边的复杂图
  it('should export a complex graph to a file', function()
    local node1 = create_node(1, "Node1")
    local node2 = create_node(2, "Node2")
    local node3 = create_node(3, "Node3")

    local edge1 = create_edge(node1, node2)
    local edge2 = create_edge(node2, node3)

    table.insert(node1.outcoming_edges, edge1)
    table.insert(node2.incoming_edges, edge1)
    table.insert(node2.outcoming_edges, edge2)
    table.insert(node3.incoming_edges, edge2)

    MermaidGraph.export(node1, output_path)

    check_file_exists(output_path, true)

    local target_lines = {
      "flowchart RL",
      "classDef startNode fill:#D0F6D0,stroke:#333,stroke-width:2px",
      "classDef endNode fill:#fcc,stroke:#333,stroke-width:2px",
      'node1["Node1"]',
      "class node1 startNode",
      'node2["Node2"]',
      "node1 --> node2",
      'node3["Node3"]',
      "node2 --> node3",
      "class node3 endNode",
    }

    compare_file_content(output_path, target_lines)
  end)

  -- 测试只有一个节点的图
  it('should export a single node graph to a file', function()
    local node = create_node(1, "SingleNode")

    MermaidGraph.export(node, output_path)

    check_file_exists(output_path, true)

    local target_lines = {
      "flowchart RL",
      "classDef startNode fill:#D0F6D0,stroke:#333,stroke-width:2px",
      "classDef endNode fill:#fcc,stroke:#333,stroke-width:2px",
      'node1["SingleNode"]',
      "class node1 startNode",
      "class node1 endNode",
    }

    compare_file_content(output_path, target_lines)
  end)

  -- 测试根节点只有入边的情况
  it('should export a graph with root node having only incoming edges', function()
    local node1 = create_node(1, "Node1")
    local node2 = create_node(2, "Node2")

    local edge = create_edge(node2, node1)
    table.insert(node2.outcoming_edges, edge)
    table.insert(node1.incoming_edges, edge)

    MermaidGraph.export(node1, output_path)

    check_file_exists(output_path, true)

    local target_lines = {
      "flowchart RL",
      "classDef startNode fill:#D0F6D0,stroke:#333,stroke-width:2px",
      "classDef endNode fill:#fcc,stroke:#333,stroke-width:2px",
      'node1["Node1"]',
      "class node1 startNode",
      'node2["Node2"]',
      "node2 --> node1",
      "class node2 endNode",
    }

    compare_file_content(output_path, target_lines)
  end)

  -- 测试输入根节点为 nil 的情况
  it('should handle nil root node gracefully', function()
    MermaidGraph.export(nil, output_path)
    check_file_exists(output_path, false)
  end)
end)

