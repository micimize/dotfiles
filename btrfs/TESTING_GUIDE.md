# Testing Guide for Btrfs Backup System

This guide will help you test the AWS infrastructure deployment.

## Prerequisites

Before testing, make sure you have:
- ✅ AWS account with credentials configured (`aws configure`)
- ✅ OpenTofu or Terraform installed
- ✅ SSH client
- ✅ An SSH keypair for the backup system

## Quick Start Test

### 1. Generate SSH Key (if you don't have one)

```bash
ssh-keygen -t ed25519 -f ~/.ssh/btrbk_backup -C "btrbk-backup" -N ""
```

This creates:
- Private key: `~/.ssh/btrbk_backup`
- Public key: `~/.ssh/btrbk_backup.pub`

### 2. Create Configuration File

```bash
cd /code/btrfs
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and:
1. Set `aws_region` to your preferred region (or keep default: `us-west-1`)
2. Replace the `ssh_public_key` value with your actual public key:
   ```bash
   cat ~/.ssh/btrbk_backup.pub
   ```
   Copy the entire output and paste it in `terraform.tfvars`

### 3. Run Prerequisites Check

```bash
cd /code/btrfs
./scripts/check-prerequisites.sh
```

**Expected output:**
- ✓ tofu or terraform found
- ✓ aws CLI found
- ✓ SSH client found
- ✓ AWS credentials configured
- ⚠ btrfs-progs warning is OK (not needed for AWS deployment)

**If any required items fail**, install them before proceeding.

### 4. Deploy Infrastructure

```bash
cd /code/btrfs
./scripts/setup-aws.sh
```

**What this does:**
1. Checks prerequisites
2. Validates your terraform.tfvars
3. Initializes Terraform/OpenTofu
4. Shows you the deployment plan
5. **Prompts for confirmation** - Type `yes` to deploy
6. Creates AWS resources (~2-3 minutes)
7. Waits for instance to be ready (~5 minutes for user_data script)
8. Runs smoke tests
9. Generates `aws_connection.env` with connection details

**Expected duration:** 7-10 minutes total

### 5. Verify Deployment

After setup completes, you should see:
```
╔════════════════════════════════════════════════════════════╗
║   Setup Complete!                                          ║
╚════════════════════════════════════════════════════════════╝

SUCCESS: AWS infrastructure is ready for backups

Connection details saved to: /code/btrfs/aws_connection.env
```

### 6. Test SSH Connection

```bash
ssh -i ~/.ssh/btrbk_backup btrbk@$(cd /code/btrfs && tofu output -raw instance_public_ip)
```

**Expected:**
- You should connect but see: `Access denied: Command not permitted.`
- This is CORRECT! It means SSH restrictions are working.

### 7. Test Allowed Commands

```bash
ssh -i ~/.ssh/btrbk_backup btrbk@$(cd /code/btrfs && tofu output -raw instance_public_ip) "btrfs --version"
```

**Expected output:**
```
btrfs-progs v5.16.2
```

### 8. Run Troubleshooting Checks

```bash
cd /code/btrfs
./scripts/troubleshoot.sh check-all
```

**Expected:** All checks should pass (green checkmarks)

---

## What to Report Back

Please share:

1. **Prerequisites check output:**
   ```bash
   ./scripts/check-prerequisites.sh
   ```

2. **Setup output (full log):**
   ```bash
   ./scripts/setup-aws.sh 2>&1 | tee setup.log
   ```
   Then share `setup.log`

3. **Smoke test results:**
   - Did all 6 smoke tests pass?
   - If any failed, which ones?

4. **SSH test results:**
   - Can you connect with SSH?
   - Are commands properly restricted?
   - Can you run `btrfs --version`?

5. **Troubleshooting output:**
   ```bash
   ./scripts/troubleshoot.sh check-all
   ```

6. **Any errors or unexpected behavior**

---

## Common Issues

### Issue: "terraform.tfvars contains example placeholder values"

**Solution:** Edit `terraform.tfvars` and replace the SSH public key with your actual key from `~/.ssh/btrbk_backup.pub`

### Issue: "SSH connection: FAIL" in smoke tests

**Possible causes:**
1. Instance is still initializing (wait 2-3 more minutes)
2. Security group not allowing SSH from your IP
3. SSH key mismatch

**Debug:**
```bash
# Check if instance is running
aws ec2 describe-instances --instance-ids $(cd /code/btrfs && tofu output -raw instance_id)

# Try manual SSH connection
ssh -v -i ~/.ssh/btrbk_backup btrbk@$(cd /code/btrfs && tofu output -raw instance_public_ip)
```

### Issue: "Volume not mounted" in smoke tests

**Solution:** Check cloud-init logs:
```bash
./scripts/troubleshoot.sh check-logs
```

Look for errors in the user_data script execution.

### Issue: Smoke tests fail but I want to continue

The setup script will still generate `aws_connection.env` even if smoke tests fail. You can proceed with manual troubleshooting using:
```bash
./scripts/troubleshoot.sh check-all
```

---

## Cleaning Up

When you're done testing and want to destroy the infrastructure:

```bash
cd /code/btrfs
tofu destroy
# or
terraform destroy
```

Type `yes` when prompted.

**Note:** This will permanently delete the EC2 instance and EBS volume.

---

## Cost Information

While the infrastructure is running:
- **EC2 t3a.nano:** ~$0.0047/hour = ~$3.43/month
- **EBS 100GB gp3:** ~$8/month
- **Total:** ~$11-12/month

To minimize costs during testing:
1. Test everything you need
2. Run `tofu destroy` when done
3. Can always redeploy later with `./scripts/setup-aws.sh`

---

## Files Created

After successful deployment, you should have:

```
btrfs/
├── .gitignore                    # Ignores sensitive files
├── terraform.tfvars              # Your config (NOT in git)
├── terraform.tfvars.example      # Template
├── aws_connection.env            # Generated connection details (NOT in git)
├── .terraform/                   # Terraform state (NOT in git)
├── terraform.tfstate             # Terraform state (NOT in git)
├── btrbk_aws.tf                  # Infrastructure definition
├── scripts/
│   ├── check-prerequisites.sh    # Prerequisites checker
│   ├── setup-aws.sh              # Main setup script
│   └── troubleshoot.sh           # Diagnostic tool
└── TESTING_GUIDE.md              # This file
```

---

## Next Steps After Successful Test

Once everything works:
1. Report results back
2. We can add more features:
   - End-to-end backup test script
   - Detailed troubleshooting documentation
   - Local btrbk configuration (Phase 2)
   - More robust error handling

---

## Questions?

If you encounter anything not covered here, please report:
- What command you ran
- Full error output
- Output of `./scripts/troubleshoot.sh check-all`
