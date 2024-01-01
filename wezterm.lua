local wezterm = require 'wezterm'

local config = {}

if wezterm.config_builder then
  config = wezterm.config_builder()
end

-- https://gogh-co.github.io/Gogh/
config.color_scheme = 'Night (Gogh)'
config.hide_tab_bar_if_only_one_tab = true

return config