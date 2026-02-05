# Solarized dark color configuration for nushell table rendering
# Reference: https://ethanschoonover.com/solarized/

let solarized_dark = {
  separator: dark_gray
  leading_trailing_space_bg: { attr: n }
  header: { fg: "#b58900" attr: b }         # yellow, bold
  empty: "#586e75"                           # base01
  bool: "#2aa198"                            # cyan
  int: "#268bd2"                             # blue
  float: "#268bd2"                           # blue
  filesize: "#2aa198"                        # cyan
  duration: "#2aa198"                        # cyan
  date: "#6c71c4"                            # violet
  range: "#268bd2"                           # blue
  string: "#839496"                          # base0 (default fg)
  nothing: "#586e75"                         # base01
  binary: "#6c71c4"                          # violet
  cell_path: "#839496"                       # base0
  row_index: { fg: "#859900" attr: b }       # green, bold
  record: "#839496"                          # base0
  list: "#839496"                            # base0
  block: "#839496"                           # base0
  hints: "#586e75"                           # base01
  search_result: { fg: "#002b36" bg: "#b58900" } # base03 on yellow

  shape_and: { fg: "#6c71c4" attr: b }
  shape_binary: { fg: "#6c71c4" attr: b }
  shape_block: { fg: "#268bd2" attr: b }
  shape_bool: "#2aa198"
  shape_closure: { fg: "#859900" attr: b }
  shape_custom: "#859900"
  shape_datetime: { fg: "#2aa198" attr: b }
  shape_directory: "#2aa198"
  shape_external: "#2aa198"
  shape_externalarg: { fg: "#859900" attr: b }
  shape_external_resolved: { fg: "#2aa198" attr: b }
  shape_filepath: "#2aa198"
  shape_flag: { fg: "#268bd2" attr: b }
  shape_float: { fg: "#6c71c4" attr: b }
  shape_garbage: { fg: "#fdf6e3" bg: "#dc322f" attr: b }
  shape_glob_interpolation: { fg: "#2aa198" attr: b }
  shape_globpattern: { fg: "#2aa198" attr: b }
  shape_int: { fg: "#6c71c4" attr: b }
  shape_internalcall: { fg: "#2aa198" attr: b }
  shape_keyword: { fg: "#6c71c4" attr: b }
  shape_list: { fg: "#2aa198" attr: b }
  shape_literal: "#268bd2"
  shape_match_pattern: "#859900"
  shape_matching_brackets: { attr: u }
  shape_nothing: "#2aa198"
  shape_operator: "#b58900"
  shape_or: { fg: "#6c71c4" attr: b }
  shape_pipe: { fg: "#6c71c4" attr: b }
  shape_range: { fg: "#b58900" attr: b }
  shape_raw_string: { fg: "#fdf6e3" attr: b }
  shape_record: { fg: "#2aa198" attr: b }
  shape_redirection: { fg: "#6c71c4" attr: b }
  shape_signature: { fg: "#859900" attr: b }
  shape_string: "#859900"
  shape_string_interpolation: { fg: "#2aa198" attr: b }
  shape_table: { fg: "#268bd2" attr: b }
  shape_variable: { fg: "#6c71c4" attr: b }
  shape_vardecl: { fg: "#6c71c4" attr: b }
}

$env.config.color_config = $solarized_dark
