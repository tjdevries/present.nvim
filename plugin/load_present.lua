vim.api.nvim_create_user_command("PresentStart", function()
  -- Easy Reloading
  package.loaded["present"] = nil

  require("present").start_presentation()
end, {})
