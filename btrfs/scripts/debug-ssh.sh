#!/usr/bin/env bash
# Debug SSH authentication issues with 1Password
set -euo pipefail

echo "=== 1Password SSH Agent Debug ==="
echo ""

echo "1. Checking SSH_AUTH_SOCK environment variable..."
if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
    echo "   ✓ SSH_AUTH_SOCK is set to: $SSH_AUTH_SOCK"
    if [[ -S "$SSH_AUTH_SOCK" ]]; then
        echo "   ✓ Socket exists and is valid"
    else
        echo "   ✗ Socket does not exist or is not a socket!"
        exit 1
    fi
else
    echo "   ✗ SSH_AUTH_SOCK is not set"
    echo "   Set it with: export SSH_AUTH_SOCK=~/.1password/agent.sock"
    exit 1
fi
echo ""

echo "2. Checking what keys the SSH agent has..."
if ssh-add -L &>/dev/null; then
    echo "   Keys available from agent:"
    ssh-add -L | while read -r key; do
        # Extract key type and fingerprint
        type=$(echo "$key" | awk '{print $1}')
        fingerprint=$(echo "$key" | ssh-keygen -lf - 2>/dev/null | awk '{print $2}')
        echo "   - $type $fingerprint"
    done
else
    echo "   ✗ No keys available from SSH agent"
    echo "   Make sure you have keys in 1Password"
    exit 1
fi
echo ""

echo "3. Checking terraform.tfvars public key..."
if [[ -f btrfs/terraform.tfvars ]]; then
    tfvars_key=$(grep '^ssh_public_key' btrfs/terraform.tfvars | cut -d'"' -f2)
    if [[ -n "$tfvars_key" ]]; then
        echo "   terraform.tfvars has key:"
        tfvars_fingerprint=$(echo "$tfvars_key" | ssh-keygen -lf - 2>/dev/null | awk '{print $2}')
        echo "   - $tfvars_fingerprint"
    else
        echo "   ✗ Could not extract key from terraform.tfvars"
        exit 1
    fi
else
    echo "   ✗ btrfs/terraform.tfvars not found"
    exit 1
fi
echo ""

echo "4. Comparing fingerprints..."
agent_fingerprints=$(ssh-add -L | ssh-keygen -lf - 2>/dev/null | awk '{print $2}')
match_found=false
for fp in $agent_fingerprints; do
    if [[ "$fp" == "$tfvars_fingerprint" ]]; then
        echo "   ✓ MATCH FOUND! Agent has the key from terraform.tfvars"
        match_found=true
        break
    fi
done

if [[ "$match_found" == "false" ]]; then
    echo "   ✗ NO MATCH! The keys don't match!"
    echo ""
    echo "   Keys in agent:"
    ssh-add -L | ssh-keygen -lf - 2>/dev/null
    echo ""
    echo "   Key in terraform.tfvars:"
    echo "$tfvars_key" | ssh-keygen -lf - 2>/dev/null
    echo ""
    echo "   SOLUTION: Update terraform.tfvars with one of the keys from your agent:"
    echo "   ssh-add -L"
    exit 1
fi
echo ""

echo "5. Testing SSH connection..."
if [[ -f btrfs/terraform.tfstate ]]; then
    instance_ip=$(cd btrfs && tofu output -raw instance_public_ip 2>/dev/null || terraform output -raw instance_public_ip 2>/dev/null || echo "")
    if [[ -n "$instance_ip" ]]; then
        echo "   Testing connection to: btrbk@$instance_ip"
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "btrbk@$instance_ip" "echo 'SSH works!'" 2>/dev/null; then
            echo "   ✓ SSH connection successful!"
        else
            echo "   ✗ SSH connection failed"
            echo ""
            echo "   Trying verbose connection to see details..."
            ssh -v -o ConnectTimeout=5 -o StrictHostKeyChecking=no "btrbk@$instance_ip" "echo test" 2>&1 | grep -E "Offering|Authentications|key_load_public|debug1: send_pubkey_test"
        fi
    else
        echo "   ⚠ Could not get instance IP (infrastructure may not be deployed)"
    fi
else
    echo "   ⚠ No terraform.tfstate found (infrastructure not deployed)"
fi
echo ""

echo "=== Debug Complete ==="
