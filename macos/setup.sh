#!/bin/bash
set -u
set -x

# install homebrew
if ! command -v brew &>/dev/null; then
  $(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)
  brew install bash neovim tmux ncdu \
    python3 ruby # maybe unneeded
fi

if [ ! -f "$HOME/.slate.js" ]; then
  ln -s $_DIR/slate.js $HOME/.slate.js
fi

if [ ! `which fzf` ]; then
  echo "fzf not installed, installing"
  brew install fzf
fi

if [ ! `which grealpath` ]; then
  echo "grealpath not installed, installing coreutils"
  brew install coreutils
fi

# To install useful key bindings and fuzzy completion:
# TODO is this setup or recurring?
$(brew --prefix)/opt/fzf/install
