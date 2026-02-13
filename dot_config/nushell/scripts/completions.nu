# External completer setup
# Uses carapace if installed, otherwise gracefully degrades to no external completions
# Note: nushell 0.108+ handles alias expansion natively -- no need for manual scope lookup

let external_completer = if (which carapace | is-not-empty) {
  {|spans: list<string>|
    try {
      carapace $spans.0 nushell ...$spans | from json
    } catch {
      null  # Fall back to file completion on carapace errors
    }
  }
} else {
  {|spans: list<string>| null }  # No external completions available
}

$env.config.completions.external = {
  enable: true
  max_results: 100
  completer: $external_completer
}
