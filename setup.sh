#!/bin/bash
set -u
set -x

_DIR=$(dirname -- "$(readlink -f -- "$0")")
eval $(grep "^export" "$_DIR/bashrc")
case $(uname -s) in
  Darwin | FreeBSD) eval $(grep "^export" "$_DIR/macos/macos.sh") ;;
  Linux | FreeBSD) eval $(grep "^export" "$_DIR/blackbox/blackbox.sh") ;;
esac
cd "$_DIR"

case $(uname -s) in
  Darwin | FreeBSD) source "$DOTFILES_DIR/macos/setup.sh" ;;
  Linux) source "$DOTFILES_DIR/blackbox/setup.sh" ;;
esac

if [ -f "$HOME/.bashrc" ]; then
  echo "already configured: bashrc"
else
  ln "$_DIR/bashrc" "$HOME/.bashrc"
fi

if [ -f "$HOME/.blerc" ]; then
  echo "already configured: blerc"
else
  ln "$_DIR/blerc" "$HOME/.blerc"
  if [ ! -d "$BLESH_DIR" ]; then
    mkdir -p "$BLESH_DIR/src"
    pushd "$BLESH_DIR/src"
    git clone --recursive https://github.com/akinomyoga/ble.sh.git .
    make install PREFIX=~/.local
    popd
  fi
fi

# NOTE: using hard links avoids fragility
if [ -f "$HOME/.tmux.conf" ]; then
  echo "already configured: tmux"
else
  ln "$_DIR/tmux.conf" "$HOME/.tmux.conf"

  # tmux plugin manager
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

  function _install_nvim_plugins {
    plug_raw_source=https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
    autoload_dir="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/site/autoload"
    curl -fLo "$autoload_dir/plug.vim" --create-dirs $plug_raw_source
    # ~/.local/share/nvim/site/autoload
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
  ln -s "_$DIR/firefox/tridactylrc" "$HOME/.config/tridactylrc"
fi

if [ -f "$HOME/.config/tridactyl/tridactylrc" ]; then
  echo "already configured: tridactyl"
else
  ln -s "_$DIR/tridactyl" "$HOME/.config/tridactyl"
  function _install_tridactyl_native {
    tridactyl_installer=https://raw.githubusercontent.com/tridactyl/native_messenger/master/installers/install.sh
    version=1.22.1
    temp_file=/tmp/trinativeinstall.sh
    curl -fsSl $tridactyl_installer -o $temp_file
    sh $temp_file $version
    rm -f $temp_file
  }
  _install_tridactyl_native
fi

if [ ! -d "$HOME/vscode" ]; then
  echo "warning: $HOME/vscode doesn't exist"
elif [ -f "$HOME/.vscode/shell.sh" ]; then
  echo "already configured: firefox"
else
  ln "$_DIR/vscode/keybindings.jsonc" "$HOME/vscode/.config/Code/User/keybindings.json"
  ln "$_DIR/shell.sh" "$HOME/vscode/.vscode/shell.sh"
fi

# globally .gitignore
git config --global core.excludesfile ~/.gitignore
