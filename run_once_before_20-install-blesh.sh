#!/bin/bash
# run_once_before_20-install-blesh.sh
# Installs ble.sh (Bash Line Editor) if not already installed
# Requires: git, make

set -e

BLESH_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/blesh"

if [ -d "$BLESH_DIR" ] && [ -f "$BLESH_DIR/ble.sh" ]; then
    echo "ble.sh already installed at $BLESH_DIR"
    exit 0
fi

echo "Installing ble.sh..."

# Check dependencies
if ! command -v git &> /dev/null; then
    echo "Warning: git not found. Cannot install ble.sh."
    exit 0
fi

if ! command -v make &> /dev/null; then
    echo "Warning: make not found. Cannot install ble.sh."
    exit 0
fi

# Create directory structure
mkdir -p "$BLESH_DIR/src"

# Clone and build
echo "Cloning ble.sh repository..."
git clone --recursive --depth 1 https://github.com/akinomyoga/ble.sh.git "$BLESH_DIR/src"

echo "Building ble.sh..."
make -C "$BLESH_DIR/src" install PREFIX="$HOME/.local"

echo "ble.sh installed successfully"
