#!/bin/sh
set -e

# Set WezTerm as the default KDE terminal emulator
if ! command -v kwriteconfig6 >/dev/null 2>&1; then
    echo "kwriteconfig6 not found, skipping default terminal setup"
    exit 0
fi

kwriteconfig6 --file kdeglobals --group General --key TerminalApplication /home/linuxbrew/.linuxbrew/bin/wezterm
kwriteconfig6 --file kdeglobals --group General --key TerminalService org.wezfurlong.wezterm.desktop

# Rebuild desktop and icon caches so KRunner and the app menu pick up changes immediately
update-desktop-database ~/.local/share/applications/ 2>/dev/null || true
gtk-update-icon-cache ~/.local/share/icons/hicolor/ 2>/dev/null || true
