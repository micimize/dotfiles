# export HISTCONTROL=ignoredups
export HISTSIZE=1000000
export HISTFILESIZE=1000000
export HISTIGNORE="&:ls:ll:la:l.:pwd:exit:clear"

# automatic virtualenv sourcing
export _LAST_SEEN_PWD=""
function _current_venv_info {
  if [[ "$VIRTUAL_ENV" != "" ]]; then
    venv=$(realpath --relative-to $PWD $VIRTUAL_ENV)
    version=$(cat $VIRTUAL_ENV/pyvenv.cfg | grep version | sed 's/version = \(.*\)\..*$/\1/g' | tail -n1)
    echo "($venv v$version)"
  fi
}
function _on_auto_venv {
  echo
}
function auto_activate_venv {
  if [[ "$PWD" != "$_LAST_SEEN_PWD" ]]; then
    export _LAST_SEEN_PWD="$PWD"
    # TODO: nested venvs
    if [[ "$VIRTUAL_ENV" != "" && "$PWD" != "$(dirname $VIRTUAL_ENV)"* ]]; then
      deactivate || true
    fi
    if [[ "$VIRTUAL_ENV" == "" ]]; then 
      [ -d ".venv" ] && source ".venv/bin/activate"
    fi
  fi
  _on_auto_venv
}


_short_path_for_prompt() {
  if [[ $PWD == $HOME ]]; then
    echo "~"
  else
    dir=$(dirname $(echo "$PWD" | sed "s|$HOME|~|g" | sed 's|/\(...\)[^/]*|/\1|g'))
    echo "$dir/${PWD##*/}"
  fi
}
function _fallback_prompt {
  _export_color_escape_codes
  export PS1="\[$_text_cyan\]\D{%m-%d} \A \[$_bold_cyan\]\$(_short_path_for_prompt) $ \[$_text_reset\]"
}
_fallback_prompt


# I use this for writing to give myself nice padded layout
function margin_pane {
  bright='brightblack'
  dark='black'
  # vscode bright and normal black are reversed
  if [[ "$VSCODE_SESSION" != "" ]]; then
    dark='brightblack'
    bright='black'
  fi

  # export POWERLEVEL9K_VI_MODE_INSERT_BACKGROUND="$dark"
  # export POWERLEVEL9K_VI_MODE_INSERT_FOREGROUND='blue'
  # export POWERLEVEL9K_VI_MODE_NORMAL_BACKGROUND="$dark"
  # export POWERLEVEL9K_VI_MODE_NORMAL_FOREGROUND='yellow'
  short_prompt

  pane_borders="bg=$bright,fg=$bright"
  tmux set-option pane-border-style $pane_borders
  tmux set-option pane-active-border-style $pane_borders
  tmux select-pane -P "bg=$dark"

  clear
}

function unmargin_pane {
  bright='brightblack'
  brblack='brblack'
  # vscode bright and normal black are reversed
  #if [[ "$VSCODE_SESSION" != "" ]] {
  #  bright='black'
  #  brblack='black'
  #}

  # export POWERLEVEL9K_VI_MODE_INSERT_BACKGROUND='blue'
  # export POWERLEVEL9K_VI_MODE_INSERT_FOREGROUND='white'
  # export POWERLEVEL9K_VI_MODE_NORMAL_BACKGROUND='yellow'
  # export POWERLEVEL9K_VI_MODE_NORMAL_FOREGROUND="$brblack"
  long_prompt

  tmux set-option pane-border-style ''
  tmux set-option pane-active-border-style 'fg=green'
  tmux select-pane -P "bg=$bright"
}

#log all history always
_prompt_func() {
  # right before prompting for the next command, save the previous command in a file.
  echo "$(date +%Y-%m-%d--%H-%M-%S) $(hostname) $PWD $(history 1)" >>~/.full_history
  auto_activate_venv
}
PROMPT_COMMAND=_prompt_func

# eval "$(starship init bash)"
source "$BLESH_DIR/ble.sh"