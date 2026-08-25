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

function tmux-kill-all-sessions {
  prefix="$1"
  current=`current_tmux_session`
  for session in $(tmux list-sessions | awk 'BEGIN{FS=":"}{print $1}'); do
    if [[ "$session" == "$current"*  ]]; then
      echo "skipping $session: is current session"
      continue
    fi
    if [[ "$session" == "$prefix"* && "$" ]]; then
      echo "killing $session"
      tmux kill-session -t "$session"
    fi
  done
}


alias searchjobs="ps -ef | grep -v grep | grep"
alias numbersum="paste -s -d+ - | bc"

alias current_tmux_session='[ -n "$TMUX" ] && tmux display-message -p "#S" || echo'

# ── wt-clone: Fresh bare-worktree clone command ──
# Ported from dot_config/nushell/scripts/wt-clone.nu.
# Creates the nikitabobko convention layout that lace's classifyWorkspace() recognizes:
#   project/.bare/        (bare git database)
#   project/.git          (gitdir: ./.bare)
#   project/main/         (worktree tracking default branch)
#   project/.worktree-root
# One container mounts the project/ parent; all worktrees are siblings inside it.
# See: https://nikitabobko.github.io/blog/git-worktree

# Derive repo name from a git URL (SSH or HTTPS)
_wt_repo_name() {
  local url="$1" path_part
  # SSH: git@github.com:org/repo.git -> split on ":", take path, basename
  # HTTPS: https://github.com/org/repo.git -> basename directly
  if [[ "$url" == *:* && "$url" != http* ]]; then
    path_part="${url##*:}"
  else
    path_part="$url"
  fi
  path_part="${path_part##*/}"          # basename
  path_part="${path_part%.git}"         # strip trailing .git
  echo "$path_part"
}

# Fix worktree gitdir paths to relative pointers (critical for container portability)
_wt_fix_paths() {
  local name="$1" root="$2"
  printf 'gitdir: ../.bare/worktrees/%s\n' "$name" > "$root/$name/.git"
  printf '../../%s\n' "$name" > "$root/.bare/worktrees/$name/gitdir"
}

# Clone a git repo into bare-worktree layout
# Usage: wt-clone URL [TARGET] [-b BRANCH] [-n NAME] [--shallow]
wt-clone() {
  local reserved=(".bare" ".git" ".worktree-root")
  local url="" target="" branch="" name="" shallow=0
  local positional=()

  while [ $# -gt 0 ]; do
    case "$1" in
      -b|--branch) branch="$2"; shift 2 ;;
      -n|--name)   name="$2";   shift 2 ;;
      --shallow)   shallow=1;   shift ;;
      -h|--help)
        echo "Usage: wt-clone URL [TARGET] [-b BRANCH] [-n NAME] [--shallow]"
        return 0 ;;
      *) positional+=("$1"); shift ;;
    esac
  done

  url="${positional[0]}"
  target="${positional[1]}"

  if [ -z "$url" ]; then
    echo "wt-clone: a git remote URL is required" >&2
    return 1
  fi

  # Resolve target to an absolute path (parent need not exist yet)
  if [ -n "$target" ]; then
    case "$target" in
      /*) : ;;
      ~*) target="${target/#\~/$HOME}" ;;
      *)  target="$PWD/$target" ;;
    esac
  else
    target="$PWD/$(_wt_repo_name "$url")"
  fi

  # Check target directory (must not exist non-empty)
  if [ -e "$target" ] && [ -n "$(ls -A "$target" 2>/dev/null)" ]; then
    echo "wt-clone: target directory '$target' already exists and is not empty. Choose a different target or remove it first." >&2
    return 1
  fi

  # Validate --name early if provided
  if [ -n "$name" ]; then
    for r in "${reserved[@]}"; do
      if [ "$name" = "$r" ]; then
        echo "wt-clone: worktree name '$name' conflicts with layout structure. Use --name to choose a different name." >&2
        return 1
      fi
    done
  fi

  local bare_dir="$target/.bare"

  echo "Cloning $url..."
  if [ "$shallow" -eq 1 ]; then
    git clone --bare --depth 1 "$url" "$bare_dir" || { [ -e "$target" ] && rm -rf "$target"; echo "wt-clone: clone failed. Check the URL and your network connection." >&2; return 1; }
  else
    git clone --bare "$url" "$bare_dir" || { [ -e "$target" ] && rm -rf "$target"; echo "wt-clone: clone failed. Check the URL and your network connection." >&2; return 1; }
  fi

  # Create .git file pointing to bare db
  printf 'gitdir: ./.bare\n' > "$target/.git"

  # Configure fetch refspec for all branches (bare clone default is too restrictive)
  git -C "$bare_dir" config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"

  # Fetch all refs
  if [ "$shallow" -eq 1 ]; then
    git -C "$bare_dir" fetch origin --depth 1 || echo "wt-clone: warning: fetch failed. Remote branches may be incomplete." >&2
  else
    git -C "$bare_dir" fetch origin || echo "wt-clone: warning: fetch failed. Remote branches may be incomplete." >&2
  fi

  # Determine default branch
  if [ -z "$branch" ]; then
    branch="$(git -C "$bare_dir" symbolic-ref HEAD 2>/dev/null | sed 's|refs/heads/||' | tr -d '[:space:]')"
    [ -z "$branch" ] && branch="main"
  fi

  # Determine worktree name
  local wt_name="${name:-$branch}"
  for r in "${reserved[@]}"; do
    if [ "$wt_name" = "$r" ]; then
      rm -rf "$target"
      echo "wt-clone: worktree name '$wt_name' conflicts with layout structure. Use --name to choose a different name." >&2
      return 1
    fi
  done

  # Create worktree
  if ! git -C "$bare_dir" worktree add "../$wt_name" "$branch"; then
    rm -rf "$target"
    echo "wt-clone: failed to create worktree '$wt_name' for branch '$branch'. Does the branch exist?" >&2
    return 1
  fi

  # Fix gitdir paths to relative (container portability)
  _wt_fix_paths "$wt_name" "$target"

  # Create .worktree-root marker
  printf '# This file marks the root of a bare-worktree layout.\n# See: https://nikitabobko.github.io/blog/git-worktree\n' > "$target/.worktree-root"

  # Detect submodules
  local has_submodules=0
  [ -f "$target/$wt_name/.gitmodules" ] && has_submodules=1

  # Summary
  if [ "$shallow" -eq 1 ]; then
    echo "Note: Shallow clone. Run \`git fetch --unshallow\` for full history."
  fi

  echo
  echo "Created bare-worktree layout:"
  echo "  $target/"
  echo "    .bare/          (bare git database)"
  echo "    .git            (gitdir: ./.bare)"
  echo "    $wt_name/         (worktree: $branch)"
  echo "    .worktree-root"

  if [ "$has_submodules" -eq 1 ]; then
    echo
    echo "This repo uses submodules. Run:"
    echo "  cd $target/$wt_name && git submodule update --init --recursive"
  fi

  echo
  echo "Next steps:"
  echo "  cd $target/$wt_name"
  if [ -d "$target/$wt_name/.devcontainer" ]; then
    echo "  lace up"
  fi
}
