#!/bin/bash
set -u
set -x

if [ ! -d "$BLESH_DIR" ]; then
  mkdir -p "$BLESH_DIR"
  cd "$BLESH_DIR"
  git clone --recursive https://github.com/akinomyoga/ble.sh.git
  make -C ble.sh install PREFIX=~/.local
fi

# install homebrew
if ! command -v brew &>/dev/null; then
  $(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)
  brew install bash neovim tmux ncdu python3 ruby
fi

if [ ! -f "$HOME/.slate.js" ]; then
  ln -s $_DIR/slate.js $HOME/.slate.js
fi
