#!/bin/bash
# run_once_before_30-install-carapace.sh
# Installs carapace for nushell completions (nushell itself is already installed)

if ! command -v carapace &> /dev/null; then
    if command -v go &> /dev/null; then
        go install github.com/carapace-sh/carapace-bin@latest
    else
        echo "carapace: go not found. Install manually:"
        echo "  go install github.com/carapace-sh/carapace-bin@latest"
        echo "  OR download from https://github.com/carapace-sh/carapace-bin/releases"
        echo "  (Optional: nushell works without carapace, with reduced completions)"
    fi
fi
