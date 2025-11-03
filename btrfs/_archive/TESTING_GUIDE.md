# Testing Guide for Btrfs Backup System

This guide will help you test the AWS infrastructure deployment using 1Password SSH agent.

## Prerequisites

Before testing, make sure you have:
- ✅ AWS account with credentials configured (`aws configure`)
- ✅ OpenTofu or Terraform installed
- ✅ 1Password with SSH agent enabled
- ✅ SSH key generated in 1Password for btrfs-sync

## Setup 1Password SSH Agent

### 1. Enable 1Password SSH Agent

1. Open 1Password Settings → Developer
2. Enable "Use the SSH agent"
3. Enable "Integrate with 1Password CLI" (optional, but recommended)

### 2. Create SSH Key in 1Password

1. In 1Password, create a new item of type "SSH Key"
2. Give it a name: `btrfs-sync`
3. Click "Generate a New Key" → Choose ED25519
4. Save the item

### 3. Get Your Public Key

From 1Password app:
- Open the `btrfs-sync` item
- Copy the public key (starts with `ssh-ed25519`)

Or via CLI:
```bash
op item get "btrfs-sync" --fields "public key"
```

---

## Deployment Test

**All commands should be run from the repository root (`/code`).**

### 1. Create Configuration File

```bash
cp btrfs/terraform.tfvars.example btrfs/terraform.tfvars
```

Edit `btrfs/terraform.tfvars`:
1. Set `aws_region` to your preferred region (or keep default: `us-west-1`)
2. Replace the `ssh_public_key` value with your public key from 1Password
   - Paste the entire line starting with `ssh-ed25519`

### 2. Run Prerequisites Check

```bash
./btrfs/scripts/check-prerequisites.sh
```

**Expected output:**
- ✓ tofu or terraform found
- ✓ aws CLI found
- ✓ SSH client found
- ✓ AWS credentials configured
- ⚠ btrfs-progs warning is OK (not needed for AWS deployment)

**If any required items fail**, install them before proceeding.

### 3. Deploy Infrastructure

```bash
./btrfs/scripts/setup-aws.sh
```

**What this does:**
1. Checks prerequisites
2. Validates your terraform.tfvars
3. Initializes Terraform/OpenTofu
4. Shows you the deployment plan
5. **Prompts for confirmation** - Type `yes` to deploy
6. Creates AWS resources (~2-3 minutes)
7. Waits for instance to be ready (~5 minutes for user_data script)
8. Runs smoke tests using 1Password SSH agent
9. Generates `btrfs/aws_connection.env` with connection details

**Expected duration:** 7-10 minutes total

### 4. Verify Deployment

After setup completes, you should see:
```
╔════════════════════════════════════════════════════════════╗
║   Setup Complete!                                          ║
╚════════════════════════════════════════════════════════════╝

SUCCESS: AWS infrastructure is ready for backups

Connection details saved to: /code/btrfs/aws_connection.env
```

### 5. Test SSH Connection

```bash
ssh btrbk@<IP_ADDRESS>
```

**Expected:**
- Connection succeeds
- See: `Access denied: Command not permitted.`
- This is CORRECT! SSH restrictions are working
- 1Password prompts for authentication (Touch ID/etc)

### 6. Test Allowed Commands

```bash
ssh btrbk@<IP_ADDRESS> "btrfs --version"
```

**Expected:** `btrfs-progs v5.16.2`

### 7. Run Full Diagnostics

```bash
./btrfs/scripts/troubleshoot.sh check-all
```

**Expected:** All checks pass (green ✓)

---

## Common Issues

### Issue: "terraform.tfvars contains example placeholder values"

**Solution:** Edit `btrfs/terraform.tfvars` and replace with your actual 1Password public key

### Issue: 1Password not prompting

**Solutions:**
1. Verify SSH agent enabled (1Password Settings → Developer)
2. Test it works: `ssh-add -L` (should list your keys)
3. Check key exists: `op item list --categories "SSH Key"`

### Issue: "SSH connection: FAIL"

**Debug:**
```bash
# Check instance is running
cd btrfs && aws ec2 describe-instances --instance-ids $(tofu output -raw instance_id)

# Test 1Password SSH agent
ssh-add -L

# Verbose SSH connection
ssh -v btrbk@$(cd btrfs && tofu output -raw instance_public_ip)
```

---

## Cleaning Up

```bash
cd btrfs && tofu destroy
```

**Cost:** ~$11-12/month while running

---

## Key Benefits of 1Password SSH

- ✅ No SSH key files on disk
- ✅ Biometric authentication
- ✅ Keys available on all devices
- ✅ Secure encrypted storage
- ✅ Easy rotation
