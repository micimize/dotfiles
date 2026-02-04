#!/bin/bash
# run_once_after_10-install-tpm.sh
# Installs TPM (Tmux Plugin Manager) if not already installed
# Runs after file installation because it depends on ~/.tmux.conf existing
# Requires: git

set -e

TPM_DIR="$HOME/.tmux/plugins/tpm"

if [ -d "$TPM_DIR" ]; then
    echo "TPM already installed at $TPM_DIR"
    exit 0
fi

echo "Installing TPM (Tmux Plugin Manager)..."

if ! command -v git &> /dev/null; then
    echo "Warning: git not found. Cannot install TPM."
    exit 0
fi

mkdir -p "$HOME/.tmux/plugins"
git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR"

echo "TPM installed successfully"
echo "Note: Run 'prefix + I' in tmux to install plugins defined in tmux.conf"
