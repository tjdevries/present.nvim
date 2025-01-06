# `present.nvim`

Hey, this is a plugin for presenting markdown files!!

# Features: Neovim Lua Execution

Can execute code in lua blocks, when you have them in a slide

```lua
print("Hello world", 37, true)
```

# Features: Other Langs

Can execute code in Language blocks, when you have them in a slide.

You may need to configure this with `opts.executors`, only have Lua, Python, Javascript, and Rust by default.

```python
print("yaayayayaya python")
```

# Comments

Lines starting with **--** are considered as comments, and they are not exposed
in presentation.

# Usage

```lua
require("present").start_presentation {}
```

Use `n`, and `p` to navigate markdow slides.

Or use `:PresentStart` Command

# Credits

teej_dv
