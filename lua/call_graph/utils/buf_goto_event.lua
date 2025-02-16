local M = {
  bufs = {}
}
local log = require("call_graph.utils.log")

--- 设置 buffer 的回调函数
--- @param bufnr integer buffer number
--- @param cb function 回调函数，接受 row 和 col 作为参数
M.setup_buffer = function(bufnr, cb, keymap)
  local mapping = keymap or "gd"
  M.bufs[bufnr] = cb
  local cursor_cb = function()
    local bufid = vim.api.nvim_win_get_buf(0)
    log.debug("cursor cb is called, bufid", bufid)
    if M.bufs[bufid] == nil then
      log.debug(string.format("buf id:%d has no cb registed", bufid))
      return
    end
    local pos = vim.api.nvim_win_get_cursor(0)
    if pos == nil or #pos ~= 2 then
      log.error("get cursor position error")
      return
    end
    local current_row = pos[1]
    local current_col = pos[2]
    current_row = current_row - 1 -- 行是1-based
    current_col = current_col     -- 列是0-based
    M.bufs[bufid](current_row, current_col)
  end
  vim.keymap.set("n", mapping, cursor_cb, { buffer = bufnr, silent = true, noremap = true })
end

--- @param bufnr integer buffer number
function M.clear_buffer(bufnr)
  if M.bufs[bufnr] then
    log.debug("clear buf id", bufnr, "cb")
    M.bufs[bufnr] = nil                           -- 移除 bufnr 对应的回调函数
    vim.keymap.del("n", "gd", { buffer = bufnr }) -- 移除快捷键
  end
end

vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, { -- 同时监听 BufDelete 和 BufWipeout 事件
  callback = function(event)
    local bufnr = event.buf
    M.clear_buffer(bufnr)
  end,
})


return M
