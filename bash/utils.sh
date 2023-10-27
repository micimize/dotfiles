# Delete line from known_hosts (via rpetre from reddit)
ssh-del() {
  sed -i -e ${1}d ~/.ssh/known_hosts
}

# show the current IP address if connected to the internet.
showip() {
  lynx -dump -hiddenlinks=ignore -nolist http://checkip.dyndns.org:8245/ \
    | awk '{ print $4 }' \
    | sed '/^$/d; s/^[ ]*//g; s/[ ]*$//g'
}

# extract files eg: ex tarball.tar#
function extract() {
  if [ -f $1 ]; then
    case $1 in
      *.tar.bz2) tar xjf $1 ;;
      *.tar.gz) tar xzf $1 ;;
      *.bz2) bunzip2 $1 ;;
      *.rar) rar x $1 ;;
      *.gz) gunzip $1 ;;
      *.tar) tar xf $1 ;;
      *.tbz2) tar xjf $1 ;;
      *.tgz) tar xzf $1 ;;
      *.zip) unzip $1 ;;
      *.Z) uncompress $1 ;;
      *.7z) 7z x $1 ;;
      *) echo "'$1' cannot be extracted via extract()" ;;
    esac
  else
    echo "'$1' is not a valid file"
  fi
}

alias current_tmux_session="tmux display-message -p '#S'"

function vscode_session_number {
  session="$1"
  name="${session##*/}"
  number="${session#%%_*}"
  echo "$number"
}

function vscode_session_label {
  session="$1"
  name="${session##*/}"
  task="${session#*_}"
  echo "$task"
}

function vscode_pack_sessions {
  num=0
  sessions=`tmux ls -F '#{session_name}' | grep "$VSCODE_SESSION*" | sort`
  while read session; do
    name="${session##*/}"
    task="${session#*_}"
    tmux rename-session -t "$session" "${VSCODE_SESSION}/${num}_task" 
    let "num=num+1"
  done <<<"$sessions"
}

function nametab {
  if [ -n "$TMUX" ] && [[ `tmux display-message -p '#S'` == vscode* ]]; then
    num=$(vscode_session_number $(current_tmux_session))
    tabname="${VSCODE_SESSION}/${num}_${1}"
  else
    tabname=$1
  fi
  tmux set-option set-titles-string $tabname
}
alias nt=nametab

function git-track-all {
  git branch -r | grep -v '\->' \
    | sed "s,\x1B\[[0-9;]*[a-zA-Z],,g" \
    | while read remote; do git branch --track "${remote#origin/}" "$remote"; done
  echo 'Now tracking all remote branches.'
  echo 'To update, run `git fetch --all && git pull --all`'
}

function wget-all {
  --recursive \
    --no-clobber \
    --page-requisites \
    --html-extension \
    --convert-links \
    --restrict-file-names=windows \
    --domains $1 \
    --no-parent
}

function docker-clean {
  docker rm -v $(docker ps -a -q -f status=exited)

  docker rmi $(docker images -f "dangling=true" -q)

  docker run -v /var/run/docker.sock:/var/run/docker.sock -v /var/lib/docker:/var/lib/docker --rm martin/docker-cleanup-volumes
}


alias searchjobs="ps -ef | grep -v grep | grep"
alias numbersum="paste -s -d+ - | bc"
