## /bin/sh
set -u
set -x

_DIR=$(cd -P -- "$(dirname -- "$0")" && pwd -P)
source <(cat "$_DIR/../bashrc" | grep "^export")

if [ ! -d "$BLESH_DIR" ]; then
  mkdir -p "$BLESH_DIR"
  cd "$BLESH_DIR"
  git clone --recursive https://github.com/akinomyoga/ble.sh.git
  make -C ble.sh install PREFIX=~/.local
fi

# install homebrew
if ! command -v brew &>/dev/null; then
  $(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)
fi

brew install neovim tmux ncdu

ln -s $_DIR/slate.js $HOME/.slate.js

echo "
probably have to run manually:
chsh -s /bin/bash

iterm theme: macos/iterm_solarized.josn in iterm
karabiner settings: macos/karabiner.json 

after installing vscode and firefox:
$DOTFILES_DIR/vscode/create_symlinks.sh
$DOTFILES_DIR/vscode/create_symlinks.sh


"
