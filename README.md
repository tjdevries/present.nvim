# `present.nvim`

Hey, this is a plugin for presenting markdown files!!

# Setup

```lua
require("present").setup {
    -- Check source for options :)
    ...
}
```

# Features

- Use markdown to write slides
    - Break one "section" into multiple "slides"
        - Use `<!-- stop -->` comment to split a slide.
        - Can be configured with `opts.syntax.stop`
    - Comments are ignored
        - Use `%% comment` to comment a line
        - Can be configured with `opts.syntax.comment`
    - Execute code in code blocks!

```lua
print("Hello world", 37, true)
```

```python
# Configure this with `opts.executors`
print("yaayayayaya python")
```

# Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    'tjdevries/present.nvim'
}
```

# Usage

Use `:PresentStart` Command inside of a markdown file to start presenting.

Use `n`, and `p` to navigate markdow slides.
