sudo umount /run/systemd/system
sudo rmdir /run/systemd/system
sudo ln -s /run/host/run/systemd/system /run/systemd
sudo ln -s /run/host/run/dbus/system_bus_socket /run/dbus/

# sudo vim /etc/profile.d/fix_tmp.sh 
# chown -f -R $USER:$USER /tmp/.X11-unix

[Desktop Entry]
Exec=/usr/sbin/Hyprland
DesktopNames=Hyprland
Name=Wayland Hyprland (arch distrobox)
X-KDE-PluginInfo-Version=5.27.4

export XAUTHORITY=/home/mjr/.Xauthority; \
export XDG_RUNTIME_DIR=/run/user/1000; \
export CLUTTER_BACKEND=x11; \
export QT_X11_NO_MITSHM=1; \