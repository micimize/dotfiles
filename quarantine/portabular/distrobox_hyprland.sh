#!/bin/sh
unset LD_PRELOAD
xhost +si:localuser:$USER
sudo chown -f -R $USER:$USER /tmp/.X11-unix
/usr/bin/distrobox enter archlinux-toolbox-latest --additional-flags "--env DISPLAY=${DISPLAY}" -- Hyprland

pip install xcffib
pip install qtile

