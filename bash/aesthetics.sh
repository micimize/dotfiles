function __color_escape_code_reference {
  text_black='\e[0;30m'
  text_red='\e[0;31m'
  text_green='\e[0;32m'
  text_yellow='\e[0;33m'
  text_blue='\e[0;34m'
  text_purle='\e[0;35m'
  text_cyan='\e[0;36m'
  text_white='\e[0;37m'
  bold_black='\e[1;30m'
  bold_red='\e[1;31m'
  bold_green='\e[1;32m'
  bold_yellow='\e[1;33m'
  bold_blue='\e[1;34m'
  bold_purle='\e[1;35m'
  bold_cyan='\e[1;36m'
  bold_white='\e[1;37m'
  underlined_black='\e[4;30m'
  underlined_red='\e[4;31m'
  underlined_green='\e[4;32m'
  underlined_yellow='\e[4;33m'
  underlined_blue='\e[4;34m'
  underlined_purle='\e[4;35m'
  underlined_cyan='\e[4;36m'
  underlined_white='\e[4;37m'
  background_black='\e[40m'
  background_red='\e[41m'
  background_green='\e[42m'
  background_yellow='\e[43m'
  background_blue='\e[44m'
  background_purle='\e[45m'
  background_cyan='\e[46m'
  background_white='\e[47m'
  text_reset='\e[0m'
}

# https://github.com/tinted-theming/base16-fzf/blob/main/bash/base16-solarized-dark.config
_gen_fzf_default_opts() {
  local color00='#002b36'
  local color01='#073642'
  local color02='#586e75'
  local color03='#657b83'
  local color04='#839496'
  local color05='#93a1a1'
  local color06='#eee8d5'
  local color07='#fdf6e3'
  local color08='#dc322f'
  local color09='#cb4b16'
  local color0A='#b58900'
  local color0B='#859900'
  local color0C='#2aa198'
  local color0D='#268bd2'
  local color0E='#6c71c4'
  local color0F='#d33682'

  export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS\
   --color=bg+:$color01,bg:$color00,spinner:$color0C,hl:$color0D\
   --color=fg:$color04,header:$color0D,info:$color0A,pointer:$color0C\
   --color=marker:$color0C,fg+:$color06,prompt:$color0A,hl+:$color0D"
}

_gen_fzf_default_opts


# https://gist.github.com/thomd/7667642
# TODO: Consider https://github.com/sharkdp/vivid
export LSCOLORS="fxgxcxdxbxegedabagacad"

if [ "$TERM" = "screen" ] && [ "$HAS_256_COLORS" = "yes" ]; then
  export TERM=screen-256color
fi

export GREP_OPTIONS=--color=auto
export LESS_TERMCAP_mb=$'\E[01;31m'
export LESS_TERMCAP_md=$'\E[01;31m'
export LESS_TERMCAP_me=$'\E[0m'
export LESS_TERMCAP_se=$'\E[0m'
export LESS_TERMCAP_so=$'\E[01;44;33m'
export LESS_TERMCAP_ue=$'\E[0m'
export LESS_TERMCAP_us=$'\E[01;32m'
export CLICOLOR=1

# look at all the colors
function colors_256 {
  for i in {0..255}; do
    printf "\x1b[48;5;%sm%3d\e[0m " "$i" "$i"
    if ((i == 15)) || ((i > 15)) && (((i - 15) % 6 == 0)); then
      printf "\n"
    fi
  done
}