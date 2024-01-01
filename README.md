# mjr dotfiles and config

```
DOTFILE_DIR="~/code/personal/dotfiles"
mkdir -p "$DOTFILE_DIR"
cd "$DOTFILE_DIR"
git clone git@github.com:micimize/dotfiles.git .
```

mac notes:
* probably have to run manually on mac: `chsh -s /bin/bash`
* iterm theme: `macos/iterm_solarized.json` 
* karabiner settings: `macos/karabiner.json`

after installing vscode and firefox:
`./setup.sh` which should be idempotent and refuse to configure that which already seems configured


TODO:
* ble-import vim-airline
* link/setup tridactyl
* attempt to setup gitlab and github
* clone writing repo
* This doesn't setup xcode, vscode, iterm, etc, etc
* nvim PlugInstall hangs with this init.vim on macos but works ok when pasted into another vim file
* vscode dir is wrong
* blesh fancy prompt, margin_pane sysem: https://github.com/akinomyoga/ble.sh/discussions/282#discussioncomment-5058432

[Desktop Entry]
Name=Qtile
Comment=Qtile Session
Exec=/home/mjr/code/libraries/qtile/.venv/bin/qtile start -c /home/mjr/code/libraries/qtile/config.py
Type=Application
Keywords=wm;tiling
