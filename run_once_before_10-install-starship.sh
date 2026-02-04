#!/bin/bash
# run_once_before_10-install-starship.sh
# Installs starship prompt if not already installed
# Requires: cargo (Rust toolchain)

set -e

if command -v starship &> /dev/null; then
    echo "starship already installed: $(starship --version)"
    exit 0
fi

echo "Installing starship..."
if command -v cargo &> /dev/null; then
    cargo install starship --locked
    echo "starship installed successfully"
else
    echo "Warning: cargo not found. Please install Rust toolchain first."
    echo "Visit: https://rustup.rs/"
    exit 0  # Don't fail - allow chezmoi to continue
fi
