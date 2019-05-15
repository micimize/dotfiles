#zmodload zsh/zprof

autoload -Uz compinit
if [ $(date +'%j') != $(stat -f '%Sm' -t '%j' ~/.zcompdump) ]; then
  compinit
else
  compinit -C
fi

# 
# Paths
#
export GOPATH=$HOME/golang
export GOROOT=/usr/local/opt/go/libexec

export PATH=$PATH:$HOME/bin:$HOME/node_modules/.bin:/usr/local/sbin:$GOPATH/bin:$GOROOT/bin:$HOME/flutter/bin:$HOME/Library/Android/sdk/platform-tools/

export ANDROID_SDK=$HOME/Library/Android/sdk
export PATH=$ANDROID_SDK/emulator:$ANDROID_SDK/tools:$PATH

if [ -d /opt/local/bin ]; then
  PATH="/opt/local/bin:$PATH"
fi

if [ -d /usr/lib/cw ] ; then
  PATH="/usr/lib/cw:$PATH"
fi

export ZSH_DISABLE_COMPFIX=true # 
# Path to your oh-my-zsh installation.
export ZSH="/Users/mjr/.oh-my-zsh"

# tmux
DISABLE_AUTO_TITLE=true

#
# omz history settings
#
HIST_STAMPS="%Y-%m-%dT%H:%M"
export HISTORY_IGNORE="(ls|l|s|exit|clear|pwd|vim|note|notes|Lq)"
export HISTCONTROL=ignoredups

#
# Plugins (using antigen)
# 
# brew installed anitgen
source /usr/local/share/antigen/antigen.zsh

antigen use oh-my-zsh
antigen bundle git
antigen bundle virtualenv
antigen bundle gpg-agent
antigen bundle dotenv

antigen bundle zsh-users/zsh-autosuggestions
antigen bundle iam4x/zsh-iterm-touchbar

antigen apply

# makes zsh-iterm-touchbar work
YARN_ENABLED=true

unsetopt correct_all  
setopt correct

#
# Theme
# 
ZSH_THEME="powerlevel9k/powerlevel9k"
POWERLEVEL9K_DISABLE_RPROMPT=true
POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=( virtualenv time dir background_jobs_joined vcs vi_mode)

POWERLEVEL9K_TIME_FORMAT="%D{%m-%d %H:%M}"
POWERLEVEL9K_TIME_FOREGROUND='cyan'
POWERLEVEL9K_TIME_BACKGROUND='black'

POWERLEVEL9K_SHORTEN_DIR_LENGTH=3
POWERLEVEL9K_SHORTEN_STRATEGY="truncate_from_right"
POWERLEVEL9K_DIR_HOME_BACKGROUND='black'
POWERLEVEL9K_DIR_HOME_SUBFOLDER_BACKGROUND='black'
POWERLEVEL9K_DIR_DEFAULT_BACKGROUND='black'
POWERLEVEL9K_DIR_HOME_FOREGROUND='magenta'
POWERLEVEL9K_DIR_HOME_SUBFOLDER_FOREGROUND='magenta'
POWERLEVEL9K_DIR_DEFAULT_FOREGROUND='magenta'

POWERLEVEL9K_VI_INSERT_MODE_STRING="I"
POWERLEVEL9K_VI_COMMAND_MODE_STRING="N"
POWERLEVEL9K_VI_MODE_INSERT_BACKGROUND='blue'
POWERLEVEL9K_VI_MODE_NORMAL_BACKGROUND='yellow'


CASE_SENSITIVE="true" # Foo != foo
# HYPHEN_INSENSITIVE="true" # makes _ and - will be interchangeable. Requires CASE_SENSITIVE="false"
ENABLE_CORRECTION="true" # Correct typos, etc
# DISABLE_UNTRACKED_FILES_DIRTY="true" # don't mark untracked files dirty. Makes `git status` faster

source $ZSH/oh-my-zsh.sh

setopt no_hist_verify
# should maybe truncate history by a year every year after 5 years have built up,
# moving the old history to the archive
HISTSIZE=999999999
SAVEHIST=$HISTSIZE

set -o vi

bindkey "^?" backward-delete-char
bindkey -v
bindkey '^R' history-incremental-search-backward

alias ":q"="exit"
alias s="ls | GREP_COLOR='1;34' grep --color '.*@'"
alias l="ls"

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(lesspipe)"

export PAGER=less
export EDITOR=vim
export LESS='-R'

## set options
#set -o noclobber        # prevent overwriting files with cat
#set -o ignoreeof        # stops ctrl+d from logging me out

# Set appropriate ls alias
# adds / for dirs, @ for symlinks
case $(uname -s) in
  Darwin|FreeBSD)
    alias ls="ls -hFG"
    ;;
  Linux)
    alias ls="ls --color=always -hF"
    ;;
  NetBSD|OpenBSD)
    alias ls="ls -hF"
    ;;
esac

alias rm="rm -i"
alias mv="mv -i"
alias cp="cp -i"
alias ll="ls -hl"
alias cd..="cd .."
alias mkdir='mkdir -p -v'
alias df='df -h'
alias du='du -h -c'
alias lsd="ls -hdlf */"
alias myip="ifconfig en0 | grep inet | grep -v inet6 | awk '{print \$2}'"

export GREP_OPTIONS=--color=auto

##############################################################################
# Functions
##############################################################################
# Delete line from known_hosts
# courtesy of rpetre from reddit
ssh-del() {
  sed -i -e ${1}d ~/.ssh/known_hosts
}

psgrep() {
  if [ ! -z $1 ] ; then
    echo "Grepping for processes matching $1..."
    ps aux | grep $1 | grep -v grep
  else

    echo "!! Need name to grep for"
  fi
}

# showip - show the current IP address if connected to the internet.
# Usage: showip.
#
showip () {
  lynx -dump -hiddenlinks=ignore -nolist http://checkip.dyndns.org:8245/ | awk '{ print $4 }' | sed '/^$/d; s/^[ ]*//g; s/[ ]*$//g' 
}

##################
#extract files eg: ex tarball.tar#
##################
ex () {
  if [ -f $1 ] ; then
    case $1 in
      *.tar.bz2)   tar xjf $1        ;;
      *.tar.gz)    tar xzf $1     ;;
      *.bz2)       bunzip2 $1       ;;
      *.rar)       rar x $1     ;;
      *.gz)        gunzip $1     ;;
      *.tar)       tar xf $1        ;;
      *.tbz2)      tar xjf $1      ;;
      *.tgz)       tar xzf $1       ;;
      *.zip)       unzip $1     ;;
      *.Z)         uncompress $1  ;;
      *.7z)        7z x $1    ;;
      *)           echo "'$1' cannot be extracted via extract()" ;;
    esac
  else
    echo "'$1' is not a valid file"
  fi
}


function note {
    dir=`pwd`
    cd ~/Documents/notes
    vim -p "$@" 
    cd $dir
}
alias notes='vim ~/Documents/notes'



#
# Utility functions
#

# apply the first function to every subsequent argument
function map { 
  if [ $# -le 1 ]; then 
    return 
  else 
    local f=$1 
    local x=$2 
    shift 2 
    local xs=$@ 
    $f $x 
    map "$f" $xs 
  fi 
}

# take a screenshot ever 5 min
function monitor {
  while true;
  do vardate=$(date +%Y\-%m\-%d\_%H:%M:%S);
    echo $vardate;
    screencapture -t jpg -x ~/Documents/data/monitor/${vardate}.jpg;
    sleep 500;
  done;
}

# clean old docker images
function docker-clean {
  docker rm -v $(docker ps -a -q -f status=exited)

  docker rmi $(docker images -f "dangling=true" -q)

  docker run -v /var/run/docker.sock:/var/run/docker.sock -v /var/lib/docker:/var/lib/docker --rm martin/docker-cleanup-volumes
}

# rename the origin remote to $1
function git-remote-rename {
  new_name=$1
  base=$(git remote -v | head -n 1 | awk '{print $2}' | awk -F '/' '{print $1}')
  git remote remove origin
  git remote add origin ${base}/${1}.git
}

# list locally linked node modules (unsure if this works with yarn link)
function npm-ls-linked-deps {
  ls -l node_modules | \
    grep ^l | \
    awk '{print $9}' | \
    sed 's/@//g';
}

# see if the current module is linked to locally (unsure if this works with yarn link)
function npm-symlinked {
  npm $@ --color=always 2>&1 | grep -vE 'Module is inside a symlinked module'
}

pip-diff () {
  grep -v -f \
    <(cat requirements.txt .dependencies.txt | sed '/^$/d') \
    <(pip freeze -r requirements.txt) | sed '/^$/d'
}

function git-clean () {
  git branch --merged >/tmp/merged-branches && \
    vi /tmp/merged-branches && \
    xargs git branch -d </tmp/merged-branches
}

function feature-in () {
  branch=$1
  t in $branch
  git branch $branch
  git checkout $branch
}

function feature-out () {
  branch=$(git rev-parse --abbrev-ref HEAD)
  echo "Checking out of $branch"
  git push origin $branch
  git checkout master
  t out
  t d | grep "$branch"
}

#[ -f ~/.fzf.bash ] && source ~/.fzf.bash


test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"

alias twindow='tmux display-message -p "#W"'
alias ping-me="osascript -e 'display notification \"\" with title \"ping from $(twindow)\"'"


function reset_touchbar {
  pkill "Touch Bar agent";
  killall "ControlStrip";
}

function flutter_wash {
  flutter clean
  flutter packages get
  flutter packages pub get
}


# The next line updates PATH for the Google Cloud SDK.
if [ -f '/Users/mjr/google-cloud-sdk/path.zsh.inc' ]; then . '/Users/mjr/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/Users/mjr/google-cloud-sdk/completion.zsh.inc' ]; then . '/Users/mjr/google-cloud-sdk/completion.zsh.inc'; fi

#zprof
