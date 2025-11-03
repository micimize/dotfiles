#!/usr/bin/env bash
#
# setup-ssh-for-btrbk.sh - Configure SSH for btrbk to work with 1Password agent
#
# This script helps set up SSH configuration so btrbk can use your 1Password
# SSH agent when run with sudo. It creates an SSH config that btrbk will use.
#
# Usage:
#   ./setup-ssh-for-btrbk.sh
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== SSH Configuration for btrbk ===${NC}"
echo ""

# Source AWS connection details
AWS_ENV_FILE="$(dirname "$0")/../aws_connection.env"
if [[ -f "$AWS_ENV_FILE" ]]; then
    echo -e "${BLUE}INFO:${NC} Loading AWS connection details..." >&2
    source "$AWS_ENV_FILE"
    echo -e "${GREEN}✓${NC} AWS Host: $BTRBK_AWS_HOST"
else
    echo -e "${RED}ERROR:${NC} AWS connection file not found: $AWS_ENV_FILE" >&2
    echo "Run '../scripts/setup-aws.sh' first to deploy infrastructure" >&2
    exit 1
fi

# Check current SSH_AUTH_SOCK
if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
    echo -e "${RED}ERROR:${NC} SSH_AUTH_SOCK is not set" >&2
    echo "Your SSH agent (e.g., 1Password) is not running" >&2
    exit 1
fi

echo -e "${GREEN}✓${NC} SSH Agent: $SSH_AUTH_SOCK"
echo ""

# Test SSH connection as regular user
echo -e "${BLUE}Testing SSH connection as your user...${NC}"
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
       "ubuntu@$BTRBK_AWS_HOST" "echo 'SSH connection successful'" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} SSH connection works as $USER"
else
    echo -e "${RED}✗${NC} SSH connection failed as $USER"
    echo ""
    echo "Please ensure:"
    echo "  1. Your SSH key is loaded in 1Password"
    echo "  2. The AWS instance is running"
    echo "  3. You can manually connect: ssh ubuntu@$BTRBK_AWS_HOST"
    exit 1
fi

echo ""
echo -e "${BLUE}=== Solution Options ===${NC}"
echo ""
echo "btrbk needs to run as root (for btrfs operations) but also needs SSH access."
echo "Here are three solutions:"
echo ""

echo -e "${YELLOW}Option 1: Socket Permission Workaround${NC} (Quick fix, less secure)"
echo "  Allow root to access your SSH agent socket temporarily:"
echo ""
echo "  # Set permissions (before running btrbk):"
echo "  sudo setfacl -m u:root:rw $SSH_AUTH_SOCK"
echo ""
echo "  # Run btrbk:"
echo "  sudo env SSH_AUTH_SOCK=$SSH_AUTH_SOCK btrbk -c btrfs/local/btrbk.conf run"
echo ""
echo "  # Remove permissions (after running btrbk):"
echo "  sudo setfacl -x u:root $SSH_AUTH_SOCK"
echo ""

echo -e "${YELLOW}Option 2: SSH Control Socket${NC} (Recommended)"
echo "  Use SSH connection sharing via ControlMaster:"
echo ""
echo "  # Create SSH config for btrbk:"
cat << 'EOF'
  cat >> ~/.ssh/config << 'CONFIG'
Host btrbk-backup
    HostName $BTRBK_AWS_HOST
    User ubuntu
    ControlMaster auto
    ControlPath ~/.ssh/btrbk-%r@%h:%p
    ControlPersist 10m
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
CONFIG
EOF
echo ""
echo "  # Establish master connection (as your user):"
echo "  ssh -fN btrbk-backup"
echo ""
echo "  # Update btrbk.conf target line to use host alias:"
echo "  target ssh://btrbk-backup/backup_volume/backups/home/mjr"
echo ""
echo "  # Run btrbk (control socket is accessible):"
echo "  sudo btrbk -c btrfs/local/btrbk.conf run"
echo ""

echo -e "${YELLOW}Option 3: SSH Key File${NC} (Most reliable, less convenient)"
echo "  Export your SSH key from 1Password to a file:"
echo ""
echo "  # Export key from 1Password to ~/.ssh/btrbk_key"
echo "  # Set permissions: chmod 600 ~/.ssh/btrbk_key"
echo ""
echo "  # Update btrbk.conf:"
echo "  ssh_identity /home/$USER/.ssh/btrbk_key"
echo ""
echo "  # Run btrbk:"
echo "  sudo btrbk -c btrfs/local/btrbk.conf run"
echo ""

echo -e "${BLUE}=== Quick Test Commands ===${NC}"
echo ""
echo "After choosing an option above, test with:"
echo ""
echo "  # Dry run (no changes):"
echo "  sudo [...solution...] btrbk -c btrfs/local/btrbk.conf -v -n run"
echo ""
echo "  # Create local snapshots only:"
echo "  sudo btrbk -c btrfs/local/btrbk.conf -v snapshot"
echo ""

# Create a helper script for Option 1
HELPER_SCRIPT="$(dirname "$0")/btrbk-with-ssh.sh"
cat > "$HELPER_SCRIPT" << 'EOF'
#!/usr/bin/env bash
# btrbk-with-ssh.sh - Run btrbk with SSH agent access (Option 1 automated)

set -euo pipefail

if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
    echo "ERROR: SSH_AUTH_SOCK not set" >&2
    exit 1
fi

echo "Granting root access to SSH agent socket..."
sudo setfacl -m u:root:rw "$SSH_AUTH_SOCK" || exit 1

echo "Running btrbk..."
sudo env "SSH_AUTH_SOCK=$SSH_AUTH_SOCK" "PATH=$PATH" \
    btrbk -c "$(dirname "$0")/btrbk.conf" "$@"
EXIT_CODE=$?

echo "Revoking root access to SSH agent socket..."
sudo setfacl -x u:root "$SSH_AUTH_SOCK" 2>/dev/null || true

exit $EXIT_CODE
EOF

chmod +x "$HELPER_SCRIPT"

echo ""
echo -e "${GREEN}=== Helper Script Created ===${NC}"
echo ""
echo "For Option 1 (quick fix), use the helper script:"
echo "  $HELPER_SCRIPT -v -n run"
echo ""
echo "This script automatically handles socket permissions."