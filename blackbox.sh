#!/bin/bash

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

# TODO this whole thing is awkward but this especially
for arg in "$@"; do
  if [[ $arg =~ ^display ]]; then
    eval $arg
  fi
done

