#
# Utility functions
#

# Delete line from known_hosts
# courtesy of rpetre from reddit
ssh-del() {
  sed -i -e ${1}d ~/.ssh/known_hosts
}

# Grep processes
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

# extract files eg: ex tarball.tar#
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
# function monitor {
#   while true;
#   do vardate=$(date +%Y\-%m\-%d\_%H:%M:%S);
#     echo $vardate;
#     screencapture -t jpg -x ~/Documents/data/monitor/${vardate}.jpg;
#     sleep 500;
#   done;
# }

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

