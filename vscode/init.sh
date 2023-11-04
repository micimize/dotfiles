# current_tmux_session defined in bash/utils.sh

function vscode_session_prefix {
  session="${1:-`current_tmux_session`}"
  prefix="${session%%/*}"
  echo "$prefix"
}

function vscode_session_number {
  session="${1:-`current_tmux_session`}"
  name="${session##*/}"
  number="${name%%_*}"
  echo "$number"
}

function vscode_session_label {
  session="${1:-`current_tmux_session`}"
  name="${session##*/}"
  task="${name#*_}"
  echo "$task"
}

function vscode_pack_sessions {
  session_prefix="${1:-`vscode_session_prefix`}"
  num=0
  for session in `tmux ls -F '#{session_name}' | grep "$session_prefix*" | sort`; do
    new_session_name="${session_prefix}/${num}_$(vscode_session_label $session)"
    tmux rename-session -t "$session" "$new_session_name"
    let "num=num+1"
  done
}

function nametab {
  prefix=`vscode_session_prefix`
  tabname="$1"
  if [[ "$2" != "" ]]; then
    num=$1
    args="-t ${prefix}/${num}_"
    tabname="$2"
  else
    args=""
    num=$(vscode_session_number)
    tabname="$1"
  fi
  if [[ "$prefix" == vscode* ]]; then
    tmux rename-session $args "${prefix}/${num}_${tabname}"
  else
    tmux set-option set-titles-string "$tabname"
  fi
}

alias nt=nametab

if [ -n "$TMUX" ] && [[ `tmux display-message -p '#S'` == vscode* ]]; then
  vscode_pack_sessions
  shopt -s nullglob
  for activation_file in .vscode/*activate.sh; do
    source $activation_file
  done
  shopt -u nullglob
  # medium_prompt
fi
