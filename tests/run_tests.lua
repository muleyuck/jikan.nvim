-- tests/run_tests.lua
-- Minimal zero-dependency test runner for jikan.nvim.
-- Designed to run via the -l flag (Neovim 0.9+); runtimepath is set by minimal_init.lua:
--   nvim --headless -u tests/minimal_init.lua -l tests/run_tests.lua

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local pass_count = 0
local fail_count = 0
local failures = {}

-- Each describe() call pushes one slot onto these stacks.
-- before_each/after_each fill the top slot with their callback.
-- it() iterates _before_stack outer→inner, _after_stack inner→outer.
local _before_stack = {}
local _after_stack = {}
local _current_prefix = '' -- accumulated "Outer / Inner / " prefix for test names

--------------------------------------------------------------------------------
-- DSL globals (describe / before_all / before_each / after_each / it)
--------------------------------------------------------------------------------

-- describe(label, fn): open a named scope for grouping tests.
-- Nesting is supported; the prefix accumulates across levels.
-- Uses pcall around fn() so that table.remove always runs even if fn() errors,
-- preventing stack corruption across subsequent spec files.
_G.describe = function(label, fn)
  local prev = _current_prefix
  _current_prefix = _current_prefix .. label .. ' / '
  table.insert(_before_stack, false)
  table.insert(_after_stack, false)
  local ok, err = pcall(fn)
  table.remove(_before_stack)
  table.remove(_after_stack)
  _current_prefix = prev
  if not ok then
    error(err, 0) -- re-raise after cleanup
  end
end

-- before_all(fn): run fn once immediately at parse time.
-- Equivalent to top-level code inside describe(); provided for readability.
_G.before_all = function(fn)
  fn()
end

-- before_each(fn): register fn to run before every it() in the current describe scope.
-- Only one fn per scope; a second call silently overwrites the first.
_G.before_each = function(fn)
  if #_before_stack > 0 then
    _before_stack[#_before_stack] = fn
  end
end

-- after_each(fn): register fn to run after every it() in the current describe scope.
-- Only one fn per scope; a second call silently overwrites the first.
_G.after_each = function(fn)
  if #_after_stack > 0 then
    _after_stack[#_after_stack] = fn
  end
end

-- it(name, fn): define a single test case.
-- Execution order:
--   1. before_each hooks, outer → inner. First failure aborts the test body.
--   2. fn(), unless a before_each already failed.
--   3. after_each hooks, inner → outer. Always runs; failure overrides a passing result.
_G.it = function(name, fn)
  local full_name = _current_prefix .. name

  -- Run before_each hooks (outer → inner); stop on first failure.
  local setup_err
  for _, bfn in ipairs(_before_stack) do
    if bfn then
      local ok, err = pcall(bfn)
      if not ok then
        setup_err = 'before_each: ' .. tostring(err)
        break
      end
    end
  end

  -- Run the test body, skipping it if setup already failed.
  local passed, err
  if setup_err then
    passed, err = false, setup_err
  else
    passed, err = pcall(fn)
  end

  -- Run after_each hooks (inner → outer); always runs for cleanup.
  -- An after_each failure overrides a passing result.
  for i = #_after_stack, 1, -1 do
    if _after_stack[i] then
      local aok, aerr = pcall(_after_stack[i])
      if not aok and passed then
        passed, err = false, 'after_each: ' .. tostring(aerr)
      end
    end
  end

  if passed then
    pass_count = pass_count + 1
    io.write('.')
  else
    fail_count = fail_count + 1
    table.insert(failures, { name = full_name, err = tostring(err) })
    io.write('F')
  end
end

--------------------------------------------------------------------------------
-- Assertions
--------------------------------------------------------------------------------

-- eq(expected, actual): assert deep equality via vim.deep_equal.
_G.eq = function(expected, actual)
  if not vim.deep_equal(expected, actual) then
    error(
      string.format('expected:\n  %s\ngot:\n  %s', vim.inspect(expected), vim.inspect(actual)),
      2
    )
  end
end

-- ok(v, msg): assert v is truthy.
_G.ok = function(v, msg)
  if not v then
    error(msg or 'expected truthy value', 2)
  end
end

-- not_ok(v, msg): assert v is falsy.
_G.not_ok = function(v, msg)
  if v then
    error(msg or 'expected falsy value', 2)
  end
end

-- error_matches(pat, fn): assert that fn() raises an error whose message matches pat (Lua pattern).
_G.error_matches = function(pat, fn)
  local passed, err = pcall(fn)
  if passed then
    error('expected error matching ' .. pat .. ', but no error was raised', 2)
  end
  if not tostring(err):find(pat) then
    error(string.format('expected error matching %s, got: %s', pat, tostring(err)), 2)
  end
end

--------------------------------------------------------------------------------
-- Collection and execution
--------------------------------------------------------------------------------

-- Discover all *_spec.lua files under tests/spec/.
-- Requires nvim to be invoked from the repository root (cwd = repo root).
local spec_files = vim.fn.globpath('tests/spec', '**/*_spec.lua', true, true)

if #spec_files == 0 then
  io.write('No spec files found under tests/spec/ — check that nvim is run from the repo root\n')
  vim.cmd('cq')
end

for _, f in ipairs(spec_files) do
  -- Reset the describe context between files so each file starts clean.
  _before_stack = {}
  _after_stack = {}
  _current_prefix = ''
  dofile(f)
end

--------------------------------------------------------------------------------
-- Report
--------------------------------------------------------------------------------

io.write('\n')
for _, e in ipairs(failures) do
  print('FAIL: ' .. e.name)
  print('  ' .. e.err:gsub('\n', '\n  '))
end
print(string.format('%d passed, %d failed', pass_count, fail_count))

if fail_count > 0 then
  vim.cmd('cq')
else
  vim.cmd('qa!')
end
