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
* https://github.com/andresgongora/synth-shell
* link/setup tridactyl
* attempt to setup gitlab and github
* clone writing repo
* This doesn't setup xcode, vscode, iterm, etc, etc