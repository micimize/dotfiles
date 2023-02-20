#!/bin/bash

# blech
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/home/mjr/.mujoco/mujoco210/bin:/usr/lib/nvidia

export FIREFOX_PROFILE_DIR="$HOME/snap/firefox/common/.mozilla/firefox/bsx5dc2h.default"

function firefox_hack_recovery {
  # for parsing jsonlv4: https://gist.github.com/Tblue/62ff47bef7f894e92ed5
  backup_dir="$FIREFOX_PROFILE_DIR/sessionstore-backups"
  ls -l "$backup_dir"
  cp -R "$backup_dir/*" ~/ff_backups/
  rm "$backup_dir/recovery.jsonlv4"
}

alias clockui='plasmawindowed org.kde.plasma.digitalclock'

alias is_audio_playing="pacmd list-sink-inputs | grep -c 'state: RUNNING'"
function no_sleep_while_music {
  while :; do
    if [ $(xprintidle) -gt 100000 ]; then
      if [ $(is_audio_playing) ]; then
        xdotool key shift
      fi
    fi

    sleep 30
  done
}

export RES_4K=4096x2160
export RES_QHD=2560x1440

function display_4k {
  xrandr --output HDMI-0 --mode $RES_4K
}
export -f display_4k

function display_qhd {
  xrandr --output HDMI-0 --mode $RES_QHD
}
export -f display_qhd

function display_game {
  bash /home/mjr/code/libraries/tv_remote/set_picture_mode.sh game
}
export -f display_game

function display_normal {
  bash /home/mjr/code/libraries/tv_remote/set_picture_mode.sh expert2
}
export -f display_normal

function display_tv_time {
  display_qhd
  bash /home/mjr/code/libraries/tv_remote/set_picture_mode.sh normal
}
export -f display_tv_time

alias copy='xclip -sel clip'

function refresh_gpu {
  sudo rmmod nvidia_uvm
  sudo modprobe nvidia_uvm
}