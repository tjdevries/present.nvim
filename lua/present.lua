local M = {}

local section_query = vim.treesitter.query.parse("markdown", [[(section) @section]])
local codeblock_query = vim.treesitter.query.parse("markdown", [[(fenced_code_block) @codeblock]])

-- TODO: This was returning goofy stuff
-- local language_query =
--   vim.treesitter.query.parse("markdown", [[(fenced_code_block (info_string (language) @language))]])

local function create_floating_window(config, enter)
  if enter == nil then
    enter = false
  end

  local buf = vim.api.nvim_create_buf(false, true) -- No file, scratch buffer
  local win = vim.api.nvim_open_win(buf, enter or false, config)

  return { buf = buf, win = win }
end

--- Default executor for lua code
---@param block present.Block
local execute_lua_code = function(block)
  -- Override the default print function, to capture all of the output
  -- Store the original print function
  local original_print = print

  local output = {}

  -- Redefine the print function
  print = function(...)
    local args = { ... }
    local message = table.concat(vim.tbl_map(tostring, args), "\t")
    table.insert(output, message)
  end

  -- Call the provided function
  local chunk = loadstring(block.body)
  pcall(function()
    if not chunk then
      table.insert(output, " <<<BROKEN CODE>>>")
    else
      chunk()
    end

    return output
  end)

  -- Restore the original print function
  print = original_print

  return output
end

--- Default executor for Rust code
---@param block present.Block
local execute_rust_code = function(block)
  local tempfile = vim.fn.tempname() .. ".rs"
  local outputfile = tempfile:sub(1, -4)
  vim.fn.writefile(vim.split(block.body, "\n"), tempfile)
  local result = vim.system({ "rustc", tempfile, "-o", outputfile }, { text = true }):wait()
  if result.code ~= 0 then
    local output = vim.split(result.stderr, "\n")
    return output
  end
  result = vim.system({ outputfile }, { text = true }):wait()
  return vim.split(result.stdout, "\n")
end

M.create_system_executor = function(program)
  return function(block)
    local tempfile = vim.fn.tempname()
    vim.fn.writefile(vim.split(block.body, "\n"), tempfile)
    local result = vim.system({ program, tempfile }, { text = true }):wait()
    return vim.split(result.stdout, "\n")
  end
end

local defaults = {
  executors = {
    lua = execute_lua_code,
    javascript = M.create_system_executor("node"),
    python = M.create_system_executor("python"),
    rust = execute_rust_code,
  },
}

---@class present.Options
---@field executors table<string, function>: The executors for the different languages
---@field syntax present.SyntaxOptions: The syntax for the plugin

---@class present.SyntaxOptions
---@field comment string?: The prefix for comments, will skip lines that start with this
---@field stop string?: The stop comment, will stop slide when found. Note: Is a Lua Pattern

---@type present.Options
local options = {
  syntax = {
    comment = "%%",
    stop = "<!%-%-%s*stop%s*%-%->",
  },
  executors = {},
}

--- Setup the plugin
---@param opts present.Options
M.setup = function(opts)
  options = vim.tbl_deep_extend("force", defaults, opts or {})
end

---@class present.Slides
---@field slides present.Slide[]: The slides of the file

---@class present.Slide
---@field title string: The title of the slide
---@field body string[]: The body of slide
---@field blocks present.Block[]: A codeblock inside of a slide

---@class present.Block
---@field language string: The language of the codeblock
---@field body string: The body of the codeblock
---@field start_row integer: The start row of the codeblock
---@field end_row integer: The end row of the codeblock

--- Takes some lines and parses them
---@param lines string[]: The lines in the buffer
---@return present.Slides
local parse_slides = function(lines)
  local contents = table.concat(lines, "\n") .. "\n"
  local parser = vim.treesitter.get_string_parser(contents, "markdown")
  local root = parser:parse()[1]:root()

  local slides = { slides = {} }

  local create_empty_slide = function()
    return { title = "", body = {}, blocks = {} }
  end

  local add_line_to_block = function(slide, line)
    if not line then
      return
    end

    -- Trim trailing whitespace, it can have weird highlighting and whatnot
    line = line:gsub("%s*$", "")
    table.insert(slide.body, line)
  end

  local get_block = function(codeblocks, idx)
    for _, codeblock in ipairs(codeblocks) do
      if idx >= codeblock.start_row and idx <= codeblock.end_row then
        return codeblock
      end
    end

    return nil
  end

  local current_slide = create_empty_slide()
  for _, node in section_query:iter_captures(root, contents, 0, -1) do
    if #current_slide.title > 0 then
      table.insert(slides.slides, current_slide)
      current_slide = create_empty_slide()
    end

    local start_row, _, end_row, _ = node:range()
    current_slide.title = lines[start_row + 1]
    local codeblocks = vim
      .iter(codeblock_query:iter_captures(root, contents, start_row, end_row))
      :map(function(_, n)
        local s, _, e, _ = n:range()
        local language = vim.trim(string.sub(lines[s + 1], 4))
        return {
          language = language,
          body = table.concat(vim.list_slice(lines, s + 2, e - 1), "\n"),
          start_row = s + 1,
          end_row = e,
        }
      end)
      :totable()

    local comment = options.syntax.comment
    local stop = options.syntax.stop

    local process_line = function(idx)
      local line = lines[idx]
      local block = get_block(codeblocks, idx)

      -- Only do our comments/splits/etc if we are not in a codeblock
      if not block then
        -- Skip comment lines
        if comment and vim.startswith(line, comment) then
          return
        end

        -- Split on `stop` comments
        if stop and line:find(stop) then
          line = line:gsub(stop, "")
          add_line_to_block(current_slide, line)
          table.insert(slides.slides, current_slide)
          current_slide = vim.deepcopy(current_slide)
          return
        end

        return add_line_to_block(current_slide, line)
      end

      -- Only add code blocks to the current slide if we have
      -- actually reached them (this could not happen because of stop comments)
      if idx == block.start_row then
        table.insert(current_slide.blocks, block)
      end

      -- GIVE ME THE CODE AND GIVE IT TO ME RAW
      add_line_to_block(current_slide, lines[idx])
    end

    -- Process the lines: Add one for row->line, add one to skip the header
    local start_of_section = start_row + 2
    for idx = start_of_section, end_row do
      process_line(idx)
    end
  end

  -- Add the last slide, won't happen in the loop
  --  Could probably switch to do-while loop and make Prime happy,
  --  but that would make me sad.
  table.insert(slides.slides, current_slide)

  return slides
end

local create_window_configurations = function()
  local width = vim.o.columns
  local height = vim.o.lines

  local header_height = 1 + 2 -- 1 + border
  local footer_height = 1 -- 1, no border
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
      border = { " ", " ", " ", " ", " ", " ", " ", " " },
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
    buffer = state.floats.body.buf,
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

    local footer = string.format("  %d / %d | %s", state.current_slide, #state.parsed.slides, state.title)
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

  present_keymap("n", "X", function()
    local slide = state.parsed.slides[state.current_slide]
    -- TODO: Make a way for people to execute this for other languages
    local block = slide.blocks[1]
    if not block then
      print("No blocks on this page")
      return
    end

    local executor = options.executors[block.language]
    if not executor then
      print("No valid executor for this language")
      return
    end

    -- Table to capture print messages
    local output = { "# Code", "", "```" .. block.language }
    vim.list_extend(output, vim.split(block.body, "\n"))
    table.insert(output, "```")

    table.insert(output, "")
    table.insert(output, "# Output")
    table.insert(output, "")
    table.insert(output, "```")
    vim.list_extend(output, executor(block))
    table.insert(output, "```")

    local buf = vim.api.nvim_create_buf(false, true) -- No file, scratch buffer
    local temp_width = math.floor(vim.o.columns * 0.8)
    local temp_height = math.floor(vim.o.lines * 0.8)
    vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      style = "minimal",
      noautocmd = true,
      width = temp_width,
      height = temp_height,
      row = math.floor((vim.o.lines - temp_height) / 2),
      col = math.floor((vim.o.columns - temp_width) / 2),
      border = "rounded",
    })

    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, output)
  end)

  local restore = {
    cmdheight = {
      original = vim.o.cmdheight,
      present = 0,
    },
    guicursor = {
      original = vim.o.guicursor,
      present = "n:NormalFloat",
    },
    wrap = {
      original = vim.o.wrap,
      present = true,
    },
    breakindent = {
      original = vim.o.breakindent,
      present = true,
    },
    breakindentopt = {
      original = vim.o.breakindentopt,
      present = "list:-1",
    },
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
    end,
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
-- M.start_presentation { bufnr = 1 }

M._parse_slides = parse_slides

return M
