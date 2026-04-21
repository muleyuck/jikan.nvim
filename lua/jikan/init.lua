local M = {}

local ns_id  = vim.api.nvim_create_namespace("jikan_clock")
local EMPTY  = "\xE2\xA0\x80"  -- ⡀ (braille blank cell)

local state = {
  buf      = nil,
  timer    = nil,
  colon_on = true,
  last_min = -1,
}

local config = { font = "Inter" }

local GLYPH_ROWS = 20

local glyphs = nil  -- { [char] = { rows = {...}, width = N } }

local function load_glyphs()
  local src  = debug.getinfo(1, "S").source:sub(2)
  local root = vim.fn.fnamemodify(src, ":h:h:h")
  local art  = root .. "/art/"

  local chars = { "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ":" }
  local result = {}
  for _, ch in ipairs(chars) do
    local suffix = ch == ":" and "colon" or ch
    local fname  = config.font .. "_" .. suffix .. ".txt"
    local raw = vim.fn.readfile(art .. fname)
    if not raw or #raw == 0 then
      raw = vim.fn.readfile(art .. "Inter_" .. suffix .. ".txt")
    end
    if raw and #raw > 0 then
      -- width = widest row in braille chars (each char is 3 bytes)
      local width = 0
      for _, line in ipairs(raw) do
        local w = #line / 3
        if w > width then width = w end
      end
      -- pad each row to uniform width
      local rows = {}
      for _, line in ipairs(raw) do
        local w = #line / 3
        if w < width then
          rows[#rows + 1] = line .. string.rep(EMPTY, width - w)
        else
          rows[#rows + 1] = line
        end
      end
      -- center vertically within GLYPH_ROWS
      local pad_top = math.floor((GLYPH_ROWS - #rows) / 2)
      local pad_bot = GLYPH_ROWS - #rows - pad_top
      local empty_row = string.rep(EMPTY, width)
      local padded = {}
      for _ = 1, pad_top do padded[#padded + 1] = empty_row end
      for _, r in ipairs(rows) do padded[#padded + 1] = r end
      for _ = 1, pad_bot do padded[#padded + 1] = empty_row end
      result[ch] = { rows = padded, width = width }
    end
  end
  return result
end

local function draw()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  local win = vim.fn.bufwinid(state.buf)
  if win == -1 then return end

  if not glyphs then glyphs = load_glyphs() end

  local time_str = os.date("%H:%M")
  local chars    = {
    time_str:sub(1, 1),
    time_str:sub(2, 2),
    ":",
    time_str:sub(4, 4),
    time_str:sub(5, 5),
  }

  local GAP = 2  -- braille cells between characters
  local total_width = 0
  for i, ch in ipairs(chars) do
    local g = glyphs[ch]
    if g then
      total_width = total_width + g.width
      if i < #chars then total_width = total_width + GAP end
    end
  end

  local win_width  = vim.api.nvim_win_get_width(win)
  local win_height = vim.api.nvim_win_get_height(win)
  local start_col  = math.max(0, math.floor((win_width  - total_width) / 2))
  local start_row  = math.max(1, math.floor((win_height - GLYPH_ROWS)  / 2))
  local pad_str    = string.rep(" ", start_col)

  -- Build buffer lines
  local buf_lines = {}
  for _ = 1, win_height do buf_lines[#buf_lines + 1] = "" end

  for r = 1, GLYPH_ROWS do
    local row_idx = start_row + r - 1
    if row_idx >= 1 and row_idx <= win_height then
      local parts = {}
      for i, ch in ipairs(chars) do
        local g = glyphs[ch]
        if g then
          if ch == ":" and not state.colon_on then
            parts[#parts + 1] = string.rep(EMPTY, g.width)
          else
            parts[#parts + 1] = g.rows[r] or string.rep(EMPTY, g.width)
          end
          if i < #chars then parts[#parts + 1] = string.rep(EMPTY, GAP) end
        end
      end
      buf_lines[row_idx] = pad_str .. table.concat(parts)
    end
  end

  vim.api.nvim_buf_set_option(state.buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, buf_lines)
  vim.api.nvim_buf_set_option(state.buf, "modifiable", false)

  -- Highlight all glyph rows
  -- col offsets are in bytes: pad_str is ASCII (1 byte/char), braille is 3 bytes/char
  vim.api.nvim_buf_clear_namespace(state.buf, ns_id, 0, -1)
  for r = 1, GLYPH_ROWS do
    local row_idx = start_row + r - 1
    if row_idx >= 1 and row_idx <= win_height then
      vim.api.nvim_buf_add_highlight(
        state.buf, ns_id, "JikanClock",
        row_idx - 1,
        start_col,
        start_col + total_width * 3
      )
    end
  end

  pcall(vim.api.nvim_win_set_cursor, win, { start_row + math.floor(GLYPH_ROWS / 2), start_col })
end

local function tick()
  state.colon_on = not state.colon_on
  local cur_min  = tonumber(os.date("%M"))
  if cur_min ~= state.last_min then state.last_min = cur_min end
  draw()
end

local function stop_timer()
  if state.timer then
    vim.fn.timer_stop(state.timer)
    state.timer = nil
  end
end

local function open()
  if vim.fn.argc() ~= 0 then return end

  vim.api.nvim_set_hl(0, "JikanClock", { fg = "#6B9DC2" })

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "buftype",    "nofile")
  vim.api.nvim_buf_set_option(buf, "bufhidden",  "wipe")
  vim.api.nvim_buf_set_option(buf, "swapfile",   false)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)

  state.buf      = buf
  state.colon_on = true
  state.last_min = tonumber(os.date("%M"))

  vim.api.nvim_win_set_buf(0, buf)

  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_option(win, "number",         false)
  vim.api.nvim_win_set_option(win, "relativenumber", false)
  vim.api.nvim_win_set_option(win, "cursorline",     false)
  vim.api.nvim_win_set_option(win, "cursorcolumn",   false)
  vim.api.nvim_win_set_option(win, "signcolumn",     "no")
  vim.api.nvim_win_set_option(win, "foldcolumn",     "0")
  vim.api.nvim_win_set_option(win, "list",           false)
  vim.api.nvim_win_set_option(win, "colorcolumn",    "")
  vim.api.nvim_win_set_option(win, "winhighlight",
    "ColorColumn:Normal,CursorColumn:Normal,CursorLine:Normal")

  draw()

  state.timer = vim.fn.timer_start(1200, function() tick() end, { ["repeat"] = -1 })

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer   = buf,
    once     = true,
    callback = stop_timer,
  })
end

function M.setup(opts)
  if opts then
    if opts.font then config.font = opts.font end
  end
  vim.api.nvim_create_autocmd("VimEnter", {
    once     = true,
    callback = open,
  })
end

return M
