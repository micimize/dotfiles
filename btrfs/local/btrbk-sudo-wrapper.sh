#!/usr/bin/env bash
#
# btrbk-sudo-wrapper.sh - Wrapper to run btrbk with sudo while preserving SSH agent
#
# This script solves the problem where sudo doesn't preserve SSH_AUTH_SOCK,
# preventing btrbk from using your 1Password SSH agent for remote backups.
#
# Usage:
#   ./btrbk-sudo-wrapper.sh [btrbk arguments]
#
# Examples:
#   ./btrbk-sudo-wrapper.sh -v -n run    # dry-run
#   ./btrbk-sudo-wrapper.sh -v run       # actual backup
#   ./btrbk-sudo-wrapper.sh snapshot     # local snapshots only
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if SSH_AUTH_SOCK is set
if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
    echo -e "${RED}ERROR:${NC} SSH_AUTH_SOCK is not set" >&2
    echo "Your SSH agent (e.g., 1Password) is not running or not configured" >&2
    echo "Please ensure your SSH agent is running and try again" >&2
    exit 1
fi

# Check if the socket exists
if [[ ! -S "$SSH_AUTH_SOCK" ]]; then
    echo -e "${RED}ERROR:${NC} SSH_AUTH_SOCK points to non-existent socket: $SSH_AUTH_SOCK" >&2
    echo "Your SSH agent socket is not accessible" >&2
    exit 1
fi

# Get the btrbk config path (default to local config)
BTRBK_CONFIG="${BTRBK_CONFIG:-$(dirname "$0")/btrbk.conf}"

# Check if config exists
if [[ ! -f "$BTRBK_CONFIG" ]]; then
    echo -e "${RED}ERROR:${NC} btrbk config not found: $BTRBK_CONFIG" >&2
    exit 1
fi

# Source AWS connection details if available
AWS_ENV_FILE="$(dirname "$0")/../aws_connection.env"
if [[ -f "$AWS_ENV_FILE" ]]; then
    echo -e "${BLUE}INFO:${NC} Loading AWS connection details from $AWS_ENV_FILE" >&2
    source "$AWS_ENV_FILE"
else
    echo -e "${YELLOW}WARNING:${NC} AWS connection file not found: $AWS_ENV_FILE" >&2
    echo "Remote backups may not work without AWS connection details" >&2
fi

# Preserve current SSH_AUTH_SOCK for sudo
echo -e "${BLUE}INFO:${NC} Using SSH agent at: $SSH_AUTH_SOCK" >&2

# Method 1: Try using sudo -E with explicit SSH_AUTH_SOCK preservation
echo -e "${BLUE}INFO:${NC} Running btrbk with sudo (preserving SSH agent)..." >&2

# Run btrbk with sudo, explicitly preserving SSH_AUTH_SOCK
# We use env to ensure the variable is passed through
sudo env "SSH_AUTH_SOCK=$SSH_AUTH_SOCK" "PATH=$PATH" \
    btrbk -c "$BTRBK_CONFIG" "$@"

# Note: If the above doesn't work due to sudo restrictions, we could try:
# 1. Temporarily changing SSH_AUTH_SOCK permissions (risky)
# 2. Using ssh-add to load keys into a new agent
# 3. Running btrbk without sudo for local operations only