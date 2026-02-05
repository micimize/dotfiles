# External completer setup
# Uses carapace if installed, otherwise gracefully degrades to no external completions

let external_completer = if (which carapace | is-not-empty) {
  # Carapace provides completions for 1000+ commands out of the box
  let carapace_completer = {|spans: list<string>|
    carapace $spans.0 nushell ...$spans | from json
  }
  {|spans: list<string>|
    # Resolve aliases before passing to carapace
    let expanded_alias = (scope aliases | where name == $spans.0 | get -o 0.expansion)
    let spans = if $expanded_alias != null {
      $spans | skip 1 | prepend ($expanded_alias | split row " " | take 1)
    } else {
      $spans
    }
    do $carapace_completer $spans
  }
} else {
  {|spans: list<string>| null }  # No external completions available
}

$env.config.completions.external = {
  enable: true
  completer: $external_completer
}
