if [[ $- != *i* ]] ; then
  # Shell is non-interactive.  Be done now!
  return
fi

# if command -v tmux &> /dev/null && [[ ! "$TERM" =~ screen ]] && [[ ! "$TERM" =~ tmux ]] && [ -z "$TMUX" ]; then
#  exec tmux
# fi

#USER config
export USER_SHORTPATH=true

export FIREFOX_PROFILE_DIR="$HOME/snap/firefox/common/.mozilla/firefox/bsx5dc2h.default"
export DOTFILES_DIR="$HOME/code/personal/dotfiles"

function firefox_hack_recovery {
  # for parsing jsonlv4: https://gist.github.com/Tblue/62ff47bef7f894e92ed5
  backup_dir="$FIREFOX_PROFILE_DIR/sessionstore-backups"
  ls -l "$backup_dir"
  cp -R "$backup_dir/*" ~/ff_backups/
  rm "$backup_dir/recovery.jsonlv4"
}

#enable bash completion
[ -f /etc/profile.d/bash-completion ] && source /etc/profile.d/bash-completion
 
# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(lesspipe)"
 

# ruby
# export PATH="/Users/mjr/.gem/ruby/2.6.0/bin:/usr/local/opt/ruby/bin:$PATH"

# export LDFLAGS="-L/usr/local/opt/ruby/lib"
# export CPPFLAGS="-I/usr/local/opt/ruby/include"
# export PKG_CONFIG_PATH="/usr/local/opt/ruby/lib/pkgconfig"

# Shell variables
export PAGER=less
export EDITOR=vim
# export GOPATH=$HOME/golang
# export GOROOT=/usr/local/opt/go/libexec
# export PATH=$PATH:$HOME/bin:$HOME/node_modules/.bin:/usr/local/sbin:$GOPATH/bin:$GOROOT/bin
export LESS='-R'
export HISTCONTROL=ignoredups
export HISTSIZE=5000
export HISTFILESIZE=5000
export HISTIGNORE="&:ls:ll:la:l.:pwd:exit:clear"
 
if [ -d /opt/local/bin ]; then
  PATH="/opt/local/bin:$PATH"
fi
 
if [ -d /usr/lib/cw ] ; then
  PATH="/usr/lib/cw:$PATH"
fi
 
complete -cf sudo       # Tab complete for sudo
 
## shopt options
shopt -s cdspell        # This will correct minor spelling errors in a cd command.
shopt -s histappend     # Append to history rather than overwrite
shopt -s checkwinsize   # Check window after each command
shopt -s dotglob        # files beginning with . to be returned in the results of path-name expansion.
shopt -s extglob        # use extended globbing
shopt -s direxpand      # prevent dir expansion and $ escaping in tab complete
#shopt -s globstar don't know why this doesn't work
 
## set options
set -o noclobber        # prevent overwriting files with cat
set -o ignoreeof        # stops ctrl+d from logging me out
 
# Set appropriate ls alias
case $(uname -s) in
  Darwin|FreeBSD) alias ls="ls -hFG"      ;;
  Linux) alias ls="ls --color=always -hF" ;;
  NetBSD|OpenBSD) alias ls="ls -hF" ;;
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
 
#PS1='\h:\W \u\$ '
# Make bash check its window size after a process completes
 
##############################################################################
# Color variables
##############################################################################
txtblk='\e[0;30m' # Black - Regular
txtred='\e[0;31m' # Red
txtgrn='\e[0;32m' # Green
txtylw='\e[0;33m' # Yellow
txtblu='\e[0;34m' # Blue
txtpur='\e[0;35m' # Purple
txtcyn='\e[0;36m' # Cyan
txtwht='\e[0;37m' # White
bldblk='\e[1;30m' # Black - Bold
bldred='\e[1;31m' # Red
bldgrn='\e[1;32m' # Green
bldylw='\e[1;33m' # Yellow
bldblu='\e[1;34m' # Blue
bldpur='\e[1;35m' # Purple
bldcyn='\e[1;36m' # Cyan
bldwht='\e[1;37m' # White
unkblk='\e[4;30m' # Black - Underline
undred='\e[4;31m' # Red
undgrn='\e[4;32m' # Green
undylw='\e[4;33m' # Yellow
undblu='\e[4;34m' # Blue
undpur='\e[4;35m' # Purple
undcyn='\e[4;36m' # Cyan
undwht='\e[4;37m' # White
bakblk='\e[40m'   # Black - Background
bakred='\e[41m'   # Red
badgrn='\e[42m'   # Green
bakylw='\e[43m'   # Yellow
bakblu='\e[44m'   # Blue
bakpur='\e[45m'   # Purple
bakcyn='\e[46m'   # Cyan
bakwht='\e[47m'   # White
txtrst='\e[0m'    # Text Reset
##############################################################################
sp='$(eval "short_path")'
short_path() {
   echo "$PWD" | sed "s|$HOME|~|g" | sed 's|/\(...\)[^/]*|/\1|g'
} 
if [ $(id -u) -eq 0 ]; then # you are root, set red colour prompt
    export PS1="[\[$txtred\]\u\[$txtylw\]@\[$txtrst\]\h] \[$txtgrn\]\W\[$txtrst\]# "
else
    if $USER_SHORTPATH; then
        pth=$sp
    else 
        pth=$PWD
    fi
    export PS1="\[$txtcyn\]\D{%m-%d} \A \[$bldcyn\]$pth $ \[$txtrst\]"
    #shopt -s extdebug; trap "tput sgr0" DEBUG
    export SUDO_PS1="[\[$txtred\]\u\[$txtylw\]@\[$txtrst\]\h] \[$txtgrn\]\W\[$txtrst\]# "
    export LSCOLORS="fxgxcxdxbxegedabagacad"
fi
if [ "$TERM" = "screen" ] && [ "$HAS_256_COLORS" = "yes" ]
then
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
 
##############################################################################
# Functions
##############################################################################
# Delete line from known_hosts
# courtesy of rpetre from reddit
ssh-del() {
    sed -i -e ${1}d ~/.ssh/known_hosts
}
 
# showip - show the current IP address if connected to the internet.
# Usage: showip.
#
showip ()
{
  lynx -dump -hiddenlinks=ignore -nolist http://checkip.dyndns.org:8245/ |
    awk '{ print $4 }' |
    sed '/^$/d; s/^[ ]*//g; s/[ ]*$//g' 
}
 
##################
#extract files eg: ex tarball.tar#
##################
ex () {
  if [ -f $1 ] ; then
    case $1 in
      *.tar.bz2)   tar xjf $1     ;;
      *.tar.gz)    tar xzf $1     ;;
      *.bz2)       bunzip2 $1     ;;
      *.rar)       rar x $1       ;;
      *.gz)        gunzip $1      ;;
      *.tar)       tar xf $1      ;;
      *.tbz2)      tar xjf $1     ;;
      *.tgz)       tar xzf $1     ;;
      *.zip)       unzip $1       ;;
      *.Z)         uncompress $1  ;;
      *.7z)        7z x $1        ;;
      *)           echo "'$1' cannot be extracted via extract()" ;;
    esac
  else
    echo "'$1' is not a valid file"
  fi
}


###############################
#     mjr customizations
###############################
alias ":q"="exit"
alias s="ls | GREP_COLOR='1;34' grep --color '.*@'"
alias l="ls"

function up {
    for((i=0;i<$1;i++))
    do
        cd ..
        let inc+=1
    done
}
function note {
    dir=`pwd`
    cd ~/Documents/notes
    vim -p "$@" 
    cd $dir
}
alias notes='vim ~/Documents/notes'

alias searchjobs="ps -ef | grep -v grep | grep"
alias numbersum="paste -s -d+ - | bc"


#log all history always
promptFunc()
{
  # right before prompting for the next command, save the previous
  # command in a file.
  echo "$(date +%Y-%m-%d--%H-%M-%S) $(hostname) $PWD $(history 1)" >> ~/.full_history
}
PROMPT_COMMAND=promptFunc
function histgrep {
    cat ~/.full_history | grep "$@" | tail
}

# Add bash completion for ssh: it tries to complete the host to which you 
# want to connect from the list of the ones contained in ~/.ssh/known_hosts

__ssh_known_hosts() {
    if [[ -f ~/.ssh/known_hosts ]]; then
        cut -d " " -f1 ~/.ssh/known_hosts | cut -d "," -f1
    fi
}

_ssh() {
    local cur known_hosts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    known_hosts="$(__ssh_known_hosts)"
    
    if [[ ! ${cur} == -* ]] ; then
        COMPREPLY=( $(compgen -W "${known_hosts}" -- ${cur}) )
        return 0
    fi
}

complete -o bashdefault -o default -o nospace -F _ssh ssh 2>/dev/null \
    || complete -o default -o nospace -F _ssh ssh


stty -ixon
# for vim-ipython
stty stop undef # to unmap ctrl-s

function nametab {
    export PROMPT_COMMAND="echo -ne '\033]0;$@\007'"
}
alias nt=nametab

function git-vimerge {
    vim -p $(git --no-pager diff --name-status --diff-filter=U | awk 'BEGIN {x=""} {x=x" "$2;} END {print x}')
}

function wget-all { \
     --recursive \
     --no-clobber \
     --page-requisites \
     --html-extension \
     --convert-links \
     --restrict-file-names=windows \
     --domains $1 \
     --no-parent
}

#export DOCKER_CERT_PATH=/Users/mjr/.boot2docker/certs/boot2docker-vm
#export DOCKER_HOST=tcp://192.168.59.103:2376
#export DOCKER_TLS_VERIFY=1

function monitor {
    while true;
        do vardate=$(date +%Y\-%m\-%d\_%H:%M:%S);
        echo $vardate;
        screencapture -t jpg -x ~/Documents/data/monitor/${vardate}.jpg;
        sleep 500;
    done;
}
function docker-clean {
    docker rm -v $(docker ps -a -q -f status=exited)

    docker rmi $(docker images -f "dangling=true" -q)

    docker run -v /var/run/docker.sock:/var/run/docker.sock -v /var/lib/docker:/var/lib/docker --rm martin/docker-cleanup-volumes
}

source $DOTFILES_DIR/vscode/init.sh

set -o vi

#[ -f ~/.fzf.bash ] && source ~/.fzf.bash
