#!/bin/bash
# Install TPM (Tmux Plugin Manager) if not already present.
# chezmoi run_once_after script: runs once per machine after apply.

TPM_DIR="$HOME/.tmux/plugins/tpm"

if [ ! -d "$TPM_DIR" ]; then
  echo "Installing TPM (Tmux Plugin Manager)..."
  git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
  echo "TPM installed. Run 'prefix + I' inside tmux to install plugins."
fi
