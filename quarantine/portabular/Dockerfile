FROM quay.io/toolbx-images/archlinux-toolbox:latest

RUN	pacman -Syy



# hostname, window manager, auth utils for wm
RUN pacman -S --noconfirm inetutils \
  qt5-wayland qt6-wayland \
  pipewire wireplumber \
  polkit polkit-kde-agent \
  hyprland xdg-desktop-portal-hyprland \

  pacman -S --noconfirm nvidia=545.23.08 nvidia-dkms=545.23.08

