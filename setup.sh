#!/bin/bash
set -u
set -e
set -x

_DIR=$(dirname -- "$(readlink -f -- "$0")")
eval $(grep -h "^export" "$_DIR/bash/"*)

_OVERWRITE="false"
JUST_PATHS=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --overwrite)
      echo "Overwriting existing files"
      _OVERWRITE="true"
      shift
      ;;
    *)
      echo "Inclusion-only mode: will setup $1"
      JUST_PATHS+=("$1")
      shift
      ;;
  esac
done

function setup_symlink {
  if [[ ${#JUST_PATHS[@]} -gt 0 ]]; then
    if [[ ! " ${JUST_PATHS[@]} " =~ " $1 " ]]; then
      return
    fi
  fi
  source_file=$(realpath "$_DIR/$1")
  target_file="${2/#\~/$HOME}"
  additional="${3:-}"
  mkdir -p "$(dirname "$target_file")"

  if [[ ( -f "$target_file" || -L "$target_file") && "$_OVERWRITE" == "true" ]]; then
    echo "overwriting $target_file"
    rm -f "$target_file"
  fi

  if [[ -f "$target_file" || -L "$target_file" ]]; then
    echo -e "\nalready exists: $target_file\n"
    return
  fi
  echo -e "\n\nInstalling $1 to $target_file\n"
  ln -s "$source_file" "$target_file"
  if [ "$additional" != "" ]; then
    echo -e "\n\nRunning $additional\n"
    $additional
  fi
}

case $(uname -s) in
  Darwin | FreeBSD) eval $(grep "^export [^-]" "$_DIR/macos/macos.sh") ;;
  Linux | FreeBSD) eval $(grep "^export [^-]" "$_DIR/blackbox/blackbox.sh") ;;
esac
cd "$_DIR"

if [[ ${#JUST_PATHS[@]} == 0 ]]; then
  case $(uname -s) in
    Darwin | FreeBSD) source "$DOTFILES_DIR/macos/setup.sh" ;;
    Linux) source "$DOTFILES_DIR/blackbox/setup.sh" ;;
  esac
fi

function _install_bashrc_dependencies {
  cargo install starship --locked
}
setup_symlink bash/bashrc ~/.bashrc _install_bashrc_dependencies 

function _setup_blerc_dir {
  if [ ! -d "$BLESH_DIR" ]; then
    mkdir -p "$BLESH_DIR/src"
    pushd "$BLESH_DIR/src"
    git clone --recursive https://github.com/akinomyoga/ble.sh.git .
    make install PREFIX=~/.local
    popd
  fi
}
setup_symlink bash/blerc ~/.blerc _setup_blerc_dir

setup_symlink bash/starship.toml ~/.config/starship.toml


function _install_tmux_plugins {
  TPM_DIR=~/.tmux/plugins/tpm
  if [ ! -d "$TPM_DIR" ]; then
    mkdir -p "$TPM_DIR"
    # TODO this is not really maintained
    git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
  fi
}
setup_symlink tmux.conf ~/.tmux.conf _install_tmux_plugins

function _install_nvim_plugins {
  plug_raw_source=https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  autoload_dir="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/site/autoload"
  curl -fLo "$autoload_dir/plug.vim" --create-dirs $plug_raw_source
  # ~/.local/share/nvim/site/autoload
  nvim --headless +PlugInstall "+qall!"
}
setup_symlink init.vim ~/.config/nvim/init.vim _install_nvim_plugins

setup_symlink firefox "$FIREFOX_PROFILE_DIR/chrome"

function _install_tridactyl_native {
  tridactyl_installer=https://raw.githubusercontent.com/tridactyl/native_messenger/master/installers/install.sh
  version=1.22.1
  temp_file=/tmp/trinativeinstall.sh
  curl -fsSl $tridactyl_installer -o $temp_file
  sh $temp_file $version
  rm -f $temp_file
}
setup_symlink tridactyl/tridactylrc ~/.config/tridactyl/tridactylrc _install_tridactyl_native

if [ ! -d "$HOME/.vscode" ]; then
  echo "warning: $HOME/.vscode doesn't exist"
elif [ -f "$HOME/.vscode/shell.sh" ]; then
  echo "already configured: vscode"
else
  setup_symlink vscode/keybindings.jsonc "$VSCODE_CONFIG_DIR/keybindings.json"
  setup_symlink vscode/settings.jsonc "$VSCODE_CONFIG_DIR/settings.json"
  ln vscode/shell.sh "$HOME/.vscode/shell.sh"
fi

# globally .gitignore
git config --global core.excludesfile ~/.gitignore
