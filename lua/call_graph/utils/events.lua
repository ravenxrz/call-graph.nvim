local M = {
  bufs = {

  }
}
local log = require("call_graph.utils.log")

--- 对指定bnfnr设定keymap，当用户按下指定快捷键时，调用指定的回调函数，回调函数包括当前光标位置和cb_ctx
--- @param bufnr integer buffer number
--- @param cb function 回调函数，接受 row 和 col 作为参数
M.setup_buffer_press_cursor_cb = function(bufnr, cb, cb_ctx, keymap)
  local mapping = keymap or "gd"
  if M.bufs[bufnr] == nil then
    M.bufs[bufnr] = {}
  end
  M.bufs[bufnr].press_cb = {
    cb = cb,
    cb_ctx = cb_ctx
  }
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
    M.bufs[bufid].press_cb.cb(current_row, current_col, M.bufs[bufid].press_cb.cb_ctx)
  end
  vim.keymap.set("n", mapping, cursor_cb, { buffer = bufnr, silent = true, noremap = true })
end

M.regist_cursor_hold_cb = function(bufnr, cb, cb_ctx)
  if M.bufs[bufnr] == nil then
    M.bufs[bufnr] = {}
  end
  if M.bufs[bufnr] ~= nil and M.bufs[bufnr].cursor_hold ~= nil then
    log.debug("cursor hold cb is already registed")
    return
  end
  M.bufs[bufnr].cursor_hold = {
    cb = cb,
    cb_ctx = cb_ctx
  }
  local function cursor_hold_cb(bufnr)
    if M.bufs[bufnr] == nil or M.bufs[bufnr].cursor_hold == nil then
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
    M.bufs[bufnr].cursor_hold.cb(current_row, current_col, M.bufs[bufnr].cursor_hold.cb_ctx)
  end

  vim.api.nvim_create_autocmd({ "CursorHold" }, {
    buffer = bufnr,
    callback = function(event)
      cursor_hold_cb(event.buf)
    end,
  })
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
    M.clear_buffer(event.buf)
  end,
})



return M
