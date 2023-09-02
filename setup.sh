#!/bin/bash
set -u
set -e
set -x

_DIR=$(dirname -- "$(readlink -f -- "$0")")
eval $(grep -h "^export" "$_DIR/bash/"*)

if [ "$1" == "--overwrite" ]; then
  echo "Overwriting existing files"
  _OVERWRITE="true"
else
  _OVERWRITE="false"
fi

function setup_block {
  source_file="$1"
  target_file="${2/#\~/$HOME}"
  additional="${3:-}"
  mkdir -p "$(dirname "$target_file")"
  if [[ ( -f "$target_file" || -L "$target_file" )  && "$_OVERWRITE" == "true" ]]; then
    echo "overwriting $target_file"
    rm -f "$target_file"
  fi

  if [[ -f "$target_file" || -L "$target_file" ]]; then
    echo "already configured: $target_file"
  else
    echo -e "\n\nInstalling $source_file to $target_file\n"
    ln "$_DIR/$source_file" "$target_file"
    if [ "$additional" != "" ]; then
      echo -e "\n\nRunning $additional\n"
      $additional
    fi
  fi
}

case $(uname -s) in
  Darwin | FreeBSD) eval $(grep "^export [^-]" "$_DIR/macos/macos.sh") ;;
  Linux | FreeBSD) eval $(grep "^export [^-]" "$_DIR/blackbox/blackbox.sh") ;;
esac
cd "$_DIR"

case $(uname -s) in
  Darwin | FreeBSD) source "$DOTFILES_DIR/macos/setup.sh" ;;
  Linux) source "$DOTFILES_DIR/blackbox/setup.sh" ;;
esac

function _install_bashrc_dependencies {
  cargo install starship --locked
}
setup_block bash/bashrc ~/.bashrc _install_bashrc_dependencies 

function _setup_blerc_dir {
  if [ ! -d "$BLESH_DIR" ]; then
    mkdir -p "$BLESH_DIR/src"
    pushd "$BLESH_DIR/src"
    git clone --recursive https://github.com/akinomyoga/ble.sh.git .
    make install PREFIX=~/.local
    popd
  fi
}
setup_block bash/blerc ~/.blerc _setup_blerc_dir

setup_block bash/starship.toml ~/.config/starship.toml


function _install_tmux_plugins {
  TPM_DIR=~/.tmux/plugins/tpm
  if [ ! -d "$TPM_DIR" ]; then
    mkdir -p "$TPM_DIR"
    # TODO this is not really maintained
    git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
  fi
}
setup_block tmux.conf ~/.tmux.conf _install_tmux_plugins

function _install_nvim_plugins {
  plug_raw_source=https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  autoload_dir="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/site/autoload"
  curl -fLo "$autoload_dir/plug.vim" --create-dirs $plug_raw_source
  # ~/.local/share/nvim/site/autoload
  nvim --headless +PlugInstall "+qall!"
}
setup_block init.vim ~/.config/nvim/init.vim _install_nvim_plugins


if [ ! -d "$FIREFOX_PROFILE_DIR" ]; then
  echo "warning: FIREFOX_PROFILE_DIR $FIREFOX_PROFILE_DIR doesn't exist"
elif [ -d "$FIREFOX_PROFILE_DIR/chrome" ]; then
  echo "already configured: firefox"
else
  ln -s "$_DIR/firefox" $FIREFOX_PROFILE_DIR/chrome
fi

function _install_tridactyl_native {
  tridactyl_installer=https://raw.githubusercontent.com/tridactyl/native_messenger/master/installers/install.sh
  version=1.22.1
  temp_file=/tmp/trinativeinstall.sh
  curl -fsSl $tridactyl_installer -o $temp_file
  sh $temp_file $version
  rm -f $temp_file
}
setup_block tridactyl/tridactylrc ~/.config/tridactyl/tridactylrc _install_tridactyl_native

# case $(uname -s) in
#   Darwin | FreeBSD) _VSCODE_DIR="$HOME/vscode/.config/Code/User/";;
#   Linux) _VSCODE_DIR="$HOME/vscode/.config/Code/User/";;
# esac

if [ ! -d "$HOME/vscode" ]; then
  echo "warning: $HOME/vscode doesn't exist"
elif [ -f "$HOME/.vscode/shell.sh" ]; then
  echo "already configured: firefox"
else
  ln "$_DIR/vscode/keybindings.jsonc" "$HOME/.config/Code/User/keybindings.json"
  ln "$_DIR/vscode/settings.jsonc" "$HOME/.config/Code/User/settings.json"
  ln "$_DIR/shell.sh" "$HOME/.vscode/shell.sh"
fi

# globally .gitignore
git config --global core.excludesfile ~/.gitignore
