#!/bin/bash
set -u
set -x

# install homebrew
if ! command -v brew &>/dev/null; then
  $(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)
  brew install bash neovim tmux ncdu binutils \
    python3 ruby # maybe unneeded
fi

if [ ! -f "$HOME/.slate.js" ]; then
  ln -s $_DIR/slate.js $HOME/.slate.js
fi
