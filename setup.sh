#!/bin/bash
set -u
set -x

_DIR=$(cd -P -- "$(dirname -- "$0")" && pwd -P)
source <(cat "$_DIR/bashrc" | grep "^export")
cd "$_DIR"

case $(uname -s) in
  Darwin | FreeBSD) source "$DOTFILES_DIR/macos/setup.sh" ;;
  Linux) source "$DOTFILES_DIR/blackbox/setup.sh" ;;
esac

ln

ln tmux.conf ~/.tmux.conf

mkdir -p ~/.config/nvim
# TODO maybe I can just link whole dir
ln init.vim ~/.config/nvim/init.vim

ln -s $(pwd)/firefox $FIREFOX_PROFILE_DIR/chrome

# ln zsh/p10k.zsh ~/.p10k.zsh; # ln (LiNk) that file to a file in ~ (your home directory)

#tmux plugin manager
function _install_tmux_plugins {
  mkdir -p ~/.tmux/plugins/tpm
  # TODO this is not really maintained
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
}
_install_tmux_plugins

#vim specific
function _install_nvim_plugins {
  plug_raw_source=https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  curl -fLo ~/.local/share/nvim/site/autoload --create-dirs $plug_raw_source
  nvim --headless +PlugInstall +qall
}
_install_nvim_plugins

# globally .gitignore
git config --global core.excludesfile ~/.gitignore
