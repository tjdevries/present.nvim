---@diagnostic disable: undefined-field

local parse = require("present")._parse_slides

local eq = assert.are.same

describe("present.parse_slides", function()
  it("should parse an empty file", function()
    local slides = parse({ "" })

    eq({
      slides = {
        {
          title = "",
          body = {},
          blocks = {},
        },
      },
    }, slides)
  end)

  it("should parse a file with one slide", function()
    eq(
      {
        {
          title = "# This is the first slide",
          body = { "This is the body" },
          blocks = {},
        },
      },
      parse({
        "# This is the first slide",
        "This is the body",
      }).slides
    )
  end)

  it("should parse a file with one slide, and a block", function()
    local results = parse({
      "# This is the first slide",
      "This is the body",
      "```lua",
      "print('hi')",
      "```",
    })

    -- Should only have one slide
    eq(1, #results.slides)

    local slide = results.slides[1]
    eq("# This is the first slide", slide.title)
    eq({
      "This is the body",
      "```lua",
      "print('hi')",
      "```",
    }, slide.body)

    eq({
      language = "lua",
      body = "print('hi')",
      start_row = 3,
      end_row = 5,
    }, slide.blocks[1])
  end)

  it("should use stop comment to stop slides", function()
    local results = parse({
      "# This is the first slide",
      "This is the body <!-- stop -->",
      "This is the middle line <!--    stop -->",
      "This is the final line",
    })

    -- Should only have two slides (even though only one separator)
    eq(3, #results.slides)

    local slide = results.slides[1]
    eq("# This is the first slide", slide.title)
    eq({ "This is the body" }, slide.body)

    slide = results.slides[2]
    eq("# This is the first slide", slide.title)
    eq({ "This is the body", "This is the middle line" }, slide.body)

    slide = results.slides[3]
    eq("# This is the first slide", slide.title)
    eq({ "This is the body", "This is the middle line", "This is the final line" }, slide.body)
  end)

  it("should use ignore comments", function()
    local results = parse({
      "# This is the first slide",
      "%% This is a comment",
      "This is the body <!-- stop -->",
      "This is the final line",
    })

    -- Should only have two slides (even though only one separator)
    eq(2, #results.slides)

    local slide = results.slides[1]
    eq("# This is the first slide", slide.title)
    eq({ "This is the body" }, slide.body)

    slide = results.slides[2]
    eq("# This is the first slide", slide.title)
    eq({ "This is the body", "This is the final line" }, slide.body)
  end)

  it("should not interepret # as a slide inside of code block", function()
    local results = parse({
      "# This is the first slide",
      "This is the body",
      "```c",
      "#include <stdio.h>",
      "int main() {}",
      "```",
      "Same slide",
    })

    -- Should only have two slides (even though only one separator)
    eq(1, #results.slides)

    local slide = results.slides[1]
    eq("# This is the first slide", slide.title)
    eq({
      "This is the body",
      "```c",
      "#include <stdio.h>",
      "int main() {}",
      "```",
      "Same slide",
    }, slide.body)
  end)
end)
