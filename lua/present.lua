local M = {}

local function create_floating_window(config, enter)
  if enter == nil then
    enter = false
  end

  local buf = vim.api.nvim_create_buf(false, true) -- No file, scratch buffer
  local win = vim.api.nvim_open_win(buf, enter or false, config)

  return { buf = buf, win = win }
end


M.setup = function()
  -- nothing
end

---@class present.Slides
---@field slides present.Slide[]: The slides of the file

---@class present.Slide
---@field title string: The title of the slide
---@field body string[]: The body of slide

--- Takes some lines and parses them
---@param lines string[]: The lines in the buffer
---@return present.Slides
local parse_slides = function(lines)
  local slides = { slides = {} }
  local current_slide = {
    title = "",
    body = {}
  }

  local separator = "^#"

  for _, line in ipairs(lines) do
    if line:find(separator) then
      if #current_slide.title > 0 then
        table.insert(slides.slides, current_slide)
      end

      current_slide = {
        title = line,
        body = {}
      }
    else
      table.insert(current_slide.body, line)
    end
  end

  table.insert(slides.slides, current_slide)

  return slides
end

local create_window_configurations = function()
  local width = vim.o.columns
  local height = vim.o.lines

  local header_height = 1 + 2                                        -- 1 + border
  local footer_height = 1                                            -- 1, no border
  local body_height = height - header_height - footer_height - 2 - 1 -- for our own border

  return {
    background = {
      relative = "editor",
      width = width,
      height = height,
      style = "minimal",
      col = 0,
      row = 0,
      zindex = 1,
    },
    header = {
      relative = "editor",
      width = width,
      height = 1,
      style = "minimal",
      border = "rounded",
      col = 0,
      row = 0,
      zindex = 2,
    },
    body = {
      relative = "editor",
      width = width - 8,
      height = body_height,
      style = "minimal",
      border = { " ", " ", " ", " ", " ", " ", " ", " ", },
      col = 8,
      row = 4,
    },
    footer = {
      relative = "editor",
      width = width,
      height = 1,
      style = "minimal",
      -- TODO: Just a border on the top?
      -- border = "rounded",
      col = 0,
      row = height - 1,
      zindex = 3,
    },
  }
end

local state = {
  parsed = {},
  current_slide = 1,
  floats = {},
}

local foreach_float = function(cb)
  for name, float in pairs(state.floats) do
    cb(name, float)
  end
end

local present_keymap = function(mode, key, callback)
  vim.keymap.set(mode, key, callback, {
    buffer = state.floats.body.buf
  })
end

M.start_presentation = function(opts)
  opts = opts or {}
  opts.bufnr = opts.bufnr or 0

  local lines = vim.api.nvim_buf_get_lines(opts.bufnr, 0, -1, false)
  state.parsed = parse_slides(lines)
  state.current_slide = 1
  state.title = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(opts.bufnr), ":t")

  local windows = create_window_configurations()
  state.floats.background = create_floating_window(windows.background)
  state.floats.header = create_floating_window(windows.header)
  state.floats.footer = create_floating_window(windows.footer)
  state.floats.body = create_floating_window(windows.body, true)

  foreach_float(function(_, float)
    vim.bo[float.buf].filetype = "markdown"
  end)

  local set_slide_content = function(idx)
    local width = vim.o.columns

    local slide = state.parsed.slides[idx]

    local padding = string.rep(" ", (width - #slide.title) / 2)
    local title = padding .. slide.title
    vim.api.nvim_buf_set_lines(state.floats.header.buf, 0, -1, false, { title })
    vim.api.nvim_buf_set_lines(state.floats.body.buf, 0, -1, false, slide.body)

    local footer = string.format(
      "  %d / %d | %s",
      state.current_slide,
      #(state.parsed.slides),
      state.title
    )
    vim.api.nvim_buf_set_lines(state.floats.footer.buf, 0, -1, false, { footer })
  end

  present_keymap("n", "n", function()
    state.current_slide = math.min(state.current_slide + 1, #state.parsed.slides)
    set_slide_content(state.current_slide)
  end)

  present_keymap("n", "p", function()
    state.current_slide = math.max(state.current_slide - 1, 1)
    set_slide_content(state.current_slide)
  end)

  present_keymap("n", "q", function()
    vim.api.nvim_win_close(state.floats.body.win, true)
  end)

  local restore = {
    cmdheight = {
      original = vim.o.cmdheight,
      present = 0
    }
  }

  -- Set the options we want during presentation
  for option, config in pairs(restore) do
    vim.opt[option] = config.present
  end

  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = state.floats.body.buf,
    callback = function()
      -- Reset the values when we are done with the presentation
      for option, config in pairs(restore) do
        vim.opt[option] = config.original
      end

      foreach_float(function(_, float)
        pcall(vim.api.nvim_win_close, float.win, true)
      end)
    end
  })

  vim.api.nvim_create_autocmd("VimResized", {
    group = vim.api.nvim_create_augroup("present-resized", {}),
    callback = function()
      if not vim.api.nvim_win_is_valid(state.floats.body.win) or state.floats.body.win == nil then
        return
      end

      local updated = create_window_configurations()
      foreach_float(function(name, _)
        vim.api.nvim_win_set_config(state.floats[name].win, updated[name])
      end)

      -- Re-calculates current slide contents
      set_slide_content(state.current_slide)
    end,
  })


  set_slide_content(state.current_slide)
end

-- vim.print(parse_slides {
--   "# Hello",
--   "this is something else",
--   "# World",
--   "this is another thing",
-- })
-- M.start_presentation { bufnr = 241 }

M._parse_slides = parse_slides

return M
