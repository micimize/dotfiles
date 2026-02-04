#!/bin/bash
set -u
set -x

sudo pacman -Syu

sudo pacman -S flatpak ack

sudo pacman -S neovim tmux ncdu fzf
