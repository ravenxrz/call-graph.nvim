-- Load the module to be tested
local MermaidGraph = require("call_graph.view.mermaid_graph")

-- Mock node and edge structures
local function create_node(nodeid, text)
  return {
    nodeid = nodeid,
    text = text,
    incoming_edges = {},
    outcoming_edges = {},
  }
end

local function create_edge(from_node, to_node)
  return {
    from_node = from_node,
    to_node = to_node,
  }
end

-- Generate absolute output file path based on current directory
local function generate_output_path(filename)
  local cwd = vim.loop.cwd()
  return cwd .. "/" .. filename
end

-- Check if file exists
local function check_file_exists(file_path, should_exist)
  local file = io.open(file_path, "r")
  local file_exists = file ~= nil
  if file then
    file:close()
  end
  assert.is.equal(
    should_exist,
    file_exists,
    string.format("Output file %s exist as expected", should_exist and "should" or "should not")
  )
end

-- Compare file content line by line
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

-- Test suite
describe("MermaidGraph", function()
  local output_path
  before_each(function()
    -- Generate output file path before each test case
    output_path = generate_output_path("test_output.mermaid")
  end)

  after_each(function()
    -- Delete test file after each test case
    local file = io.open(output_path, "r")
    if file then
      file:close()
      os.remove(output_path)
    end
  end)

  it("should export a simple graph to a file", function()
    -- Create nodes
    local node1 = create_node(1, "Node1")
    local node2 = create_node(2, "Node2")

    -- Create edge
    local edge = create_edge(node1, node2)
    table.insert(node1.outcoming_edges, edge)
    table.insert(node2.incoming_edges, edge)

    -- Call export function
    MermaidGraph.export(node1, output_path)

    -- Check if file exists
    check_file_exists(output_path, true)

    -- Target strings
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

    -- Compare file content line by line
    compare_file_content(output_path, target_lines)
  end)

  -- Test complex graph with multiple nodes and edges
  it("should export a complex graph to a file", function()
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

  -- Test graph with only one node
  it("should export a single node graph to a file", function()
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

  -- Test case where root node has only incoming edges
  it("should export a graph with root node having only incoming edges", function()
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

  -- Test handling of nil root node
  it("should handle nil root node gracefully", function()
    MermaidGraph.export(nil, output_path)
    check_file_exists(output_path, false)
  end)
end)
