# mjr dotfiles and config

```
DOTFILE_DIR="~/code/personal/dotfiles"
mkdir -p "$DOTFILE_DIR"
cd "$DOTFILE_DIR"
git clone git@github.com:micimize/dotfiles.git .


# probably have to run manually:
# chsh -s /bin/bash

iterm theme: macos/iterm_solarized.josn in iterm
karabiner settings: macos/karabiner.json 

after installing vscode and firefox:
./setup.sh

```

This doesn't setup:
* mac: xcode, vscode, iterm, etc, etc

echo "
Setup should maybe hopefully be good now:
* You'll need to install vscode and terminal yourself
* 
* list of packages to install
* 
"