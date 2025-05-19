# call-graph.nvim

[中文版](https://github.com/ravenxrz/call-graph.nvim/blob/main/README_CN.md)

Inspired by [Sourcetrail](https://github.com/CoatiSoftware/Sourcetrail) and [trails.nvim](https://github.com/kontura/trails.nvim), this is an interactive ascii call graph plugin developed to assist in reading source code.

> This plugin is still in active development, and although bugs may be expected, it's becoming more stable with each update. Feedback and contributions are welcome.

**It has been tested with the clangd server and should work with all LSP servers that support callHierarchy/incomingCalls.**

- The pyright server has been tested and is usable, but its performance is poor, and it is not recommended. 

<https://github.com/user-attachments/assets/e6a869d2-21bf-46eb-bf58-e8a81180f60f>

## Features

Demonstrated with the open-source project [muduo](https://github.com/chenshuo/muduo):

![](./pic/example.png)

### Basic Features

1. Each node is named in the format `func_name/file:line_numer`.

2. The incoming edge of each node is the callee, and the outgoing edge is the caller.

3. When the cursor moves to a node, all its incoming and outgoing edges will be automatically highlighted.

4. When the cursor moves to an edge, all the edges overlapping with the current cursor (there may be multiple edges) will be automatically highlighted.

5. Each node and edge can be jumped to the corresponding position using the shortcut key `gd`.

6. For each node, you can use the shortcut key `K` to display the full file path, for example:

<img src="./pic/show_full_path.png" alt="image-20250217212652672" style="zoom:50%;" />

7. When there are overlapping multiple edges and you want to jump to one of them, an optional window will be provided:


As follows, foo1 is called by both foo2 and foo3 at the same time, and the cursor overlaps with both edges:

<img src="./pic/cursor_overlap_multi_edge.png" alt="image-20250217213038893" style="zoom:50%;" />

At this time, a selection will be provided when pressing `gd`:

<img src="./pic/multi_edge_goto.png" alt="image-20250217213125179" style="zoom:50%;" />

### Advanced Features

#### Mermaid Graph Export

This plugin will generate a mermaid graph and export it to a file. You can use `CallGraphOpenMermaidGraph` command to open it.

#### Graph History

The plugin now maintains a history of recently generated call graphs, allowing you to:
- View a list of previously generated graphs with `CallGraphHistory`
- Quickly open the most recent graph with `CallGraphOpenLastestGraph`
- Clear history with `CallGraphClearHistory`

#### Mark Mode

You can now select specific nodes of interest in a call graph to create focused subgraphs:
1. Use `CallGraphMarkNode` to enter mark mode and mark nodes (or unmark if already marked)
2. Use `CallGraphMarkEnd` to generate a subgraph from the marked nodes
3. Use `CallGraphMarkExit` to exit mark mode without generating a subgraph

This feature is particularly useful for analyzing complex call graphs by focusing only on relationships of interest.

## Installation

Installing with lazy.nvim:

```lua
{
    "ravenxrz/call-graph.nvim",
     dependencies = {
       "nvim-treesitter/nvim-treesitter",
     },
    opts = {
        log_level = "info",
        auto_toggle_hl = true, -- Whether to automatically highlight
        hl_delay_ms = 200, -- Interval time for automatic highlighting
        in_call_max_depth = 4, -- Maximum search depth for incoming calls 
        ref_call_max_depth = 4, -- Maximum search depth for reference calls
        export_mermaid_graph = false, -- Whether to export the Mermaid graph
        max_history_size = 20, -- Maximum number of graphs to keep in history
    }
}
```

## Supported Commands

- **CallGraphI**: Generate a call graph using incoming calls (fast, but not comprehensive)
- **CallGraphR**: Generate a call graph using references + treesitter (slow, and many files will be opened, but the call graph is more comprehensive. Currently, it only supports C++)
- **CallGraphO**: Generate a outcomimg call graph using treesitter (only supports C++)
- **CallGraphOpenMermaidGraph**: Open the Mermaid graph
- **CallGraphLog**: Open the log of the call graph
- **CallGraphHistory**: Show and select from call graph history
- **CallGraphOpenLastestGraph**: Open the most recently generated call graph
- **CallGraphMarkNode**: Mark/unmark the node under cursor (automatically starts mark mode if not active)
- **CallGraphMarkEnd**: End marking and generate subgraph from marked nodes
- **CallGraphMarkExit**: Exit mark mode without generating subgraph, clears all markings
- **CallGraphClearHistory**: Clear all call graph history (both in memory and on disk)

## Highlight Groups

- **CallGraphLine**: The default value is linked to `Search`
- **CallGraphMarkedNode**: The default value is linked to `Visual` (used for marked nodes in mark mode)

## FAQ

**1. When jumping from the call graph to the buffer, the location is incorrect**

This may be a bug in Neovim or the LSP server. The return value of the `vim.lsp.buf.incoming_calls` function is inaccurate. You can call `:lua vim.lsp.buf.incoming_calls()` to confirm the return value of the location information

**2. The call graph is incomplete**

According to [issue](https://github.com/clangd/clangd/issues/609), the LSP incomingCalls only supports analyzing opened files. Therefore, for files that are not opened, the analysis may be missing.

Solutions: Manually jump around the graph (to open the file), and then regenerate the call graph from the root node; or use CallGraphR.



