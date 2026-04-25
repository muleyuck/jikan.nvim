local jikan = require('jikan')
local resolve_luminance = jikan._test.resolve_luminance
local process_glyph = jikan._test.process_glyph

-- 3-byte ASCII strings stand in for braille cells so width = #line / 3 works correctly.
local E = 'EEE' -- empty cell placeholder
local A = 'AAA' -- content cell placeholder

local function cells(...)
  local t = {}
  for _, c in ipairs({ ... }) do
    t[#t + 1] = c
  end
  return table.concat(t)
end

--------------------------------------------------------------------------------
-- resolve_luminance
--------------------------------------------------------------------------------

describe('resolve_luminance', function()
  -- Kept: uniquely kills r/g channel extraction mutations (0 * 0x10000 = 0 always, but
  -- 136 * 0x10000 mod 256 = 0 too — however, the changed lum shifts the result branch)
  it('returns dark color when luminance >= 0.4', function()
    -- r=g=b=136: lum = 136/255 ≈ 0.533
    eq('#1A4A7A', resolve_luminance(0x888888))
  end)

  it('returns light color just below the 0.4 boundary', function()
    -- r=g=b=101: lum = 101/255 ≈ 0.396 < 0.4
    eq('#AED6F1', resolve_luminance(0x656565))
  end)

  it('returns light color at the floating-point boundary (0x666666)', function()
    -- r=g=b=102: mathematically lum = 102/255 = 0.4, but floating-point coefficients
    -- (0.299 + 0.587 + 0.114 < 1.0 in double) push it just below 0.4
    eq('#AED6F1', resolve_luminance(0x666666))
  end)

  it('returns light color for pure red with low luminance', function()
    -- r=80, g=0, b=0: lum = 0.299*80/255 ≈ 0.094
    -- verifies R coefficient (0.299) is applied to the R channel
    eq('#AED6F1', resolve_luminance(0x500000))
  end)

  it('returns dark color for green-dominant background', function()
    -- r=0, g=204, b=0: lum = 0.587*204/255 ≈ 0.470 >= 0.4
    -- verifies G coefficient (0.587, highest weight) is applied to the G channel;
    -- gray-only tests cannot catch a R↔G coefficient swap bug
    eq('#1A4A7A', resolve_luminance(0x00CC00))
  end)
end)

--------------------------------------------------------------------------------
-- process_glyph
--------------------------------------------------------------------------------

describe('process_glyph', function()
  it('no padding when rows equal max_rows', function()
    local raw = { cells(A, A), cells(A, A) } -- 2 rows, width=2
    local result = process_glyph(raw, 2, E)
    eq(2, #result.rows)
    eq(2, result.width)
    eq(cells(A, A), result.rows[1])
    eq(cells(A, A), result.rows[2])
  end)

  it('even padding: 2-row gap adds 1 row top and bottom', function()
    local raw = { cells(A, A) } -- 1 row, max_rows=3, gap=2
    local result = process_glyph(raw, 3, E)
    eq(3, #result.rows)
    eq(cells(E, E), result.rows[1]) -- pad top
    eq(cells(A, A), result.rows[2]) -- content
    eq(cells(E, E), result.rows[3]) -- pad bottom
  end)

  it('odd padding: 3-row gap adds 1 top and 2 bottom (floor behavior)', function()
    local raw = { cells(A, A) } -- 1 row, max_rows=4, gap=3
    -- pad_top = floor(3/2) = 1, pad_bot = 3 - 1 = 2
    local result = process_glyph(raw, 4, E)
    eq(4, #result.rows)
    eq(cells(E, E), result.rows[1]) -- 1 pad top
    eq(cells(A, A), result.rows[2]) -- content
    eq(cells(E, E), result.rows[3]) -- 2 pad bottom
    eq(cells(E, E), result.rows[4])
  end)

  it('short rows are right-padded with empty cells', function()
    -- row 1 is 2 cells wide, row 2 is 1 cell wide → row 2 gets 1 empty cell appended
    local raw = { cells(A, A), A }
    local result = process_glyph(raw, 2, E)
    eq(2, result.width)
    eq(cells(A, A), result.rows[1])
    eq(cells(A, E), result.rows[2])
  end)

  it('single-row glyph is padded to max_rows=5 with 2 rows top and bottom', function()
    local raw = { cells(A, A) } -- 1 row, max_rows=5, gap=4
    -- pad_top = floor(4/2) = 2, pad_bot = 4 - 2 = 2
    local result = process_glyph(raw, 5, E)
    eq(5, #result.rows)
    eq(cells(E, E), result.rows[1])
    eq(cells(E, E), result.rows[2])
    eq(cells(A, A), result.rows[3])
    eq(cells(E, E), result.rows[4])
    eq(cells(E, E), result.rows[5])
  end)

  it('unequal-width rows with vertical padding use max width for pad rows', function()
    -- 2 content rows (widths 2 and 1), max_rows=4 (gap=2, pad_top=1, pad_bot=1)
    -- padding rows must use width=2 (the maximum), not width=1 (the narrower row)
    local raw = { cells(A, A), A }
    local result = process_glyph(raw, 4, E)
    eq(4, #result.rows)
    eq(2, result.width)
    eq(cells(E, E), result.rows[1]) -- pad row: must be width=2, not width=1
    eq(cells(A, A), result.rows[2])
    eq(cells(A, E), result.rows[3]) -- short row right-padded to width=2
    eq(cells(E, E), result.rows[4]) -- pad row: must be width=2
  end)
end)
