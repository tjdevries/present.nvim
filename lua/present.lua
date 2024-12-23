local M = {}

local function create_floating_window(config)
  local buf = vim.api.nvim_create_buf(false, true) -- No file, scratch buffer
  local win = vim.api.nvim_open_win(buf, true, config)

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
      height = height - 5,
      style = "minimal",
      border = { " ", " ", " ", " ", " ", " ", " ", " ", },
      col = 8,
      row = 4,
    },
    -- footer = {}
  }
end

M.start_presentation = function(opts)
  opts = opts or {}
  opts.bufnr = opts.bufnr or 0

  local lines = vim.api.nvim_buf_get_lines(opts.bufnr, 0, -1, false)
  local parsed = parse_slides(lines)
  local current_slide = 1

  local windows = create_window_configurations()
  local background_float = create_floating_window(windows.background)
  local header_float = create_floating_window(windows.header)
  local body_float = create_floating_window(windows.body)

  vim.bo[header_float.buf].filetype = "markdown"
  vim.bo[body_float.buf].filetype = "markdown"

  local set_slide_content = function(idx)
    local width = vim.o.columns

    local slide = parsed.slides[idx]

    local padding = string.rep(" ", (width - #slide.title) / 2)
    local title = padding .. slide.title
    vim.api.nvim_buf_set_lines(header_float.buf, 0, -1, false, { title })
    vim.api.nvim_buf_set_lines(body_float.buf, 0, -1, false, slide.body)
  end

  vim.keymap.set("n", "n", function()
    current_slide = math.min(current_slide + 1, #parsed.slides)
    set_slide_content(current_slide)
  end, {
    buffer = body_float.buf
  })

  vim.keymap.set("n", "p", function()
    current_slide = math.max(current_slide - 1, 1)
    set_slide_content(current_slide)
  end, {
    buffer = body_float.buf
  })

  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(body_float.win, true)
  end, {
    buffer = body_float.buf
  })

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
    buffer = body_float.buf,
    callback = function()
      -- Reset the values when we are done with the presentation
      for option, config in pairs(restore) do
        vim.opt[option] = config.original
      end

      pcall(vim.api.nvim_win_close, background_float.win, true)
      pcall(vim.api.nvim_win_close, header_float.win, true)
    end
  })

  vim.api.nvim_create_autocmd("VimResized", {
    group = vim.api.nvim_create_augroup("present-resized", {}),
    callback = function()
      if not vim.api.nvim_win_is_valid(body_float.win) or body_float.win == nil then
        return
      end

      local updated = create_window_configurations()
      vim.api.nvim_win_set_config(header_float.win, updated.header)
      vim.api.nvim_win_set_config(background_float.win, updated.background)
      vim.api.nvim_win_set_config(body_float.win, updated.body)

      -- Re-calculates current slide contents
      set_slide_content(current_slide)
    end,
  })


  set_slide_content(current_slide)
end

-- vim.print(parse_slides {
--   "# Hello",
--   "this is something else",
--   "# World",
--   "this is another thing",
-- })
M.start_presentation { bufnr = 6 }

return M
