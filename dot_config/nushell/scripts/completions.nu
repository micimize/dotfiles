# External completer setup
# Multiple completer pattern: routes z/zi to zoxide, everything else to carapace
# Reference: https://www.nushell.sh/cookbook/external_completers.html

# Carapace completer (1000+ commands out of the box)
let carapace_completer = if (which carapace | is-not-empty) {
  {|spans: list<string>|
    try {
      carapace $spans.0 nushell ...$spans | from json
    } catch {
      null  # Fall back to file completion on carapace errors
    }
  }
} else {
  {|spans: list<string>| null }
}

# Zoxide completer (frecency-ranked directory candidates)
let zoxide_completer = if (which zoxide | is-not-empty) {
  {|spans: list<string>|
    $spans | skip 1 | zoxide query -l ...$in | lines | where { |line| $line != "" }
  }
} else {
  {|spans: list<string>| null }
}

# Route commands to the appropriate completer
let external_completer = {|spans: list<string>|
  match $spans.0 {
    z | zi => (do $zoxide_completer $spans)
    _ => (do $carapace_completer $spans)
  }
}

$env.config.completions.external = {
  enable: true
  max_results: 100
  completer: $external_completer
}
