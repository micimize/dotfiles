#/bin/bash

_DIR=$(cd -P -- "$(dirname -- "$0")" && pwd -P)

ln -s $_DIR/keybindings.jsonc $HOME/.config/Code/User/keybindings.json
ln -s $_DIR/shell.sh $HOME/.vscode/shell.sh
