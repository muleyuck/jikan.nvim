local M = {}

local ns_id = vim.api.nvim_create_namespace('jikan_clock')
local EMPTY = '\xE2\xA0\x80' -- ⡀ (braille blank cell)

local state = {
  buf = nil,
  timer = nil,
  colon_on = true,
  glyph_row = 0, -- 0-indexed first row of glyph area
  char_cols = {}, -- [i] = byte column start of chars[i]
  char_widths = {}, -- [i] = braille cell width of chars[i]
  last_chars = {}, -- last drawn time chars
  clock_col = 0, -- byte column of clock start (for re-applying highlights)
  clock_total_width = 0, -- total clock width in braille cells (for re-applying highlights)
}

local DEFAULT_FONT = 'Inter'
local config = { font = DEFAULT_FONT, color = nil }

local FONT_ROWS = {
  Inter = 19,
  Digital = 22,
}

local COLOR_DARK = '#AED6F1' -- light color for dark backgrounds
local COLOR_LIGHT = '#1A4A7A' -- dark color for light backgrounds
local GAP = 2 -- braille cells between characters

local glyphs = nil -- { [char] = { rows = {...}, width = N } }
local glyph_rows = 0

local function pad_rows(rows, target_rows, empty_row)
  local pad_top = math.floor((target_rows - #rows) / 2)
  local pad_bot = target_rows - #rows - pad_top
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
  return padded
end

local function process_glyph(raw_lines, max_rows, empty_char)
  local width = 0
  for _, line in ipairs(raw_lines) do
    local w = #line / 3
    if w > width then
      width = w
    end
  end
  local rows = {}
  for _, line in ipairs(raw_lines) do
    local w = #line / 3
    rows[#rows + 1] = w < width and (line .. string.rep(empty_char, width - w)) or line
  end
  local empty_row = string.rep(empty_char, width)
  return { rows = pad_rows(rows, max_rows, empty_row), width = width }
end

local function load_glyph_file(art, font, suffix)
  local raw = vim.fn.readfile(art .. font .. '/' .. suffix .. '.txt')
  if not raw or #raw == 0 then
    raw = vim.fn.readfile(art .. DEFAULT_FONT .. '/' .. suffix .. '.txt')
  end
  return raw
end

local function load_glyphs()
  local src = debug.getinfo(1, 'S').source:sub(2)
  local root = vim.fn.fnamemodify(src, ':h:h:h')
  local art = root .. '/art/'

  local chars = { '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':' }
  local max_rows = FONT_ROWS[config.font] or FONT_ROWS[DEFAULT_FONT]

  local result = {}
  for _, ch in ipairs(chars) do
    local suffix = ch == ':' and 'colon' or ch
    local raw = load_glyph_file(art, config.font, suffix)
    if raw and #raw > 0 then
      result[ch] = process_glyph(raw, max_rows, EMPTY)
    end
  end

  return result, max_rows
end

local function get_time_chars()
  local time_str = vim.fn.strftime('%H%M')
  return {
    time_str:sub(1, 1),
    time_str:sub(2, 2),
    ':',
    time_str:sub(3, 3),
    time_str:sub(4, 4),
  }
end

local function calc_total_width(chars, gap)
  local total = 0
  for i, ch in ipairs(chars) do
    local g = glyphs[ch]
    if g then
      total = total + g.width
      if i < #chars then
        total = total + gap
      end
    end
  end
  return total
end

local function apply_clock_highlights()
  vim.api.nvim_buf_clear_namespace(state.buf, ns_id, 0, -1)
  for r = 0, glyph_rows - 1 do
    vim.api.nvim_buf_set_extmark(state.buf, ns_id, state.glyph_row + r, state.clock_col, {
      end_col = state.clock_col + state.clock_total_width * 3,
      hl_group = 'JikanClock',
    })
  end
end

local function update_char_positions(chars, start_col)
  local col = start_col
  for i, ch in ipairs(chars) do
    state.char_cols[i] = col
    local g = glyphs[ch]
    if g then
      state.char_widths[i] = g.width
      col = col + g.width * 3
      if i < #chars then
        col = col + GAP * 3
      end
    end
  end
end

local function build_clock_row(chars, row_1indexed, colon_on)
  local parts = {}
  for i, ch in ipairs(chars) do
    local g = glyphs[ch]
    if g then
      local blank = string.rep(EMPTY, g.width)
      local row_text = (i == 3 and not colon_on) and blank or (g.rows[row_1indexed] or blank)
      parts[#parts + 1] = row_text
      if i < #chars then
        parts[#parts + 1] = string.rep(EMPTY, GAP)
      end
    end
  end
  return table.concat(parts)
end

local function build_and_highlight(chars, win, start_row, start_col, total_width)
  local win_height = vim.api.nvim_win_get_height(win)
  local pad_str = string.rep(' ', start_col)

  update_char_positions(chars, start_col)
  state.glyph_row = start_row - 1 -- 0-indexed
  state.last_chars = { chars[1], chars[2], chars[3], chars[4], chars[5] }
  state.clock_col = start_col
  state.clock_total_width = total_width

  local buf_lines = {}
  for _ = 1, win_height do
    buf_lines[#buf_lines + 1] = ''
  end

  for r = 1, glyph_rows do
    local row_idx = start_row + r - 1
    if row_idx >= 1 and row_idx <= win_height then
      buf_lines[row_idx] = pad_str .. build_clock_row(chars, r, state.colon_on)
    end
  end

  vim.api.nvim_set_option_value('modifiable', true, { buf = state.buf })
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, buf_lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = state.buf })

  apply_clock_highlights()
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
    glyphs, glyph_rows = load_glyphs()
  end

  local chars = get_time_chars()
  local total_width = calc_total_width(chars, GAP)

  local win_width = vim.api.nvim_win_get_width(win)
  local win_height = vim.api.nvim_win_get_height(win)
  local start_col = math.max(0, math.floor((win_width - total_width) / 2))
  local start_row = math.max(1, math.floor((win_height - glyph_rows) / 2))

  build_and_highlight(chars, win, start_row, start_col, total_width)
end

local function update_digits(new_chars)
  local old_end_col = state.clock_col + state.clock_total_width * 3
  for r = 0, glyph_rows - 1 do
    local text = build_clock_row(new_chars, r + 1, state.colon_on)
    vim.api.nvim_buf_set_text(
      state.buf,
      state.glyph_row + r,
      state.clock_col,
      state.glyph_row + r,
      old_end_col,
      { text }
    )
  end
  update_char_positions(new_chars, state.clock_col)
  state.clock_total_width = calc_total_width(new_chars, GAP)
  state.last_chars = { new_chars[1], new_chars[2], new_chars[3], new_chars[4], new_chars[5] }
end

local function update_colon()
  local colon_g = glyphs[':']
  if colon_g then
    local col = state.char_cols[3]
    local width = state.char_widths[3]
    local blank = string.rep(EMPTY, width)
    for r = 0, glyph_rows - 1 do
      local text = state.colon_on and (colon_g.rows[r + 1] or blank) or blank
      vim.api.nvim_buf_set_text(
        state.buf,
        state.glyph_row + r,
        col,
        state.glyph_row + r,
        col + width * 3,
        { text }
      )
    end
  end
end

local function tick()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  local new_chars = get_time_chars()
  state.colon_on = not state.colon_on

  local digit_changed = false
  for _, i in ipairs({ 1, 2, 4, 5 }) do
    if new_chars[i] ~= state.last_chars[i] then
      digit_changed = true
      break
    end
  end

  vim.api.nvim_set_option_value('modifiable', true, { buf = state.buf })
  if digit_changed then
    update_digits(new_chars)
  else
    update_colon()
  end
  vim.api.nvim_set_option_value('modifiable', false, { buf = state.buf })

  apply_clock_highlights()
end

local function stop_timer()
  if state.timer then
    vim.fn.timer_stop(state.timer)
    state.timer = nil
  end
end

local function resolve_luminance(bg_int)
  local r = math.floor(bg_int / 0x10000) % 0x100
  local g = math.floor(bg_int / 0x100) % 0x100
  local b = bg_int % 0x100
  local lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255
  return lum < 0.4 and COLOR_DARK or COLOR_LIGHT
end

local function resolve_color()
  if config.color then
    return config.color
  end

  local hl = vim.api.nvim_get_hl(0, { name = 'Normal' })
  if hl and hl.bg then
    return resolve_luminance(hl.bg)
  end

  return vim.o.background == 'light' and COLOR_LIGHT or COLOR_DARK
end

local function apply_hl()
  vim.api.nvim_set_hl(0, 'JikanClock', { fg = resolve_color() })
end

local function create_clock_buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  local buf_opts = {
    buftype = 'nofile',
    bufhidden = 'wipe',
    swapfile = false,
    filetype = 'jikan',
    modifiable = false,
  }
  for k, v in pairs(buf_opts) do
    vim.api.nvim_set_option_value(k, v, { buf = buf })
  end
  return buf
end

local function setup_autocmds(buf)
  local aug = vim.api.nvim_create_augroup('jikan_active', { clear = true })
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = aug,
    callback = apply_hl,
  })
  vim.api.nvim_create_autocmd('VimResized', {
    group = aug,
    buffer = buf,
    callback = draw,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = aug,
    buffer = buf,
    once = true,
    callback = function()
      stop_timer()
      vim.api.nvim_del_augroup_by_name('jikan_active')
    end,
  })
end

local function open()
  if vim.fn.argc() ~= 0 then
    return
  end

  apply_hl()

  local buf = create_clock_buffer()
  state.buf = buf
  state.colon_on = true

  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_exec_autocmds('BufEnter', { buffer = buf })

  draw()

  state.timer = vim.fn.timer_start(1200, function()
    tick()
  end, { ['repeat'] = -1 })

  setup_autocmds(buf)
end

function M.setup(opts)
  opts = opts or {}
  if opts.font then
    config.font = opts.font
  end
  if opts.color then
    config.color = opts.color
  end
  local aug = vim.api.nvim_create_augroup('jikan', { clear = true })
  vim.api.nvim_create_autocmd('VimEnter', {
    group = aug,
    once = true,
    callback = open,
  })
end

M._test = {
  resolve_luminance = resolve_luminance,
  process_glyph = process_glyph,
}

return M
