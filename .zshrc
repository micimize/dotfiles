# zmodload zsh/zprof

bindkey '^R' history-incremental-pattern-search-backward


source ~/.env

export NO_PROXY=localhost,127.0.0.1

# only compinit once a day
autoload -Uz compinit
if [ $(date +'%j') != $(stat -f '%Sm' -t '%j' ~/.zcompdump) ]; then
  compinit
else
  compinit -C
fi

# 
# Paths
#
source $HOME/.poetry/env

export GOPATH=$HOME/golang
export GOROOT=/usr/local/opt/go/libexec
export PATH=$PATH:$HOME/bin:$HOME/node_modules/.bin:/usr/local/sbin:$GOPATH/bin:$GOROOT/bin:$HOME/Library/Android/sdk/platform-tools/:$HOME/.cargo/bin

export PATH="$PATH":"$HOME/flutter/.pub-cache/bin"
export PATH="$PATH":"$HOME/flutter/bin"

export ANDROID_SDK=$HOME/Library/Android/sdk
export PATH=$ANDROID_SDK/emulator:$ANDROID_SDK/tools:$PATH

export PATH="$PATH":"$HOME/.pub-cache/bin"

# ruby
export PATH="/Users/mjr/.gem/ruby/2.6.0/bin:/usr/local/opt/ruby/bin:$PATH"

export LDFLAGS="-L/usr/local/opt/ruby/lib"
export CPPFLAGS="-I/usr/local/opt/ruby/include"
export PKG_CONFIG_PATH="/usr/local/opt/ruby/lib/pkgconfig"



if [ -d /opt/local/bin ]; then
  PATH="/opt/local/bin:$PATH"
fi

if [ -d /usr/lib/cw ] ; then
  PATH="/usr/lib/cw:$PATH"
fi

export ZSH_DISABLE_COMPFIX=true # 
# Path to your oh-my-zsh installation.
export ZSH="/Users/mjr/.oh-my-zsh"


# massive slowdown
#export NVM_DIR="$HOME/.nvm"
#[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm

# tmux
DISABLE_AUTO_TITLE=true

#
# omz history settings
#
HIST_STAMPS="%Y-%m-%dT%H:%M"
export HISTORY_IGNORE="(ls|l|s|exit|clear|pwd|vim|note|notes|Lq)"
export HISTCONTROL=ignoredups

. /usr/local/etc/profile.d/z.sh

# makes zsh-iterm-touchbar work
YARN_ENABLED=true

unsetopt correct_all  
setopt correct

#
# Theme
# 
#
ZSH_THEME="powerlevel10k/powerlevel10k"
POWERLEVEL9K_MODE="awesome-patched"

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
POWERLEVEL9K_VI_MODE_INSERT_FOREGROUND='white'
POWERLEVEL9K_VI_MODE_NORMAL_BACKGROUND='yellow'

POWERLEVEL9K_LEGACY_ICON_SPACING=true


# I use this for writing to give myself nice padded layout
function margin_pane {
  export POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(vi_mode)
  export POWERLEVEL9K_VI_MODE_INSERT_BACKGROUND='black'
  export POWERLEVEL9K_VI_MODE_NORMAL_BACKGROUND='black'

  pane_borders='bg=brightblack,fg=brightblack'

  tmux set-option pane-border-style $pane_borders
  tmux set-option pane-active-border-style $pane_borders
  tmux select-pane -P 'bg=black'
  clear
}


CASE_SENSITIVE="true" # Foo != foo
# HYPHEN_INSENSITIVE="true" # makes _ and - will be interchangeable. Requires CASE_SENSITIVE="false"
# ENABLE_CORRECTION="true" # Correct typos, etc
# DISABLE_UNTRACKED_FILES_DIRTY="true" # don't mark untracked files dirty. Makes `git status` faster
#
#
# Plugins (using antibody)
# 
# brew install getantibody/tap/antibody

# antibody bundle < ~/.zsh_plugins.txt > ~/code/personal/dotfiles/zsh/plugins.sh
source ~/code/personal/dotfiles/zsh/plugins.sh



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

alias date=gdate
alias isodate="gdate -Ins"

alias chrome="/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome"

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

function cheap_clone {
  EXTERNAL_CLONE_DIR="~/code/external"
  # mkdir -p $EXTERNAL_CLONE_DIR

  GIT_HOST='github.com'
  BRANCH='master'
  while [[ $# -gt 0 ]]
  do
      key="$1"
      case $key in
          -h|--host)
              GIT_HOST=$2
              shift # past argument
              shift # past value
              ;;
          -b|--branch)
              BRANCH=$2
              shift # past argument
              shift # past value
              ;;
          *)
              REPO=$key
              shift # past argument
              ;;
      esac
  done

  if [ -z "$REPO" ]
  then
      echo $REPO
      echo "ERROR: positional argument repo must be supplied"
      return
  fi
  
  cd $EXTERNAL_CLONE_DIR

  git clone --depth 1 \
    --single-branch --branch $BRANCH \
    git@${GIT_HOST}:${REPO}.git ${REPO}

  cd $REPO 
}


function reset_touchbar {
  pkill "Touch Bar agent";
  killall "ControlStrip";
}

function flutter_wash {
  flutter clean
  flutter packages get
  flutter packages pub get
}

function git_diff {
  while [[ $# -gt 0 ]]
  do
      key="$1"
      case $key in
          --exclude)
              exclude=$2
              shift # past argument
              shift # past value
              ;;
          *)
            break
              ;;
      esac
  done
  exclude=$1
  git diff $@ --name-only | grep -v "$exclude" \
      | xargs git diff $@ --
}

alias csvdiff='git diff --color-words="[^[:space:],]+" --no-index'
alias git_csvdiff='git diff --color-words="[^[:space:],]+"'


# The next line updates PATH for the Google Cloud SDK.
if [ -f '/Users/mjr/google-cloud-sdk/path.zsh.inc' ]; then . '/Users/mjr/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/Users/mjr/google-cloud-sdk/completion.zsh.inc' ]; then . '/Users/mjr/google-cloud-sdk/completion.zsh.inc'; fi

# poetry() {
#     if [[ -f pyproject.toml ]]; then
#         PYVER=$(grep -E '^python =' pyproject.toml | sed -E 's/^python = "\^([0-9].[0-9])"/\1/')
#         python${PYVER} $(whence -p poetry) "$@"
#     else
#         if [[ -v PYTHON ]]; then
#             python${PYTHON} $(whence -p poetry) "$@"
#         else
#             $(whence -p poetry) "$@"
#         fi
#     fi
# }


function notify_me {
  osascript -e 'display notification "NOTIFICATION" with title "NOTIFICATION"'
}


source /Users/mjr/Library/Preferences/org.dystroy.broot/launcher/bash/br

# zprof
