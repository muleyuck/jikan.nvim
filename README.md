[![unit-test](https://github.com/muleyuck/jikan.nvim/actions/workflows/unit-test.yml/badge.svg)](https://github.com/muleyuck/jikan.nvim/actions/workflows/unit-test.yml)
![Software License](https://img.shields.io/badge/license-MIT-brightgreen.svg?style=flat-square)
[![Release](https://img.shields.io/github/release/muleyuck/jikan.nvim.svg)](https://github.com/muleyuck/jikan.nvim/releases/latest)

# jikan.nvim

Braille art clock on your Neovim start screen.

jikan.nvim displays the current time in braille characters when you open Neovim without a file. No configuration required — it just works.

![demo](https://github.com/user-attachments/assets/dbc21529-9528-4a94-9f0e-713ee9ecf2af)

## Features

- Braille art clock shown automatically on startup
- Blinking colon for a live feel
- Clock color auto-detected from your colorscheme background
- Horizontally and vertically centered in any window size
- Skipped automatically when opening a file (`nvim file.txt`)
- Zero configuration required

## Requirements

- Neovim >= 0.9

## Installation

### lazy.nvim

```lua
{
  'muleyuck/jikan.nvim',
  lazy = false,
  opts = {},
}
```

### vim-plug

```vim
Plug 'muleyuck/jikan.nvim'
```

Then in your `init.lua`:

```lua
require('jikan').setup()
```

### packer.nvim

```lua
use {
  'muleyuck/jikan.nvim',
  config = function()
    require('jikan').setup()
  end,
}
```

### mini.deps

```lua
MiniDeps.add('muleyuck/jikan.nvim')
require('jikan').setup()
```

### Manual

```sh
cd ~/.config/nvim/pack/plugins/start
git clone https://github.com/muleyuck/jikan.nvim
```

Then in your `init.lua`:

```lua
require('jikan').setup()
```

## Configuration

No configuration is required. If you want to customize, the following options are available:

```lua
require('jikan').setup({
  -- Font for the braille art. Built-in: 'Inter' (default), 'Digital'
  font = 'Inter',

  -- Fixed foreground color for the clock (e.g. '#AED6F1').
  -- When nil, the color is auto-detected from the colorscheme background.
  color = nil,
})
```

## Highlights

jikan.nvim defines one highlight group:

| Group        | Used for         |
|--------------|------------------|
| `JikanClock` | Clock foreground |

The color is set automatically — light on dark backgrounds, dark on light backgrounds. To override:

```lua
vim.api.nvim_set_hl(0, 'JikanClock', { fg = '#your-color' })
```

Or pass `color` in `setup()` to fix it permanently.

## LICENSE

[The MIT License](https://github.com/muleyuck/jikan.nvim/blob/main/LICENSE)
