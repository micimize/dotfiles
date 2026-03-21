# Catppuccin Mocha color configuration for nushell table rendering
# Reference: https://github.com/catppuccin/nushell

let catppuccin_mocha = {
  separator: "#585b70"                              # surface2
  leading_trailing_space_bg: { attr: n }
  header: { fg: "#f9e2af" attr: b }                 # yellow, bold
  empty: "#6c7086"                                  # overlay0
  bool: "#94e2d5"                                   # teal
  int: "#89b4fa"                                    # blue
  float: "#89b4fa"                                  # blue
  filesize: "#94e2d5"                               # teal
  duration: "#94e2d5"                               # teal
  date: "#cba6f7"                                   # mauve
  range: "#89b4fa"                                  # blue
  string: "#cdd6f4"                                 # text
  nothing: "#6c7086"                                # overlay0
  binary: "#cba6f7"                                 # mauve
  cell_path: "#cdd6f4"                              # text
  row_index: { fg: "#a6e3a1" attr: b }              # green, bold
  record: "#cdd6f4"                                 # text
  list: "#cdd6f4"                                   # text
  block: "#cdd6f4"                                  # text
  hints: "#6c7086"                                  # overlay0
  search_result: { fg: "#1e1e2e" bg: "#f9e2af" }    # base on yellow

  shape_and: { fg: "#cba6f7" attr: b }              # mauve
  shape_binary: { fg: "#cba6f7" attr: b }           # mauve
  shape_block: { fg: "#89b4fa" attr: b }            # blue
  shape_bool: "#94e2d5"                             # teal
  shape_closure: { fg: "#a6e3a1" attr: b }          # green
  shape_custom: "#a6e3a1"                           # green
  shape_datetime: { fg: "#94e2d5" attr: b }         # teal
  shape_directory: "#94e2d5"                        # teal
  shape_external: "#94e2d5"                         # teal
  shape_externalarg: { fg: "#a6e3a1" attr: b }      # green
  shape_external_resolved: { fg: "#94e2d5" attr: b } # teal
  shape_filepath: "#94e2d5"                         # teal
  shape_flag: { fg: "#89b4fa" attr: b }             # blue
  shape_float: { fg: "#cba6f7" attr: b }            # mauve
  shape_garbage: { fg: "#cdd6f4" bg: "#f38ba8" attr: b } # text on red
  shape_glob_interpolation: { fg: "#94e2d5" attr: b } # teal
  shape_globpattern: { fg: "#94e2d5" attr: b }      # teal
  shape_int: { fg: "#cba6f7" attr: b }              # mauve
  shape_internalcall: { fg: "#94e2d5" attr: b }     # teal
  shape_keyword: { fg: "#cba6f7" attr: b }          # mauve
  shape_list: { fg: "#94e2d5" attr: b }             # teal
  shape_literal: "#89b4fa"                          # blue
  shape_match_pattern: "#a6e3a1"                    # green
  shape_matching_brackets: { attr: u }
  shape_nothing: "#94e2d5"                          # teal
  shape_operator: "#f9e2af"                         # yellow
  shape_or: { fg: "#cba6f7" attr: b }               # mauve
  shape_pipe: { fg: "#cba6f7" attr: b }             # mauve
  shape_range: { fg: "#f9e2af" attr: b }            # yellow
  shape_raw_string: { fg: "#cdd6f4" attr: b }       # text
  shape_record: { fg: "#94e2d5" attr: b }           # teal
  shape_redirection: { fg: "#cba6f7" attr: b }      # mauve
  shape_signature: { fg: "#a6e3a1" attr: b }        # green
  shape_string: "#a6e3a1"                           # green
  shape_string_interpolation: { fg: "#94e2d5" attr: b } # teal
  shape_table: { fg: "#89b4fa" attr: b }            # blue
  shape_variable: { fg: "#cba6f7" attr: b }         # mauve
  shape_vardecl: { fg: "#cba6f7" attr: b }          # mauve
}

$env.config.color_config = $catppuccin_mocha
