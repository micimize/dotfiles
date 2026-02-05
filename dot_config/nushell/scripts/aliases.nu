# Safety aliases (nushell's rm already uses trash by default,
# but these cover the external command variants)
alias crm = ^rm -i     # "careful rm" -- interactive external rm
alias cmv = ^mv -i     # "careful mv"
alias ccp = ^cp -i     # "careful cp"

# ls variants (nushell's built-in ls returns structured data;
# these aliases are for the external ls when you want classic output)
alias lse = ^ls --color=always -hF
alias lle = ^ls --color=always -hlF
alias lsd = ^ls --color=always -hdlF */

# Nushell-native ls is already excellent for interactive use:
#   ls | sort-by size | reverse    -- sort by size descending
#   ls | where type == dir         -- directories only
#   ls **/*.rs                     -- recursive glob

# Editor
alias vim = ^nvim

# Quick exit (vi habit)
alias ':q' = exit

# Disk usage
alias duf = ^df -h
alias duh = ^du -h -c
