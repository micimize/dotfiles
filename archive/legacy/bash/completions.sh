# enable bash completion
function _source_if_present {
  [ -f $1 ] && source $1
}
_source_if_present /etc/profile.d/bash_completion.sh
_source_if_present /etc/bash_completion
_source_if_present /usr/share/bash-completion/completions/fzf

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(lesspipe)"


complete -cf sudo # Tab complete for sudo

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

  if [[ ! ${cur} == -* ]]; then
    COMPREPLY=($(compgen -W "${known_hosts}" -- ${cur}))
    return 0
  fi
}

complete -o bashdefault -o default -o nospace -F _ssh ssh 2>/dev/null \
  || complete -o default -o nospace -F _ssh ssh

