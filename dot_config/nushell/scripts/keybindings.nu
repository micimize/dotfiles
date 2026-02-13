# Vi-mode keybinding customizations
# Mirrors the ble.sh keybindings from the archived dot_blerc
# Uses ++= to append to (not overwrite) nushell's default keybindings

$env.config.keybindings ++= [
  # Ctrl-C: discard current line in both insert and normal mode
  {
    name: discard_line
    modifier: control
    keycode: char_c
    mode: [vi_insert vi_normal]
    event: [
      { edit: Clear }
    ]
  }
  # Ctrl-R: reverse history search in both vi modes
  {
    name: history_search
    modifier: control
    keycode: char_r
    mode: [vi_insert vi_normal]
    event: {
      send: SearchHistory
    }
  }
  # Tab: completion menu (open → cycle → inline-complete)
  {
    name: completion_menu
    modifier: none
    keycode: tab
    mode: [vi_insert]
    event: {
      until: [
        { send: menu name: completion_menu }
        { send: menunext }
        { edit: complete }
      ]
    }
  }
  # Shift-Tab: completion menu previous
  {
    name: completion_previous
    modifier: shift
    keycode: backtab
    mode: [vi_insert]
    event: {
      send: menuprevious
    }
  }
]
