TODO

This is the wrong way to go about this.
tiling window managers are too much of a pain and too far from the mainstream
rather, adapt your old system using hammerspoon to quicksnap to grid to use kde's scripting capabilities.

You should even be able to do relative splits of say, a firefox tab into a new window


# qeww_tile

Chimera Qtile setup attempting to fuse eww widgets into the layout.

Built around `flex_tile`, a fork of `qtile-plasma` with hopefully some added useful stuff
- [ ] Collapsing minimization
- [ ] Dashboard scratchpad
- [ ] Modes
- [ ] Visual mode (select, cut/paste windows)


Widgets were initially taken from https://github.com/PoSayDone/.dotfiles_new


### scratch notes
```bash
sudo apt install python3-gi python3-gi-cairo gir1.2-gtk-4.0
pip install material_color_utilities_python

sudo apt-get install libgdk-3-dev libgtk-3-dev gtk-layer-shell libpango1.0-dev libgdk-pixbuf2.0-dev libcairo2-dev libcairo-gobject2 libglib2.0-dev libgio2.0-dev libgobject-2.0-dev libgcc-9-dev libc6-dev
sudo apt-get update && sudo apt-get install libgtk-3-dev libgtk-layer-shell-dev
sudo apt-get install -f
sudo apt-get install libbrotli1=1.0.9-2build8 libwebp7=1.2.4-0.3 libwebpmux3=1.2.4-0.3 libwebpdemux2=1.2.4-0.3
sudo apt-get install libbrotli-dev libwebp-dev
sudo apt-get install libgtk-3-dev libgtk-layer-shell-dev
pip install material_color_utilities_python
sudo apt install python3-gi python3-gi-cairo gir1.2-gtk-4.0

git clone git@github.com:elkowar/eww.git

git clone git@github.com:micimize/qtile-plasma.git
pip install --upgrade qtile-plasma
pip install -e ./qtile-plasma/

 pip install xcffib
 pip install xcffib
 pip install qtile
 pip install pywlroots

pip3 install PyGObject

sudo apt-get install rofi


TODO:
So, it is possible to use KDE with a different window manager.
This means instead of having to rip the bandaid off, I can just swap kwin for qtile, etc.
krunner seems to be the only launcher with a good firefox integration, which is pretty clutch of it.
there's also all kinds of system apps etc that you get for free with KDE, so probably stick to plasma
the main point is to containerize the dealy so you can reload it elsewhere

Switch to ~vifm~ broot


"/usr/share/wayland-sessions/qtile.desktop"
[Desktop Entry]
Name=Qtile (Wayland)
Comment=Qtile Session
Exec=/home/mjr/code/libraries/qtile/.venv/bin/qtile start -b wayland
Type=Application
Keywords=wm;tiling

[Desktop Entry]
Name=Qtile
Comment=Qtile Session
Exec=/home/mjr/code/libraries/qtile/.venv/bin/qtile start -c /home/mjr/code/libraries/qtile/config.py
Type=Application
Keywords=wm;tiling

xinput set-prop 10 284 1

libconfig-dev libdbus-1-dev libegl-dev libev-dev libgl-dev libpcre2-dev libpixman-1-dev libx11-xcb-dev libxcb1-dev libxcb-composite0-dev libxcb-damage0-dev libxcb-dpms0-dev libxcb-glx0-dev libxcb-image0-dev libxcb-present-dev libxcb-randr0-dev libxcb-render0-dev libxcb-render-util0-dev libxcb-shape0-dev libxcb-util-dev libxcb-xfixes0-dev libxext-dev meson ninja-build uthash-dev
git clone https://github.com/FT-Labs/picom
cd picom
meson --buildtype=release . build
sudo ninja -C build install
cd ..
```

git clone https://github.com/P3rf/rofi-network-manager.git
cd rofi-network-manager
bash "./rofi-network-manager.sh"