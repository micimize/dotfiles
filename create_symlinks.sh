#!/bin/bash
for rc in .*rc .*conf; # for each file matching the pattern .*rc or .*conf in the current directory
do
    echo symlinking $rc
    ln $rc ~/$rc; # ln (LiNk) that file to a file in ~ (your home directory)
done


ln zsh/p10k.zsh ~/.p10k.zsh; # ln (LiNk) that file to a file in ~ (your home directory)

#tmux plugin manager
mkdir -p ~/.tmux/plugins/tpm
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

#vim specific
git clone https://github.com/gmarik/Vundle.vim.git ~/.vim/bundle/Vundle.vim
vim +PluginInstall +qall

# globally .gitignore
git config --global core.excludesfile ~/.gitignore
