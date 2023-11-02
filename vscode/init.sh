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
  sessions=`tmux ls -F '#{session_name}' | grep "$session_prefix*" | sort`
  while read session; do
    name="${session##*/}"
    task="${session#*_}"
    tmux rename-session -t "$session" "${session_prefix}/${num}_${task}"
    let "num=num+1"
  done <<<"$sessions"
}

function nametab {
  tabname=$1
  prefix=`vscode_session_prefix`
  if [[ "$prefix" == vscode* ]]; then
    num=$(vscode_session_number)
    tmux rename-session "${prefix}/${num}_${tabname}"
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
