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

# NOTE: using hard links avoids fragility
if [ -f "$HOME/.tmux.conf" ]; then
  echo "already configured: tmux"
else
  ln "$_DIR/tmux.conf" "$HOME/.tmux.conf"

  #tmux plugin manager
  function _install_tmux_plugins {
    mkdir -p ~/.tmux/plugins/tpm
    # TODO this is not really maintained
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
  }
  _install_tmux_plugins
fi

if [ -f "$HOME/.config/nvim/init.vim" ]; then
  echo "already configured: nvim"
else
  mkdir -p "$HOME/.config/nvim"
  # TODO maybe I can just link whole dir
  ln "$_DIR/init.vim" "$HOME/.config/nvim/init.vim"

  #vim specific
  function _install_nvim_plugins {
    plug_raw_source=https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
    curl -fLo ~/.local/share/nvim/site/autoload --create-dirs $plug_raw_source
    nvim --headless +PlugInstall +qall
  }
  _install_nvim_plugins
fi

if [ ! -d "$FIREFOX_PROFILE_DIR" ]; then
  echo "warning: FIREFOX_PROFILE_DIR $FIREFOX_PROFILE_DIR doesn't exist"
elif [ -d "$FIREFOX_PROFILE_DIR/chrome" ]; then
  echo "already configured: firefox"
else
  ln -s "$_DIR/firefox" $FIREFOX_PROFILE_DIR/chrome
fi

if [ ! -d "$HOME/vscode" ]; then
  echo "warning: $HOME/vscode doesn't exist"
elif [ -f "$HOME/vscode/.vscode/shell.sh" ]; then
  echo "already configured: firefox"
else
  ln "$_DIR/vscode/keybindings.jsonc" "$HOME/vscode/.config/Code/User/keybindings.json"
  ln "$_DIR/shell.sh" "$HOME/vscode/.vscode/shell.sh"
fi

# globally .gitignore
git config --global core.excludesfile ~/.gitignore
