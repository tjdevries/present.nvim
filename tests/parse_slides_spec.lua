---@diagnostic disable: undefined-field

local parse = require "present"._parse_slides

local eq = assert.are.same

describe("present.parse_slides", function()
  it("should parse an empty file", function()
    eq({
      slides = {
        {
          title = '',
          body = {},
          blocks = {},
        }
      }
    }, parse {})
  end)

  it("should parse a file with one slide", function()
    eq({
      slides = {
        {
          title = '# This is the first slide',
          body = { "This is the body" },
          blocks = {},
        }
      }
    }, parse {
      "# This is the first slide",
      "This is the body"
    })
  end)

  it("should parse a file with one slide, and a block", function()
    local results = parse {
      "# This is the first slide",
      "This is the body",
      "```lua",
      "print('hi')",
      "```",
    }

    -- Should only have one slide
    eq(1, #results.slides)

    local slide = results.slides[1]
    eq('# This is the first slide', slide.title)
    eq({
      "This is the body",
      "```lua",
      "print('hi')",
      "```",
    }, slide.body)

    eq({
      language = 'lua',
      body = "print('hi')",
    }, slide.blocks[1])
  end)

  it('should not treat # inside code blocks as new slides', function()
    local results = parse {
      '# Main slide',
      'Some content',
      '```bash',
      '#this is a comment',
      'echo hello',
      '```',
      'More content',
    }

    -- Should only have one slide
    eq(1, #results.slides)

    local slide = results.slides[1]
    eq('# Main slide', slide.title)
    eq({
      'Some content',
      '```bash',
      '#this is a comment',
      'echo hello',
      '```',
      'More content',
    }, slide.body)
    eq({
      language = 'bash',
      body = '#this is a comment\necho hello',
    }, slide.blocks[1])
  end)
end)
