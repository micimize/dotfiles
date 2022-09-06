#/bin/bash
#export PATH="$HOME/.yarn/bin:$PATH"

export NVM_DIR="/Users/mjr/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"  # This loads nvm

alias fixaudio="sudo killall coreaudiod"
function fixbluetooth {
    sudo kextunload -b com.apple.iokit.BroadcomBluetoothHostControllerUSBTransport
    sudo kextload -b com.apple.iokit.BroadcomBluetoothHostControllerUSBTransport
}

# Add environment variable COCOS_CONSOLE_ROOT for cocos2d-x
export COCOS_CONSOLE_ROOT=/Users/mjr/Documents/code/internal/cocos2d-js-v3.6/tools/cocos2d-console/bin
export PATH=$COCOS_CONSOLE_ROOT:$PATH


[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# TODO ?
source /Users/mjr/Library/Preferences/org.dystroy.broot/launcher/bash/br
