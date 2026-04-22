local M = {}

local ns_id = vim.api.nvim_create_namespace('jikan_clock')
local EMPTY = '\xE2\xA0\x80' -- ⡀ (braille blank cell)

local state = {
  buf = nil,
  timer = nil,
  colon_on = true,
  last_min = -1,
}

local config = { font = 'Inter', color = nil }

local GLYPH_ROWS = 20

local glyphs = nil -- { [char] = { rows = {...}, width = N } }

local function load_glyphs()
  local src = debug.getinfo(1, 'S').source:sub(2)
  local root = vim.fn.fnamemodify(src, ':h:h:h')
  local art = root .. '/art/'

  local chars = { '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':' }
  local result = {}
  for _, ch in ipairs(chars) do
    local suffix = ch == ':' and 'colon' or ch
    local fname = config.font .. '_' .. suffix .. '.txt'
    local raw = vim.fn.readfile(art .. fname)
    if not raw or #raw == 0 then
      raw = vim.fn.readfile(art .. 'Inter_' .. suffix .. '.txt')
    end
    if raw and #raw > 0 then
      -- width = widest row in braille chars (each char is 3 bytes)
      local width = 0
      for _, line in ipairs(raw) do
        local w = #line / 3
        if w > width then
          width = w
        end
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
      for _ = 1, pad_top do
        padded[#padded + 1] = empty_row
      end
      for _, r in ipairs(rows) do
        padded[#padded + 1] = r
      end
      for _ = 1, pad_bot do
        padded[#padded + 1] = empty_row
      end
      result[ch] = { rows = padded, width = width }
    end
  end
  return result
end

local function draw()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  local win = vim.fn.bufwinid(state.buf)
  if win == -1 then
    return
  end

  if not glyphs then
    glyphs = load_glyphs()
  end

  local time_str = vim.fn.strftime('%H%M')
  local chars = {
    time_str:sub(1, 1),
    time_str:sub(2, 2),
    ':',
    time_str:sub(3, 3),
    time_str:sub(4, 4),
  }

  local GAP = 2 -- braille cells between characters
  local total_width = 0
  for i, ch in ipairs(chars) do
    local g = glyphs[ch]
    if g then
      total_width = total_width + g.width
      if i < #chars then
        total_width = total_width + GAP
      end
    end
  end

  local win_width = vim.api.nvim_win_get_width(win)
  local win_height = vim.api.nvim_win_get_height(win)
  local start_col = math.max(0, math.floor((win_width - total_width) / 2))
  local start_row = math.max(1, math.floor((win_height - GLYPH_ROWS) / 2))
  local pad_str = string.rep(' ', start_col)

  -- Build buffer lines
  local buf_lines = {}
  for _ = 1, win_height do
    buf_lines[#buf_lines + 1] = ''
  end

  for r = 1, GLYPH_ROWS do
    local row_idx = start_row + r - 1
    if row_idx >= 1 and row_idx <= win_height then
      local parts = {}
      for i, ch in ipairs(chars) do
        local g = glyphs[ch]
        if g then
          if ch == ':' and not state.colon_on then
            parts[#parts + 1] = string.rep(EMPTY, g.width)
          else
            parts[#parts + 1] = g.rows[r] or string.rep(EMPTY, g.width)
          end
          if i < #chars then
            parts[#parts + 1] = string.rep(EMPTY, GAP)
          end
        end
      end
      buf_lines[row_idx] = pad_str .. table.concat(parts)
    end
  end

  vim.api.nvim_set_option_value('modifiable', true, { buf = state.buf })
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, buf_lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = state.buf })

  -- Highlight all glyph rows
  -- col offsets are in bytes: pad_str is ASCII (1 byte/char), braille is 3 bytes/char
  vim.api.nvim_buf_clear_namespace(state.buf, ns_id, 0, -1)
  for r = 1, GLYPH_ROWS do
    local row_idx = start_row + r - 1
    if row_idx >= 1 and row_idx <= win_height then
      vim.api.nvim_buf_set_extmark(state.buf, ns_id, row_idx - 1, start_col, {
        end_col = start_col + total_width * 3,
        hl_group = 'JikanClock',
      })
    end
  end

  pcall(vim.api.nvim_win_set_cursor, win, { start_row + math.floor(GLYPH_ROWS / 2), start_col })
end

local function tick()
  state.colon_on = not state.colon_on
  local cur_min = tonumber(vim.fn.strftime('%M')) or -1
  if cur_min ~= state.last_min then
    state.last_min = cur_min
  end
  draw()
end

local function stop_timer()
  if state.timer then
    vim.fn.timer_stop(state.timer)
    state.timer = nil
  end
end

local function resolve_color()
  if config.color then
    return config.color
  end

  local hl = vim.api.nvim_get_hl(0, { name = 'Normal' })
  if hl and hl.bg then
    local bg = hl.bg
    local r = math.floor(bg / 0x10000) % 0x100
    local g = math.floor(bg / 0x100) % 0x100
    local b = bg % 0x100
    local lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255
    return lum < 0.4 and '#AED6F1' or '#1A4A7A'
  end

  return vim.o.background == 'light' and '#1A4A7A' or '#AED6F1'
end

local function apply_hl()
  vim.api.nvim_set_hl(0, 'JikanClock', { fg = resolve_color() })
end

local function open()
  if vim.fn.argc() ~= 0 then
    return
  end

  apply_hl()

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('buftype', 'nofile', { buf = buf })
  vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = buf })
  vim.api.nvim_set_option_value('swapfile', false, { buf = buf })
  vim.api.nvim_set_option_value('modifiable', false, { buf = buf })

  state.buf = buf
  state.colon_on = true
  state.last_min = tonumber(vim.fn.strftime('%M')) or -1

  vim.api.nvim_win_set_buf(0, buf)

  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_option_value('number', false, { win = win })
  vim.api.nvim_set_option_value('relativenumber', false, { win = win })
  vim.api.nvim_set_option_value('cursorline', false, { win = win })
  vim.api.nvim_set_option_value('cursorcolumn', false, { win = win })
  vim.api.nvim_set_option_value('signcolumn', 'no', { win = win })
  vim.api.nvim_set_option_value('foldcolumn', '0', { win = win })
  vim.api.nvim_set_option_value('list', false, { win = win })
  vim.api.nvim_set_option_value('colorcolumn', '', { win = win })
  vim.api.nvim_set_option_value(
    'winhighlight',
    'ColorColumn:Normal,CursorColumn:Normal,CursorLine:Normal',
    { win = win }
  )

  draw()

  state.timer = vim.fn.timer_start(1200, function()
    tick()
  end, { ['repeat'] = -1 })

  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    once = true,
    callback = stop_timer,
  })
  vim.api.nvim_create_autocmd('VimResized', {
    buffer = buf,
    callback = draw,
  })
end

function M.setup(opts)
  if opts then
    if opts.font then
      config.font = opts.font
    end
    if opts.color then
      config.color = opts.color
    end
  end
  vim.api.nvim_create_autocmd('VimEnter', {
    once = true,
    callback = open,
  })
  vim.api.nvim_create_autocmd('ColorScheme', {
    callback = apply_hl,
  })
end

return M
