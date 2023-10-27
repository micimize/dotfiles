#!/bin/bash

# https://medium.com/@joaomoreno/persistent-terminal-sessions-in-vs-code-8fc469ed6b41

# if [[ $- != *i* ]] ; then
  # Shell is non-interactive. No reason to muck about with tmux
#  exec /bin/bash
#fi

if [ -d /usr/local/bin ]; then
  PATH="/usr/local/bin:$PATH"
fi

_dir=$(basename $PWD)
_hash=$(pwd | md5sum)
_hash=${_hash:0:3}

export VSCODE_SESSION="vscode_${_dir}_${_hash}"

sessions=`tmux ls -F '#{session_attached} #{session_name}' | grep "$VSCODE_SESSION*" | sort`

if [ -z "$sessions" ]
then
  exec tmux new-session -s "${VSCODE_SESSION}/0_tmux" -e VSCODE_SESSION="$VSCODE_SESSION"
  exit
fi

_first=$(echo "$sessions" | head -1)
IFS=" " read -r is_attached session_name <<< "${_first}"

if [ "$is_attached" -eq "0" ]
then
  exec tmux attach-session -d -t "$session_name"
  exit
fi

_last_session=$(echo "$sessions" | tail -1)
last_session_num=$(echo "$_last_session" | rev | cut -d"/" -f1 | cut -d"_" -f2  | rev)

let "this_session_num=last_session_num+1"

function pack_sessions {
  num=0
  sessions=`tmux ls -F '#{session_name}' | grep "$VSCODE_SESSION*" | sort`
  while read session; do
    name="${session##*/}"
    task="${session#*_}"
    tmux rename-session -t "$session" "${VSCODE_SESSION}/${num}_task"
    let "num=num+1"
  done <<<"$sessions"
}
pack_sessions

exec tmux new-session -s "${VSCODE_SESSION}/${this_session_num}_tmux" -e VSCODE_SESSION="$VSCODE_SESSION"

# TODO: separate command to clean up session names
# TODO use -L
# https://superuser.com/questions/592063/how-to-execute-a-cleanup-command-on-tmux-server-session-exit
