# call-graph.nvim

受[Sourcetrail](https://github.com/CoatiSoftware/Sourcetrail) 和 [trails.nvim ](https://github.com/kontura/trails.nvim)启发，开发的 interactive ascii call graph插件，用于辅助阅读源码。

> 此插件仍在积极开发中，虽然可能会有一些bug，但随着每次更新变得更加稳定。欢迎反馈和贡献。

**已在clangd server上测试通过，理论上所有支持callHierarchy/incomingCalls的lsp server均可使用。**

- pyright server 测试可用，但性能不佳，不建议使用。 

https://github.com/user-attachments/assets/e6a869d2-21bf-46eb-bf58-e8a81180f60f

## 功能

以开源项目[muduo](https://github.com/chenshuo/muduo)展示：

![](./pic/example.png)

### 基础功能

1. 每个节点命名格式为 `func_name/file:line_number`
2. 每个节点入边为callee, 出边为caller
3. 光标移动到一个节点上，会自动高亮它的所有入边和出边
4. 光标移动到边上，会自动高亮所有和当前光标有重叠边（可能会有多个）
5. 每个节点和边都可以通过快捷键`gd`跳转到对应位置
6. 每个节点可以通过快捷键`K`，显示文件全路径, 如：

<img src="./pic/show_full_path.png" alt="image-20250217212652672" style="zoom:50%;" />

7. 多边重合想要跳转时，提供可选窗口：

如下，foo1被foo2和foo3同时调用，光标与两条边都有重叠：

<img src="./pic/cursor_overlap_multi_edge.png" alt="image-20250217213038893" style="zoom:50%;" />

此时跳转会提供选择：

<img src="./pic/multi_edge_goto.png" alt="image-20250217213125179" style="zoom:50%;" />

### 高级功能

#### Mermaid图表导出

此插件会生成Mermaid图表并导出到文件中，您可以使用`CallGraphOpenMermaidGraph`命令打开它。

#### 图表历史记录

插件现在维护最近生成的调用图历史记录，使您能够：
- 使用`CallGraphHistory`查看先前生成的图表列表
- 使用`CallGraphOpenLastestGraph`快速打开最近的图表
- 使用`CallGraphClearHistory`清除历史记录

#### 标记模式

您现在可以在调用图中选择特定的感兴趣节点以创建聚焦的子图：
1. 使用`CallGraphMarkNode`进入标记模式并标记节点（如果已标记则取消标记）
2. 使用`CallGraphMarkEnd`从标记的节点生成子图
3. 使用`CallGraphMarkExit`退出标记模式而不生成子图

这个功能对于分析复杂的调用图特别有用，可以只关注感兴趣的关系。

## 安装

lazy.nvim

```lua
  {
    "ravenxrz/call-graph.nvim",
     dependencies = {
       "nvim-treesitter/nvim-treesitter",
     },
    opts = {
      log_level = "info",
      auto_toggle_hl = true, -- 是否自动高亮
      hl_delay_ms = 200, -- 自动高亮间隔时间
      in_call_max_depth = 4, -- incoming call 最大搜索深度 
      ref_call_max_depth = 4, -- ref call 最大搜索深度
      export_mermaid_graph = false, -- 是否导出mermaid graph
      max_history_size = 20, -- 历史记录中保存的最大图表数量
    }
  }
```

## 支持的命令

- **CallGraphI**: 使用incoming call生成call graph（快，但是不一定全）
- **CallGraphR**: 使用references + treesitter生成call graph（慢，且会打开很多文件，但是call graph更全，当前仅支持C++）
- **CallGraphO**: 使用treesitter生成outcoming call graph（当前仅支持C++）
- **CallGraphOpenMermaidGraph**: 打开mermaid graph
- **CallGraphLog**: 打开call graph的log
- **CallGraphHistory**: 显示并从调用图历史记录中选择
- **CallGraphOpenLastestGraph**: 打开最近生成的调用图
- **CallGraphMarkNode**: 标记/取消标记光标下的节点（如果标记模式未激活则自动启动）
- **CallGraphMarkEnd**: 结束标记并从标记的节点生成子图
- **CallGraphMarkExit**: 退出标记模式而不生成子图，清除所有标记
- **CallGraphClearHistory**: 清除所有调用图历史记录（内存和磁盘中的）

## 高亮组

- **CallGraphLine**: 默认值链接到`Search`
- **CallGraphMarkedNode**: 默认值链接到`Visual`（用于标记模式中的标记节点）

## FAQ

**1. 从call graph跳转到buffer的地方不对或报column out of range**

这可能是neovim或者lsp server的bug，`vim.lsp.buf.incoming_calls` 函数返回值不准，可调用 `:lua vim.lsp.buf.incoming_calls()`确认位置信息返回值。

**2. 调用链图不全**

根据 [issue](https://github.com/clangd/clangd/issues/609) 所说，lsp incomingCalls仅支持分析打开了的文件，所以对于没有打开的文件，可能会缺分析。

解决方案：自行在图上跳转（用于打开文件），然后重新从root node生成调用图; 或者使用CallGraphR。

