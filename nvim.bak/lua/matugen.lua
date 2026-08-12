 local M = {}

function M.setup()
  require('base16-colorscheme').setup({
    base00 = '#101418',
    base01 = '#1c2025',
    base02 = '#272a2f',
    base03 = '#8a919c',
    base04 = '#c0c7d2',
    base05 = '#e0e2e9',
    base06 = '#e0e2e9',
    base07 = '#e0e2e9',
    base08 = '#ffb4ab',
    base09 = '#f1b2ff',
    base0A = '#aec9ea',
    base0B = '#9fccff',
    base0C = '#f0b0ff',
    base0D = '#9ccaff',
    base0E = '#aec9ea',
    base0F = '#93000a',
  })

  local hi = function(group, opts)
    vim.api.nvim_set_hl(0, group, opts)
  end

  hi('TelescopeNormal',         { fg = '#e0e2e9',          bg = '#101418' })
  hi('TelescopeBorder',         { fg = '#8a919c',             bg = '#101418' })
  hi('TelescopePromptNormal',   { fg = '#e0e2e9',          bg = '#101418' })
  hi('TelescopePromptBorder',   { fg = '#8a919c',             bg = '#101418' })
  hi('TelescopePromptPrefix',   { fg = '#9fccff',             bg = '#101418' })
  hi('TelescopePromptCounter',  { fg = '#c0c7d2',  bg = '#101418' })
  hi('TelescopePromptTitle',    { fg = '#101418',             bg = '#9fccff' })
  hi('TelescopePreviewTitle',   { fg = '#101418',             bg = '#aec9ea' })
  hi('TelescopeResultsTitle',   { fg = '#101418',             bg = '#f1b2ff' })
  hi('TelescopeSelection',      { fg = '#e0e2e9',          bg = '#272a2f' })
  hi('TelescopeSelectionCaret', { fg = '#9fccff',             bg = '#272a2f' })
  hi('TelescopeMatching',       { fg = '#9fccff',             bold = true })
end

 -- Register a signal handler for SIGUSR1 (matugen updates)
 local signal = vim.uv.new_signal()
 signal:start(
   'sigusr1',
   vim.schedule_wrap(function()
     package.loaded['matugen'] = nil
     require('matugen').setup()
   end)
 )

 return M
