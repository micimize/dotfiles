# TODO should backup ~/.config
# https://unix.stackexchange.com/a/191676/203864

_DIR=$(dirname -- "$(readlink -f -- "$0")")

exclude_file="$_DIR/backup_exclude.txt"

cd $HOME

today=$(date +"%Y-%m-%d")

# Note: if restoring is necessary apt clone results should be in blackbox_2023-02-21.apt-clone.tar.gz
apt-clone clone blackbox_$today

env GZIP=-9 tar -cvzf blackbox_${today}_home.tar.gz --exclude-from=$exclude_file $HOME
