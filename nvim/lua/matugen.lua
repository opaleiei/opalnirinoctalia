 local M = {}

function M.setup()
  require('base16-colorscheme').setup({
    base00 = '#131314',
    base01 = '#1f2020',
    base02 = '#2a2a2a',
    base03 = '#8d9194',
    base04 = '#c4c7ca',
    base05 = '#e4e2e2',
    base06 = '#e4e2e2',
    base07 = '#e4e2e2',
    base08 = '#ffb4ab',
    base09 = '#f8ebfa',
    base0A = '#c4c7ca',
    base0B = '#e5f0f8',
    base0C = '#cec3d1',
    base0D = '#bdc8d0',
    base0E = '#c4c7ca',
    base0F = '#93000a',
  })

  local hi = function(group, opts)
    vim.api.nvim_set_hl(0, group, opts)
  end

  hi('TelescopeNormal',         { fg = '#e4e2e2',          bg = '#131314' })
  hi('TelescopeBorder',         { fg = '#8d9194',             bg = '#131314' })
  hi('TelescopePromptNormal',   { fg = '#e4e2e2',          bg = '#131314' })
  hi('TelescopePromptBorder',   { fg = '#8d9194',             bg = '#131314' })
  hi('TelescopePromptPrefix',   { fg = '#e5f0f8',             bg = '#131314' })
  hi('TelescopePromptCounter',  { fg = '#c4c7ca',  bg = '#131314' })
  hi('TelescopePromptTitle',    { fg = '#131314',             bg = '#e5f0f8' })
  hi('TelescopePreviewTitle',   { fg = '#131314',             bg = '#c4c7ca' })
  hi('TelescopeResultsTitle',   { fg = '#131314',             bg = '#f8ebfa' })
  hi('TelescopeSelection',      { fg = '#e4e2e2',          bg = '#2a2a2a' })
  hi('TelescopeSelectionCaret', { fg = '#e5f0f8',             bg = '#2a2a2a' })
  hi('TelescopeMatching',       { fg = '#e5f0f8',             bold = true })
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
