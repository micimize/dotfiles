if [[ $- != *i* ]] ; then
         # Shell is non-interactive.  Be done now!
         return
fi
 
#enable bash completion
[ -f /etc/profile.d/bash-completion ] && source /etc/profile.d/bash-completion
 
# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(lesspipe)"
 
# Shell variables
export PAGER=less
export EDITOR=vim
export GOPATH="$HOME/go"
PLAN9=$HOME/plan9port export PLAN9
export PATH=$PATH:$GOPATH/bin:$HOME/bin:$HOME/node_modules/.bin:$PLAN9/bin:/usr/local/sbin:/usr/local/Cellar/ruby/2.1.1_1/bin
export CLOJURESCRIPT_HOME=$HOME/code/clojure/clojurescript
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
 
## set options
set -o noclobber        # prevent overwriting files with cat
set -o ignoreeof        # stops ctrl+d from logging me out
 
 
 
# Set appropriate ls alias
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
alias chrome='open -a "/Applications/Google Chrome.app"'
 
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
if [ $(id -u) -eq 0 ];
        then # you are root, set red colour prompt
                export PS1="[\[$txtred\]\u\[$txtylw\]@\[$txtrst\]\h] \[$txtgrn\]\W\[$txtrst\]# "
        else

                export PS1="\[$txtcyn\]\D{%m-%d} \A \[$bldcyn\]$sp $ \[$txtrst\]"
                #shopt -s extdebug; trap "tput sgr0" DEBUG
                export SUDO_PS1="[\[$txtred\]\u\[$txtylw\]@\[$txtrst\]\h] \[$txtgrn\]\W\[$txtrst\]# "
        export LSCOLORS="fxgxcxdxbxegedabagacad"
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
 
psgrep() {
        if [ ! -z $1 ] ; then
                echo "Grepping for processes matching $1..."
                ps aux | grep $1 | grep -v grep
        else
 
                echo "!! Need name to grep for"
        fi
}
 
# clock - a little clock that appeares in the terminal window.
# Usage: clock.
#
clock ()
{
while true;do clear;echo "===========";date +"%r";echo "===========";sleep 1;done
}
 
# showip - show the current IP address if connected to the internet.
# Usage: showip.
#
showip ()
{
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


###############################
#     mjr customizations
###############################
alias ":q"="exit"
alias s="ls | GREP_COLOR='1;34' grep --color '.*@'"
alias l="ls"

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

function singleton-inspect {
    for FS in "|" "	" "," ";";
    do 
       (head -n 5 $1; tail -n 5 $1) | \
       awk -F "$FS" '(NR > 1 && (fieldcount != NF || NF == 1)){exit 1}; {fieldcount=NF}';
       if [ $? == 0 ]; then break; fi;
    done
    if [ $? == 1 ]; then "couldn't guess delimiter"; exit; fi;
    echo "delimiter: $(if [ "$FS" == "	" ]; then echo 'tab'; else echo $FS; fi;)"
    echo "fields:"
    csvcut -n -d "$FS" $1
    (head -n 5 $1; tail -n 5 $1) < "$1" | column -s "$FS" -t

    #check all lines for delimiters (assumes dirty data)
    awk -F "$FS" '(NR == 1){fieldcount=NF}; (NR > 1 && (fieldcount != NF || NF == 1)){print "record "NR" has the wrong field count:"; print $0};' $1;
    if [[ -n $(ggrep --color='auto' -P -n "[\x80-\xFF]" $1) ]];
    #expensive encoding checks
    then echo "Lines with NON-UTF8 characters:"
        ggrep --color='auto' -P -n "[\x80-\xFF]" $1;
    fi;

    if [[ -n $(diff $1 <(iconv -f utf-8 -t utf-8 -c $1)) ]];
    then echo "Lines with CONTROL characters:"
        awk 'NR==FNR{a[NR]=$0;next}{x=a[FNR];if($0!=x)printf("%s: %s\n",FNR,x)}' $1 <(iconv -f utf-8 -t utf-8 -c $1)
    fi;
}
function i {
    map singleton-inspect "$@"
}

#append empty records to a file
function flesh_out {
    awk -F "$2" '(NR == 1){fieldcount=NF}; (NR > 1){for (i = 1; i <= (fieldcount - NF); i++) $0=$0$FS}; {print $0}' testin.tsv | awk -F "\t" '{print NF}' $1
}

function archive {
    for item in "$@"
    do
        mv "$item" ~/archives/incoming
    done
}
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

alias elasticsearch-f='/Applications/elasticsearch-0.90.7/bin/elasticsearch -f'

alias searchjobs="ps -ef | grep -v grep | grep"
alias numbersum="paste -s -d+ - | bc"

#alias es='/usr/local/bin/emacs --daemon'
#alias emacs='/usr/local/bin/emacsclient -c'

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


# Lines added by the Vim-R-plugin command :RpluginConfig (2014-Jan-31 18:08):
# Change the TERM environment variable (to get 256 colors) and make Vim
# connecting to X Server even if running in a terminal emulator (to get
# dynamic update of syntax highlight and Object Browser):
if [ "x$DISPLAY" != "x" ]
then
    export HAS_256_COLORS=yes
    alias tmux="tmux -2"
    if [ "$TERM" = "xterm" ]
    then
        export TERM=xterm-256color
    fi
    if [ "$TERM" == "xterm" ] || [ "$TERM" == "xterm-256color" ]
    then
        function tvim(){ tmux -2 new-session "TERM=screen-256color vim $@" ; }
    else
        function tvim(){ tmux new-session "vim $@" ; }
    fi
else
    if [ "$TERM" == "xterm" ] || [ "$TERM" == "xterm-256color" ]
    then
        export HAS_256_COLORS=yes
        alias tmux="tmux -2"
        function tvim(){ tmux -2 new-session "TERM=screen-256color vim $@" ; }
    else
        function tvim(){ tmux new-session "vim $@" ; }
    fi
fi
if [ "$TERM" = "screen" ] && [ "$HAS_256_COLORS" = "yes" ]
then
    export TERM=screen-256color
fi

export PATH="$PATH:$HOME/.rvm/bin" # Add RVM to PATH for scripting

# for vim-ipython
stty stop undef # to unmap ctrl-s

function lolping {
    psum=0.0
    count=0
    while read ping
    do
        ptime=$(echo $ping | sed -e 's/^.*time=\(.*\) ms/\1/'  -e 'tx' -e 'd' -e ':x')
        if [ -n "$ptime" ]; then
            psum=$(echo "scale = 3; $psum + $ptime" | bc)
            ((count++))
            echo time=$ptime avg=$(bc <<< "scale = 3; $psum / $count")
        fi
    done < <(ping 216.52.241.254)
}
function nametab {
    export PROMPT_COMMAND="echo -ne '\033]0;$@\007'"
}
alias nt=nametab
function gamechanger {
    nt gamechanger/${1:-"code"}
    alias pushmaster="git push origin master:master"
    alias pushwhai="git push whai feature:master"
}
function drawbridge {
    nt drawbridge/${1:-"code"}
    alias pushmaster="git push origin master:master"
    alias pushkatie="git push katie feature:master"
}
