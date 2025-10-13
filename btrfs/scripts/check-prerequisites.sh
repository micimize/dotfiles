#!/usr/bin/env bash
# Prerequisites checker for btrfs backup system setup
# This script verifies all required tools are installed and properly configured

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0

check_command() {
    local cmd=$1
    local package=$2
    local min_version=${3:-}

    if command -v "$cmd" &> /dev/null; then
        local version
        version=$("$cmd" --version 2>&1 | head -n1 || echo "unknown")
        echo -e "${GREEN}✓${NC} $cmd found: $version"
        return 0
    else
        echo -e "${RED}✗${NC} $cmd not found. Install: $package"
        ((ERRORS++))
        return 1
    fi
}

check_aws_credentials() {
    if [[ -f ~/.aws/credentials ]] || [[ -n "${AWS_ACCESS_KEY_ID:-}" ]]; then
        echo -e "${GREEN}✓${NC} AWS credentials configured"
        return 0
    else
        echo -e "${YELLOW}⚠${NC} AWS credentials not found. Configure with: aws configure"
        echo "  Or set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables"
        ((ERRORS++))
        return 1
    fi
}

check_ssh_client() {
    if command -v ssh &> /dev/null; then
        local version
        version=$(ssh -V 2>&1)
        echo -e "${GREEN}✓${NC} SSH client found: $version"
        return 0
    else
        echo -e "${RED}✗${NC} SSH client not found. Install: openssh-client"
        ((ERRORS++))
        return 1
    fi
}

check_btrfs_local() {
    if command -v btrfs &> /dev/null; then
        local version
        version=$(btrfs --version)
        echo -e "${GREEN}✓${NC} btrfs-progs found: $version"
    else
        echo -e "${YELLOW}⚠${NC} btrfs-progs not found on local machine"
        echo "  This is required for local backup configuration (future task)"
        echo "  Install: apt install btrfs-progs (Debian/Ubuntu) or equivalent"
    fi
}

echo "Checking prerequisites for btrfs backup system setup..."
echo ""

# Required for AWS setup - check for either tofu or terraform
if ! check_command "tofu" "opentofu (see https://opentofu.org/docs/intro/install/)"; then
    # If tofu not found, check for terraform
    if ! check_command "terraform" "terraform (see https://www.terraform.io/downloads)"; then
        # Both failed, error already incremented
        :
    else
        # terraform found, decrement the error from tofu check
        ((ERRORS--))
    fi
fi
check_command "aws" "awscli (brew install awscli)"
check_ssh_client
check_aws_credentials

echo ""

# Optional but recommended for future local setup
check_btrfs_local

echo ""

if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}All required prerequisites met!${NC}"
    exit 0
else
    echo -e "${RED}$ERRORS prerequisite(s) missing. Please install required tools.${NC}"
    exit 1
fi
