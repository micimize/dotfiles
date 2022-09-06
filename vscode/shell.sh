#!/bin/sh
# https://medium.com/@joaomoreno/persistent-terminal-sessions-in-vs-code-8fc469ed6b41

_dir=$(basename $PWD)
_hash=$(pwd | md5)
_hash=${_hash:0:3}

export VSCODE_SESSION="vscode_${_dir}_${_hash}"

sessions=`tmux ls -F '#{session_attached} #{session_name}' | grep "$VSCODE_SESSION*" | sort`

if [ -z "$sessions" ]
then
  exec tmux new-session -s "${VSCODE_SESSION}_0" \
    -e VSCODE_SESSION=$VSCODE_SESSION
  exit
fi

_first=$(echo "$sessions" | head -1)
IFS=" " read -r is_attached session_name <<< "${_first}"

if [ "$is_attached" -eq "0" ]
then
  exec tmux attach-session -t $session_name
  exit
fi

_last_session=$(echo "$sessions" | tail -1)
last_session_num=$(echo $_last_session | rev | cut -d"_" -f1  | rev)

let "this_session_num=last_session_num+1"

function pack_sessions {
  num=0
  sessions=`tmux ls -F '#{session_name}' | grep "$VSCODE_SESSION*" | sort`
  while read session; do
    tmux rename-session -t $session "${VSCODE_SESSION}_$num" 
    let "num=num+1"
  done <<<"$sessions"
}

exec tmux new-session -s "${VSCODE_SESSION}_$this_session_num" -e VSCODE_SESSION="$VSCODE_SESSION"

# TODO: separate command to clean up session names
# TODO use -L
# https://superuser.com/questions/592063/how-to-execute-a-cleanup-command-on-tmux-server-session-exit
