# Btrfs Backup System Implementation Plan

## Context & Background

### What We're Building
A production-ready AWS-based btrfs backup system with bidirectional sync capability. This plan covers Phase 1: AWS infrastructure setup and tooling.

### Problem Domain Primer
- **btrfs**: A modern Linux filesystem with built-in snapshot capabilities
- **btrbk**: A backup tool that leverages btrfs snapshots for incremental backups
- **Snapshots**: Point-in-time copies of a filesystem that share unchanged data (space-efficient)
- **Incremental backups**: Only transfer changes since the last backup, not the entire filesystem
- **Bidirectional sync**: Both local→AWS and AWS→local snapshot transfers

### Technology Stack
- **OpenTofu**: Open-source Terraform fork for infrastructure-as-code
- **AWS EC2**: Virtual machine to run the backup target
- **AWS EBS**: Block storage (like a virtual hard drive) that can be encrypted
- **btrfs-progs**: Userspace tools for managing btrfs filesystems
- **btrbk**: Backup orchestration tool built on btrfs send/receive
- **SSH**: Secure remote access protocol

### Current State
- Terraform config exists but is untested and has bugs
- No setup automation or documentation
- No testing or troubleshooting tools

---

## Implementation Phases

### Phase 1: Fix and Test Infrastructure Code (Tasks 1-5)
### Phase 2: Create Setup Script (Tasks 6-10)
### Phase 3: Create Troubleshooting Tools (Tasks 11-13)
### Phase 4: Create Test Script (Tasks 14-15)
### Phase 5: Documentation (Tasks 16-18)

---

## Task 1: Fix Terraform Configuration Bugs

**Goal**: Make the existing `btrbk_aws.tf` valid and deployable

**Files to modify**:
- `btrfs/btrbk_aws.tf`

**Issues to fix**:

1. **Line 164: Invalid availability_zone reference**
   - Problem: Security groups don't have an `availability_zone` attribute
   - Fix: Remove the explicit AZ assignment from the EC2 instance, or use a data source to get default AZ

   ```hcl
   # REMOVE this line from aws_instance.btrbk_backup_target:
   availability_zone = aws_security_group.btrbk_sg.availability_zone

   # The instance will use the default AZ for the region
   ```

2. **Line 130: Variable interpolation in user_data**
   - Problem: Using `${var.ssh_public_key}` inside a single-quoted heredoc won't work
   - Fix: The heredoc with `EOF` (not `'EOF'`) allows interpolation, but we need to escape the inner heredoc delimiter

   ```hcl
   # Change line 130 from:
   echo 'command="btrbk-ssh" ${var.ssh_public_key}' >> /home/btrbk/.ssh/authorized_keys

   # To:
   echo 'command="/usr/local/bin/btrbk-ssh" '${var.ssh_public_key} >> /home/btrbk/.ssh/authorized_keys
   ```

3. **User_data script: btrbk user home directory inconsistency**
   - Problem: User created with `-r` (system user, no home) but script tries to use `/home/btrbk`
   - Fix: Create a proper dedicated user with a home directory

   ```bash
   # Change from:
   useradd -r btrbk -s /bin/false

   # To:
   useradd -m -s /bin/bash btrbk
   ```

4. **User_data script: Missing btrbk installation**
   - Problem: Only installs btrfs-progs, but we need btrbk for bidirectional sync
   - Fix: Add btrbk installation (it's in Ubuntu repositories)

   ```bash
   # Add after btrfs-progs installation:
   apt install -y btrbk
   ```

5. **btrbk-ssh script: Insufficient command whitelist**
   - Problem: Only allows `btrfs send` and `btrbk receive`, but bidirectional sync needs more
   - Fix: Expand the whitelist for btrbk operations

   ```bash
   # Replace the btrbk-ssh case statement with:
   case "$SSH_ORIGINAL_COMMAND" in
     btrfs\ send*|btrfs\ receive*|btrfs\ subvolume\ *)
       eval "$SSH_ORIGINAL_COMMAND"
       ;;
     btrbk\ *)
       eval "$SSH_ORIGINAL_COMMAND"
       ;;
     *)
       echo "Access denied: Command not permitted." >&2
       exit 1
       ;;
   esac
   ```

6. **Add variable for EBS volume size** (optional but good practice)
   - Makes it easier to customize without editing the .tf file directly

   ```hcl
   # Add to variables section:
   variable "ebs_volume_size" {
     description = "Size of the backup EBS volume in GiB"
     type        = number
     default     = 100
   }

   # Update aws_ebs_volume.btrbk_volume:
   size = var.ebs_volume_size
   ```

**Testing**:
```bash
# Validate syntax
tofu validate

# Check formatting
tofu fmt -check

# Generate plan (requires variables, will do in next task)
tofu plan
```

**Commit message**:
```
fix: correct terraform configuration bugs

- Remove invalid availability_zone reference from EC2 instance
- Fix SSH key interpolation in user_data
- Create btrbk user with proper home directory
- Install btrbk package for bidirectional sync
- Expand btrbk-ssh command whitelist
- Add variable for EBS volume size

Co-authored-by: Sculptor <sculptor@imbue.com>
```

---

## Task 2: Create Terraform Variables Template

**Goal**: Provide a template for users to configure their deployment

**Files to create**:
- `btrfs/terraform.tfvars.example`

**Content**:
```hcl
# AWS Region
# Recommended: Choose a region close to your primary location for lower latency
aws_region = "us-west-1"

# SSH Public Key
# This key will be used for authentication to the backup server
# Generate with: ssh-keygen -t ed25519 -f ~/.ssh/btrbk_backup -C "btrbk-backup"
# Then copy the contents of ~/.ssh/btrbk_backup.pub here
ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyDataHere btrbk-backup"

# AWS Key Pair Name (optional - defaults to "btrbk-backup-key")
# key_pair_name = "btrbk-backup-key"

# EBS Volume Size in GiB (optional - defaults to 100)
# Estimate: Calculate total size of data you want to back up, multiply by 2-3x
# for snapshots and growth
# ebs_volume_size = 100
```

**Files to create**:
- `btrfs/.gitignore` (if it doesn't exist) or append to root `.gitignore`

**Content**:
```gitignore
# Terraform/OpenTofu files
*.tfstate
*.tfstate.*
.terraform/
.terraform.lock.hcl
terraform.tfvars
crash.log

# Environment files
.env
*.env

# SSH keys (just in case)
*.pem
id_*
!*.pub

# Logs
*.log
```

**Testing**:
```bash
# Verify git ignores the right files
cp btrfs/terraform.tfvars.example btrfs/terraform.tfvars
git status  # Should not show terraform.tfvars
```

**Commit message**:
```
feat: add terraform variables template

- Create terraform.tfvars.example with documented variables
- Add .gitignore for sensitive files (state, keys, vars)

Co-authored-by: Sculptor <sculptor@imbue.com>
```

---

## Task 3: Create Prerequisites Check Script

**Goal**: Verify all required tools are installed before attempting setup

**Files to create**:
- `btrfs/scripts/check-prerequisites.sh`

**Content**:
```bash
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

# Required for AWS setup
check_command "tofu" "opentofu (see https://opentofu.org/docs/intro/install/)"
check_command "aws" "awscli (pip install awscli or apt install awscli)"
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
```

**Files to modify**:
- Make it executable

**Commands**:
```bash
chmod +x btrfs/scripts/check-prerequisites.sh
```

**Testing**:
```bash
# Test with tools installed
./btrfs/scripts/check-prerequisites.sh

# Test failure case (temporarily rename a command)
sudo mv /usr/bin/tofu /usr/bin/tofu.bak 2>/dev/null || true
./btrfs/scripts/check-prerequisites.sh  # Should fail
sudo mv /usr/bin/tofu.bak /usr/bin/tofu 2>/dev/null || true
```

**Commit message**:
```
feat: add prerequisites check script

- Check for opentofu, aws cli, ssh, btrfs-progs
- Verify AWS credentials are configured
- Color-coded output for easy scanning
- Exit with error if any required tools missing

Co-authored-by: Sculptor <sculptor@imbue.com>
```

---

## Task 4: Test Terraform Configuration Manually

**Goal**: Ensure the fixed terraform config actually works before building automation

**Prerequisites**:
- AWS account with credentials configured
- Completed Tasks 1-3

**Steps**:

1. **Create test variables file**:
   ```bash
   cd btrfs
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Generate SSH key for testing**:
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/btrbk_backup_test -C "btrbk-backup-test" -N ""
   ```

3. **Edit terraform.tfvars**:
   - Set your preferred AWS region
   - Copy contents of `~/.ssh/btrbk_backup_test.pub` into `ssh_public_key`

4. **Initialize Terraform**:
   ```bash
   tofu init
   ```

5. **Validate configuration**:
   ```bash
   tofu validate
   ```

6. **Preview changes**:
   ```bash
   tofu plan
   ```

   Review the plan:
   - Should create: security group, key pair, EC2 instance, EBS volume, volume attachment
   - Should be 5 resources total
   - Check that all values look correct

7. **Apply configuration**:
   ```bash
   tofu apply
   ```

   Type `yes` when prompted. This will:
   - Create AWS resources (~2-3 minutes)
   - Run user_data script on first boot
   - Output the instance public IP

8. **Test SSH access** (wait 3-5 minutes for user_data to complete):
   ```bash
   INSTANCE_IP=$(tofu output -raw instance_public_ip)
   ssh -i ~/.ssh/btrbk_backup_test btrbk@$INSTANCE_IP
   ```

   If connection is refused, wait longer. If "permission denied", check key permissions:
   ```bash
   chmod 600 ~/.ssh/btrbk_backup_test
   ```

9. **Verify setup on remote instance**:
   ```bash
   # Check if volume is mounted
   ssh -i ~/.ssh/btrbk_backup_test btrbk@$INSTANCE_IP "df -h | grep backup"

   # Check btrfs filesystem
   ssh -i ~/.ssh/btrbk_backup_test btrbk@$INSTANCE_IP "sudo btrfs filesystem show /backup_volume"

   # Check btrbk is installed
   ssh -i ~/.ssh/btrbk_backup_test btrbk@$INSTANCE_IP "btrbk --version"
   ```

10. **Test restricted SSH commands**:
    ```bash
    # Should work
    ssh -i ~/.ssh/btrbk_backup_test btrbk@$INSTANCE_IP "btrfs --version"

    # Should be denied
    ssh -i ~/.ssh/btrbk_backup_test btrbk@$INSTANCE_IP "ls /"
    ```

11. **Destroy test infrastructure** (optional - costs ~$0.01/day):
    ```bash
    tofu destroy
    ```

    Type `yes` when prompted.

**Document findings**:
Create a file `btrfs/TESTING_NOTES.md`:
```markdown
# Manual Testing Results

## Date: [DATE]
## Tester: [YOUR NAME]

### Test Environment
- AWS Region: [REGION]
- OpenTofu Version: [VERSION]
- Instance Type: t3a.nano
- Volume Size: 100GB

### Test Results

#### Terraform Operations
- [ ] `tofu init` - SUCCESS/FAILURE
- [ ] `tofu validate` - SUCCESS/FAILURE
- [ ] `tofu plan` - SUCCESS/FAILURE
- [ ] `tofu apply` - SUCCESS/FAILURE

#### Instance Provisioning
- [ ] Instance launched successfully
- [ ] EBS volume attached
- [ ] user_data script completed (check /var/log/cloud-init-output.log)

#### SSH Access
- [ ] Can SSH to btrbk user
- [ ] Restricted commands work (btrfs, btrbk)
- [ ] Unrestricted commands blocked (ls, cat, etc.)

#### Filesystem Setup
- [ ] /backup_volume mounted
- [ ] Btrfs filesystem created
- [ ] Sufficient space available

#### Issues Encountered
[Document any problems and how they were resolved]

#### Manual Fixes Required
[List any issues that need to be fixed in the terraform config]
```

**No commit for this task** - this is testing only. If bugs are found, fix them in the terraform config and commit those fixes.

---

## Task 5: Add Terraform Output for Connection Details

**Goal**: Make it easy to extract connection info for local configuration

**Files to modify**:
- `btrfs/btrbk_aws.tf`

**Changes**:
Add these outputs at the end of the file (after line 197):

```hcl
# Output the SSH connection string for easy access
output "ssh_connection_string" {
  description = "SSH connection string for the btrbk user"
  value       = "btrbk@${aws_instance.btrbk_backup_target.public_ip}"
}

# Output the backup target path for btrbk configuration
output "backup_target_path" {
  description = "Path on remote server for backups"
  value       = "/backup_volume/backups"
}

# Output the full btrbk target string
output "btrbk_target" {
  description = "Full target string for btrbk configuration"
  value       = "ssh://btrbk@${aws_instance.btrbk_backup_target.public_ip}/backup_volume/backups/"
}

# Output instance ID for troubleshooting
output "instance_id" {
  description = "EC2 instance ID for AWS console access"
  value       = aws_instance.btrbk_backup_target.instance_id
}

# Output volume ID for troubleshooting
output "volume_id" {
  description = "EBS volume ID for AWS console access"
  value       = aws_ebs_volume.btrbk_volume.id
}
```

**Testing**:
```bash
cd btrfs

# If you have infrastructure deployed from Task 4:
tofu output
tofu output -raw btrbk_target

# Otherwise just validate
tofu validate
```

**Commit message**:
```
feat: add terraform outputs for connection details

- Add ssh_connection_string for easy SSH access
- Add btrbk_target for local configuration
- Add instance_id and volume_id for troubleshooting
- Add backup_target_path for reference

Co-authored-by: Sculptor <sculptor@imbue.com>
```

---

## Task 6: Create Setup Script (Part 1 - Structure)

**Goal**: Create the main AWS setup script with proper structure and error handling

**Files to create**:
- `btrfs/scripts/setup-aws.sh`

**Content**:
```bash
#!/usr/bin/env bash
# AWS Infrastructure Setup Script for Btrfs Backup System
#
# This script automates the deployment of AWS infrastructure for btrbk backups.
# It wraps OpenTofu commands with proper error handling and generates configuration
# files for local backup setup.
#
# Usage: ./scripts/setup-aws.sh

set -euo pipefail

# Script directory (for finding other scripts)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Log functions
log_info() {
    echo -e "${BLUE}INFO:${NC} $*"
}

log_success() {
    echo -e "${GREEN}SUCCESS:${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}WARNING:${NC} $*"
}

log_error() {
    echo -e "${RED}ERROR:${NC} $*" >&2
}

# Error handler
error_exit() {
    log_error "$1"
    log_error "Setup failed. Review the error above."
    exit 1
}

# Print banner
print_banner() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║   Btrfs Backup System - AWS Infrastructure Setup          ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
}

# Cleanup function
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Setup failed with exit code $exit_code"
    fi
}

trap cleanup EXIT

# Main function (to be implemented in next tasks)
main() {
    print_banner

    log_info "Setup script skeleton created"
    log_info "Functionality to be implemented in subsequent tasks"

    # TODO: Add steps in next tasks:
    # 1. Check prerequisites
    # 2. Validate terraform.tfvars exists
    # 3. Initialize Terraform
    # 4. Plan and apply
    # 5. Generate .env file
    # 6. Display next steps
}

# Run main function
main "$@"
```

**Make executable**:
```bash
chmod +x btrfs/scripts/setup-aws.sh
```

**Testing**:
```bash
./btrfs/scripts/setup-aws.sh
# Should print banner and placeholder message
```

**Commit message**:
```
feat: create setup script skeleton

- Add error handling and logging functions
- Add color-coded output for readability
- Add cleanup trap for error reporting
- Prepare structure for implementation

Co-authored-by: Sculptor <sculptor@imbue.com>
```

---

## Task 7: Create Setup Script (Part 2 - Prerequisites & Validation)

**Goal**: Add prerequisites check and terraform.tfvars validation to setup script

**Files to modify**:
- `btrfs/scripts/setup-aws.sh`

**Changes**:
Replace the `main()` function and add new functions before it:

```bash
# Check prerequisites using separate script
check_prerequisites() {
    log_info "Checking prerequisites..."

    if [[ ! -x "$SCRIPT_DIR/check-prerequisites.sh" ]]; then
        error_exit "Prerequisites script not found or not executable: $SCRIPT_DIR/check-prerequisites.sh"
    fi

    if ! "$SCRIPT_DIR/check-prerequisites.sh"; then
        error_exit "Prerequisites check failed. Install missing tools and try again."
    fi

    log_success "All prerequisites met"
}

# Validate terraform.tfvars exists
validate_tfvars() {
    log_info "Validating Terraform variables..."

    local tfvars_file="$PROJECT_DIR/terraform.tfvars"
    local tfvars_example="$PROJECT_DIR/terraform.tfvars.example"

    if [[ ! -f "$tfvars_file" ]]; then
        log_error "terraform.tfvars not found"
        log_info "Please create it from the example:"
        log_info "  cp $tfvars_example $tfvars_file"
        log_info "  \$EDITOR $tfvars_file"
        error_exit "Missing configuration file"
    fi

    # Check for placeholder values
    if grep -q "AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyDataHere" "$tfvars_file"; then
        log_error "terraform.tfvars contains example placeholder values"
        log_info "Please edit $tfvars_file with your actual SSH public key"
        error_exit "Invalid configuration"
    fi

    # Validate SSH public key format (basic check)
    local ssh_key
    ssh_key=$(grep '^ssh_public_key' "$tfvars_file" | cut -d'"' -f2 || echo "")

    if [[ -z "$ssh_key" ]]; then
        error_exit "ssh_public_key not set in terraform.tfvars"
    fi

    if [[ ! "$ssh_key" =~ ^ssh-(rsa|ed25519|ecdsa) ]]; then
        log_warning "ssh_public_key doesn't look like a valid SSH public key"
        log_warning "Expected format: ssh-ed25519 AAAA... comment"
    fi

    log_success "Terraform variables validated"
}

# Initialize Terraform
init_terraform() {
    log_info "Initializing OpenTofu..."

    cd "$PROJECT_DIR"

    if ! tofu init; then
        error_exit "OpenTofu initialization failed"
    fi

    log_success "OpenTofu initialized"
}

# Main function
main() {
    print_banner

    check_prerequisites
    validate_tfvars
    init_terraform

    log_info "Next steps: Plan and apply (to be implemented)"
}
```

**Testing**:
```bash
# Test without terraform.tfvars (should fail)
cd btrfs
mv terraform.tfvars terraform.tfvars.bak 2>/dev/null || true
./scripts/setup-aws.sh
# Should fail with helpful message

# Test with example file (should fail on placeholder check)
cp terraform.tfvars.example terraform.tfvars
./scripts/setup-aws.sh
# Should fail on placeholder detection

# Test with valid file
# Edit terraform.tfvars with real values
./scripts/setup-aws.sh
# Should pass validation and init terraform

# Restore if you had a backup
mv terraform.tfvars.bak terraform.tfvars 2>/dev/null || true
```

**Commit message**:
```
feat: add validation to setup script

- Check prerequisites before proceeding
- Validate terraform.tfvars exists and is configured
- Detect placeholder values in config
- Initialize OpenTofu with error handling

Co-authored-by: Sculptor <sculptor@imbue.com>
```

---

## Task 8: Create Setup Script (Part 3 - Deploy Infrastructure)

**Goal**: Add terraform plan/apply functionality to setup script

**Files to modify**:
- `btrfs/scripts/setup-aws.sh`

**Changes**:
Add these functions before `main()`:

```bash
# Run terraform plan
plan_infrastructure() {
    log_info "Planning infrastructure changes..."

    cd "$PROJECT_DIR"

    if ! tofu plan -out=tfplan; then
        error_exit "OpenTofu plan failed"
    fi

    log_success "Plan generated successfully"
}

# Apply terraform plan
apply_infrastructure() {
    log_info "Deploying AWS infrastructure..."
    log_warning "This will create resources in your AWS account and incur costs."
    log_info "Estimated monthly cost: ~\$3-5 for t3a.nano instance + 100GB storage"
    echo ""

    read -p "Continue with deployment? (yes/no): " -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Deployment cancelled by user"
        exit 0
    fi

    cd "$PROJECT_DIR"

    log_info "Deploying... (this may take 2-3 minutes)"

    if ! tofu apply tfplan; then
        error_exit "OpenTofu apply failed"
    fi

    # Remove plan file after successful apply
    rm -f tfplan

    log_success "Infrastructure deployed successfully"
}

# Wait for instance to be ready
wait_for_instance() {
    log_info "Waiting for instance to complete initialization..."
    log_info "This includes running user_data script to set up btrfs and btrbk"

    local instance_ip
    instance_ip=$(tofu output -raw instance_public_ip)

    local max_attempts=60
    local attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        if ssh -i ~/.ssh/btrbk_backup_test \
               -o ConnectTimeout=5 \
               -o StrictHostKeyChecking=no \
               -o UserKnownHostsFile=/dev/null \
               -q \
               "btrbk@$instance_ip" "exit" 2>/dev/null; then
            log_success "Instance is ready and SSH is accessible"
            return 0
        fi

        ((attempt++))
        echo -n "."
        sleep 5
    done

    echo ""
    log_warning "Instance did not become ready within expected time"
    log_info "You can check status later with: ./scripts/troubleshoot.sh check-ssh"
}
```

Update `main()`:
```bash
main() {
    print_banner

    check_prerequisites
    validate_tfvars
    init_terraform
    plan_infrastructure
    apply_infrastructure
    wait_for_instance

    log_info "Next step: Generate configuration (to be implemented)"
}
```

**Testing**:
```bash
# Full test requires real AWS deployment
./btrfs/scripts/setup-aws.sh

# Should:
# 1. Check prerequisites
# 2. Validate config
# 3. Init terraform
# 4. Show plan
# 5. Prompt for confirmation
# 6. Deploy (if you confirm)
# 7. Wait for instance

# To test cancellation:
./btrfs/scripts/setup-aws.sh
# Type "no" when prompted
```

**Commit message**:
```
feat: add infrastructure deployment to setup script

- Generate terraform plan with review
- Prompt user for confirmation before applying
- Show cost estimate before deployment
- Wait for instance to be SSH-accessible
- Clean up plan file after successful apply

Co-authored-by: Sculptor <sculptor@imbue.com>
```

---

## Task 9: Create Setup Script (Part 4 - Generate Configuration)

**Goal**: Generate .env file with connection details for local setup

**Files to modify**:
- `btrfs/scripts/setup-aws.sh`

**Changes**:
Add this function before `main()`:

```bash
# Generate .env file for local configuration
generate_config() {
    log_info "Generating configuration for local setup..."

    cd "$PROJECT_DIR"

    local env_file="$PROJECT_DIR/aws_connection.env"
    local instance_ip
    local instance_id
    local volume_id
    local btrbk_target

    # Extract outputs from terraform
    instance_ip=$(tofu output -raw instance_public_ip)
    instance_id=$(tofu output -raw instance_id)
    volume_id=$(tofu output -raw volume_id)
    btrbk_target=$(tofu output -raw btrbk_target)

    # Generate .env file
    cat > "$env_file" << EOF
# AWS Backup Server Connection Details
# Generated by setup-aws.sh on $(date)
#
# Source this file in local setup: source aws_connection.env
# Or use these values to configure btrbk on your local machine

# SSH connection
BTRBK_AWS_HOST=$instance_ip
BTRBK_AWS_USER=btrbk
BTRBK_AWS_SSH_KEY=~/.ssh/btrbk_backup  # UPDATE THIS with your actual key path

# Backup configuration
BTRBK_AWS_TARGET=$btrbk_target
BTRBK_AWS_PATH=/backup_volume/backups

# AWS resource IDs (for troubleshooting)
BTRBK_AWS_INSTANCE_ID=$instance_id
BTRBK_AWS_VOLUME_ID=$volume_id
BTRBK_AWS_REGION=$(grep '^aws_region' terraform.tfvars | cut -d'"' -f2 || echo "us-west-1")

# Example btrbk target configuration:
# target ssh://\${BTRBK_AWS_USER}@\${BTRBK_AWS_HOST}\${BTRBK_AWS_PATH}/
EOF

    log_success "Configuration written to $env_file"

    return 0
}

# Display next steps to user
display_next_steps() {
    local env_file="$PROJECT_DIR/aws_connection.env"

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║   Setup Complete!                                          ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    log_success "AWS infrastructure is ready for backups"
    echo ""
    echo "Connection details saved to: $env_file"
    echo ""
    echo "Next steps:"
    echo "  1. Test SSH connection:"
    echo "     ssh -i ~/.ssh/btrbk_backup btrbk@$(tofu output -raw instance_public_ip)"
    echo ""
    echo "  2. Configure local btrbk (future task - not yet implemented)"
    echo ""
    echo "  3. Run troubleshooting if needed:"
    echo "     ./scripts/troubleshoot.sh check-all"
    echo ""
    echo "To destroy this infrastructure later:"
    echo "  cd $PROJECT_DIR && tofu destroy"
    echo ""
}
```

Update `main()`:
```bash
main() {
    print_banner

    check_prerequisites
    validate_tfvars
    init_terraform
    plan_infrastructure
    apply_infrastructure
    wait_for_instance
    generate_config
    display_next_steps
}
```

**Testing**:
```bash
# Run full setup (requires AWS account)
./btrfs/scripts/setup-aws.sh

# Check generated file
cat btrfs/aws_connection.env

# Verify it has correct values
source btrfs/aws_connection.env
echo $BTRBK_AWS_HOST
ssh -i ~/.ssh/btrbk_backup btrbk@$BTRBK_AWS_HOST "echo 'Connection works!'"
```

**Commit message**:
```
feat: generate configuration file in setup script

- Create aws_connection.env with all connection details
- Include SSH connection info and btrbk target
- Add AWS resource IDs for troubleshooting
- Display clear next steps to user
- Show example commands for testing

Co-authored-by: Sculptor <sculptor@imbue.com>
```

---

## Task 10: Add Smoke Test to Setup Script

**Goal**: Add basic validation that the deployed infrastructure works

**Files to modify**:
- `btrfs/scripts/setup-aws.sh`

**Changes**:
Add this function after `wait_for_instance()` and before `generate_config()`:

```bash
# Run basic smoke tests on deployed infrastructure
smoke_test() {
    log_info "Running smoke tests..."

    cd "$PROJECT_DIR"

    local instance_ip
    instance_ip=$(tofu output -raw instance_public_ip)

    # Determine SSH key path from terraform.tfvars
    # This is a simple heuristic - user may need to update aws_connection.env later
    local ssh_key_path="~/.ssh/btrbk_backup"
    if [[ -f ~/.ssh/btrbk_backup_test ]]; then
        ssh_key_path="~/.ssh/btrbk_backup_test"
    fi

    local ssh_opts="-i $ssh_key_path -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q"

    # Test 1: SSH connection
    log_info "Test 1: SSH connection..."
    if ssh $ssh_opts "btrbk@$instance_ip" "exit" 2>/dev/null; then
        log_success "SSH connection: PASS"
    else
        log_error "SSH connection: FAIL"
        log_warning "Cannot connect to instance. Check security group and SSH key."
        return 1
    fi

    # Test 2: Backup volume mounted
    log_info "Test 2: Backup volume mounted..."
    if ssh $ssh_opts "btrbk@$instance_ip" "mountpoint -q /backup_volume" 2>/dev/null; then
        log_success "Backup volume: MOUNTED"
    else
        log_error "Backup volume: NOT MOUNTED"
        log_warning "Check user_data script logs: ssh $ssh_opts btrbk@$instance_ip 'sudo cat /var/log/cloud-init-output.log'"
        return 1
    fi

    # Test 3: Btrfs filesystem
    log_info "Test 3: Btrfs filesystem..."
    if ssh $ssh_opts "btrbk@$instance_ip" "sudo btrfs filesystem show /backup_volume" &>/dev/null; then
        log_success "Btrfs filesystem: READY"
    else
        log_error "Btrfs filesystem: NOT FOUND"
        return 1
    fi

    # Test 4: Btrbk installed
    log_info "Test 4: Btrbk installation..."
    if ssh $ssh_opts "btrbk@$instance_ip" "btrbk --version" &>/dev/null; then
        local btrbk_version
        btrbk_version=$(ssh $ssh_opts "btrbk@$instance_ip" "btrbk --version" 2>&1 | head -n1)
        log_success "Btrbk: INSTALLED ($btrbk_version)"
    else
        log_error "Btrbk: NOT INSTALLED"
        return 1
    fi

    # Test 5: Restricted SSH commands (should fail)
    log_info "Test 5: SSH command restrictions..."
    if ssh $ssh_opts "btrbk@$instance_ip" "ls /" &>/dev/null; then
        log_error "SSH restrictions: NOT ENFORCED (security issue!)"
        log_warning "btrbk user can run arbitrary commands"
        return 1
    else
        log_success "SSH restrictions: ENFORCED"
    fi

    # Test 6: Allowed commands (should succeed)
    log_info "Test 6: Btrbk commands allowed..."
    if ssh $ssh_opts "btrbk@$instance_ip" "btrfs --version" &>/dev/null; then
        log_success "Btrbk commands: ALLOWED"
    else
        log_error "Btrbk commands: BLOCKED (check btrbk-ssh wrapper)"
        return 1
    fi

    log_success "All smoke tests passed!"
    return 0
}
```

Update `main()`:
```bash
main() {
    print_banner

    check_prerequisites
    validate_tfvars
    init_terraform
    plan_infrastructure
    apply_infrastructure
    wait_for_instance

    # Run smoke tests but don't fail setup if they fail
    # (infrastructure is deployed, tests might have transient failures)
    if ! smoke_test; then
        log_warning "Some smoke tests failed. Infrastructure is deployed but may need troubleshooting."
        log_info "Run: ./scripts/troubleshoot.sh check-all"
    fi

    generate_config
    display_next_steps
}
```

**Testing**:
```bash
# Full setup with smoke tests
./btrfs/scripts/setup-aws.sh

# Should see 6 smoke tests run after deployment
# All should pass for a successful setup
```

**Commit message**:
```
feat: add smoke tests to setup script

- Test SSH connectivity to deployed instance
- Verify backup volume is mounted
- Check btrfs filesystem is created
- Confirm btrbk is installed
- Validate SSH command restrictions work
- Allow setup to complete even if tests fail

Co-authored-by: Sculptor <sculptor@imbue.com>
```

---

## Task 11: Create Troubleshooting Script (Part 1 - Structure)

**Goal**: Create troubleshooting script with subcommand structure

**Files to create**:
- `btrfs/scripts/troubleshoot.sh`

**Content**:
```bash
#!/usr/bin/env bash
# Troubleshooting script for btrfs backup system
#
# Usage: ./scripts/troubleshoot.sh <command>
#
# Commands:
#   check-ssh          Test SSH connectivity to backup server
#   check-volume       Check backup volume status and space
#   check-aws          Verify AWS resources are running
#   check-logs         View remote system logs
#   check-all          Run all checks
#   help               Show this help message

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() { echo -e "${BLUE}INFO:${NC} $*"; }
log_success() { echo -e "${GREEN}SUCCESS:${NC} $*"; }
log_warning() { echo -e "${YELLOW}WARNING:${NC} $*"; }
log_error() { echo -e "${RED}ERROR:${NC} $*" >&2; }

# Load connection details
load_config() {
    local env_file="$PROJECT_DIR/aws_connection.env"

    if [[ ! -f "$env_file" ]]; then
        log_error "Configuration file not found: $env_file"
        log_info "Run ./scripts/setup-aws.sh first to deploy infrastructure"
        exit 1
    fi

    # shellcheck source=/dev/null
    source "$env_file"

    # Validate required variables
    if [[ -z "${BTRBK_AWS_HOST:-}" ]]; then
        log_error "BTRBK_AWS_HOST not set in $env_file"
        exit 1
    fi
}

# Get SSH connection command
get_ssh_cmd() {
    local ssh_key="${BTRBK_AWS_SSH_KEY:-~/.ssh/btrbk_backup}"
    echo "ssh -i $ssh_key -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${BTRBK_AWS_USER}@${BTRBK_AWS_HOST}"
}

# Show help
show_help() {
    cat << EOF
Btrfs Backup System - Troubleshooting Tool

Usage: $0 <command>

Commands:
  check-ssh          Test SSH connectivity to backup server
  check-volume       Check backup volume status and space
  check-aws          Verify AWS resources are running
  check-logs         View remote system logs
  check-all          Run all checks
  help               Show this help message

Examples:
  $0 check-ssh       # Test if you can connect to the server
  $0 check-volume    # Check available disk space
  $0 check-all       # Run all diagnostic checks

Configuration:
  Connection details are loaded from: aws_connection.env
  Edit this file to update SSH key path or other settings

EOF
}

# Subcommand functions (to be implemented in next task)
cmd_check_ssh() {
    log_info "TODO: Implement SSH check"
}

cmd_check_volume() {
    log_info "TODO: Implement volume check"
}

cmd_check_aws() {
    log_info "TODO: Implement AWS check"
}

cmd_check_logs() {
    log_info "TODO: Implement log check"
}

cmd_check_all() {
    log_info "Running all checks..."
    echo ""
    cmd_check_ssh
    echo ""
    cmd_check_volume
    echo ""
    cmd_check_aws
    echo ""
    cmd_check_logs
}

# Main
main() {
    local command="${1:-help}"

    case "$command" in
        check-ssh)
            load_config
            cmd_check_ssh
            ;;
        check-volume)
            load_config
            cmd_check_volume
            ;;
        check-aws)
            load_config
            cmd_check_aws
            ;;
        check-logs)
            load_config
            cmd_check_logs
            ;;
        check-all)
            load_config
            cmd_check_all
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
```

**Make executable**:
```bash
chmod +x btrfs/scripts/troubleshoot.sh
```

**Testing**:
```bash
./btrfs/scripts/troubleshoot.sh help
./btrfs/scripts/troubleshoot.sh check-all  # Should show TODOs
./btrfs/scripts/troubleshoot.sh invalid    # Should show error + help
```

**Commit message**:
```
feat: create troubleshooting script skeleton

- Add subcommand structure (check-ssh, check-volume, etc.)
- Load connection details from aws_connection.env
- Add help text with examples
- Prepare for implementation of check commands

Co-authored-by: Sculptor <sculptor@imbue.com>
```

---

## Task 12: Create Troubleshooting Script (Part 2 - Implement Checks)

**Goal**: Implement all troubleshooting check commands

**Files to modify**:
- `btrfs/scripts/troubleshoot.sh`

**Changes**:
Replace the stub functions with full implementations:

```bash
# Check SSH connectivity
cmd_check_ssh() {
    log_info "Checking SSH connectivity..."

    local ssh_cmd
    ssh_cmd=$(get_ssh_cmd)

    # Test basic connectivity
    if $ssh_cmd "exit" 2>/dev/null; then
        log_success "SSH connection: OK"
    else
        log_error "SSH connection: FAILED"
        log_info "Troubleshooting steps:"
        log_info "  1. Check instance is running: aws ec2 describe-instances --instance-ids ${BTRBK_AWS_INSTANCE_ID}"
        log_info "  2. Check security group allows SSH from your IP"
        log_info "  3. Verify SSH key permissions: chmod 600 ${BTRBK_AWS_SSH_KEY}"
        log_info "  4. Try manual connection: $ssh_cmd"
        return 1
    fi

    # Test btrbk user
    local remote_user
    remote_user=$($ssh_cmd "whoami" 2>/dev/null || echo "unknown")

    if [[ "$remote_user" == "btrbk" ]]; then
        log_success "Connected as btrbk user: OK"
    else
        log_error "Connected as unexpected user: $remote_user"
        return 1
    fi

    # Test command restrictions
    if $ssh_cmd "ls /" &>/dev/null; then
        log_warning "SSH command restrictions: NOT ENFORCED"
        log_warning "btrbk user can run unrestricted commands (security issue)"
    else
        log_success "SSH command restrictions: ENFORCED"
    fi

    # Test allowed commands
    if $ssh_cmd "btrfs --version" &>/dev/null; then
        log_success "Btrfs commands: ALLOWED"
    else
        log_error "Btrfs commands: BLOCKED"
        log_info "Check /usr/local/bin/btrbk-ssh wrapper script on remote host"
        return 1
    fi

    return 0
}

# Check volume status
cmd_check_volume() {
    log_info "Checking backup volume..."

    local ssh_cmd
    ssh_cmd=$(get_ssh_cmd)

    # Check if volume is mounted
    if $ssh_cmd "mountpoint -q /backup_volume" 2>/dev/null; then
        log_success "Volume mounted: OK"
    else
        log_error "Volume not mounted at /backup_volume"
        log_info "Check mount status: $ssh_cmd 'mount | grep backup'"
        log_info "View logs: $ssh_cmd 'sudo cat /var/log/cloud-init-output.log'"
        return 1
    fi

    # Check filesystem type
    local fs_type
    fs_type=$($ssh_cmd "stat -f -c %T /backup_volume" 2>/dev/null || echo "unknown")

    if [[ "$fs_type" == "btrfs" ]]; then
        log_success "Filesystem type: btrfs"
    else
        log_error "Filesystem type: $fs_type (expected btrfs)"
        return 1
    fi

    # Check disk space
    local space_info
    space_info=$($ssh_cmd "df -h /backup_volume | tail -n1" 2>/dev/null || echo "")

    if [[ -n "$space_info" ]]; then
        log_success "Disk space:"
        echo "    $space_info"

        # Extract usage percentage
        local usage_pct
        usage_pct=$(echo "$space_info" | awk '{print $5}' | tr -d '%')

        if [[ "$usage_pct" -gt 90 ]]; then
            log_warning "Disk usage is high: ${usage_pct}%"
            log_info "Consider increasing EBS volume size or cleaning old snapshots"
        fi
    fi

    # Check btrfs filesystem info
    log_info "Btrfs filesystem details:"
    $ssh_cmd "sudo btrfs filesystem show /backup_volume" 2>/dev/null || log_warning "Could not get btrfs details"

    # Check for backups directory
    if $ssh_cmd "test -d /backup_volume/backups" 2>/dev/null; then
        log_success "Backups directory exists"

        # List any existing backups
        local backup_count
        backup_count=$($ssh_cmd "find /backup_volume/backups -type d -maxdepth 2 | wc -l" 2>/dev/null || echo "0")
        log_info "Backup snapshots: $((backup_count - 1))"  # Subtract 1 for backups dir itself
    else
        log_info "Backups directory not yet created (will be created on first backup)"
    fi

    return 0
}

# Check AWS resources
cmd_check_aws() {
    log_info "Checking AWS resources..."

    # Check if AWS CLI is available
    if ! command -v aws &> /dev/null; then
        log_warning "AWS CLI not installed, skipping AWS checks"
        return 0
    fi

    # Check instance status
    log_info "EC2 Instance:"
    local instance_state
    instance_state=$(aws ec2 describe-instances \
        --instance-ids "${BTRBK_AWS_INSTANCE_ID}" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text 2>/dev/null || echo "unknown")

    if [[ "$instance_state" == "running" ]]; then
        log_success "  State: running"
    else
        log_error "  State: $instance_state"
        return 1
    fi

    # Check volume status
    log_info "EBS Volume:"
    local volume_state
    volume_state=$(aws ec2 describe-volumes \
        --volume-ids "${BTRBK_AWS_VOLUME_ID}" \
        --query 'Volumes[0].State' \
        --output text 2>/dev/null || echo "unknown")

    if [[ "$volume_state" == "in-use" ]]; then
        log_success "  State: in-use"
    else
        log_error "  State: $volume_state"
        return 1
    fi

    # Check volume attachment
    local attachment_state
    attachment_state=$(aws ec2 describe-volumes \
        --volume-ids "${BTRBK_AWS_VOLUME_ID}" \
        --query 'Volumes[0].Attachments[0].State' \
        --output text 2>/dev/null || echo "unknown")

    if [[ "$attachment_state" == "attached" ]]; then
        log_success "  Attachment: attached"
    else
        log_error "  Attachment: $attachment_state"
        return 1
    fi

    return 0
}

# Check remote logs
cmd_check_logs() {
    log_info "Fetching remote logs..."

    local ssh_cmd
    ssh_cmd=$(get_ssh_cmd)

    # Cloud-init output (user_data script execution)
    log_info "Cloud-init output (last 30 lines):"
    echo "----------------------------------------"
    $ssh_cmd "sudo tail -n 30 /var/log/cloud-init-output.log" 2>/dev/null || log_error "Could not fetch cloud-init logs"
    echo "----------------------------------------"
    echo ""

    # System logs related to btrbk (if any)
    log_info "Checking for btrbk logs..."
    if $ssh_cmd "test -f /var/log/btrbk.log" 2>/dev/null; then
        echo "----------------------------------------"
        $ssh_cmd "sudo tail -n 20 /var/log/btrbk.log" 2>/dev/null
        echo "----------------------------------------"
    else
        log_info "No btrbk logs yet (normal if no backups have been run)"
    fi

    return 0
}
```

**Testing**:
```bash
# Requires deployed infrastructure
source btrfs/aws_connection.env

# Test individual checks
./btrfs/scripts/troubleshoot.sh check-ssh
./btrfs/scripts/troubleshoot.sh check-volume
./btrfs/scripts/troubleshoot.sh check-aws
./btrfs/scripts/troubleshoot.sh check-logs

# Test all checks
./btrfs/scripts/troubleshoot.sh check-all

# Test with broken setup (stop the instance)
aws ec2 stop-instances --instance-ids $BTRBK_AWS_INSTANCE_ID
./btrfs/scripts/troubleshoot.sh check-all  # Should fail with helpful messages
aws ec2 start-instances --instance-ids $BTRBK_AWS_INSTANCE_ID
```

**Commit message**:
```
feat: implement troubleshooting checks

- check-ssh: Test connectivity, user, and command restrictions
- check-volume: Verify mount, filesystem, space, and backups
- check-aws: Confirm EC2 instance and EBS volume status
- check-logs: Fetch cloud-init and btrbk logs
- Add helpful troubleshooting suggestions on failures

Co-authored-by: Sculptor <sculptor@imbue.com>
```

---

## Task 13: Add Troubleshooting Script Documentation

**Goal**: Document common issues and solutions

**Files to create**:
- `btrfs/docs/TROUBLESHOOTING.md`

**Content**:
```markdown
# Troubleshooting Guide

This guide covers common issues with the btrfs backup system and how to resolve them.

## Quick Diagnostics

Run all automated checks:
```bash
./scripts/troubleshoot.sh check-all
```

Run specific checks:
```bash
./scripts/troubleshoot.sh check-ssh      # Test connectivity
./scripts/troubleshoot.sh check-volume   # Check disk space
./scripts/troubleshoot.sh check-aws      # Verify AWS resources
./scripts/troubleshoot.sh check-logs     # View system logs
```

---

## Common Issues

### 1. SSH Connection Refused

**Symptoms:**
- `ssh: connect to host X.X.X.X port 22: Connection refused`
- Setup script hangs at "Waiting for instance..."

**Causes:**
- Instance is still booting (normal, takes 2-3 minutes)
- Security group doesn't allow SSH from your IP
- Instance is stopped

**Solutions:**
1. Wait a few more minutes for instance to boot
2. Check instance is running:
   ```bash
   aws ec2 describe-instances --instance-ids <instance-id>
   ```
3. Check security group rules in AWS console
4. Verify your public IP hasn't changed (if using IP-restricted security group)

---

### 2. SSH Permission Denied

**Symptoms:**
- `Permission denied (publickey)`

**Causes:**
- Wrong SSH key being used
- SSH key file has incorrect permissions
- Public key not properly configured in terraform.tfvars

**Solutions:**
1. Check SSH key permissions:
   ```bash
   chmod 600 ~/.ssh/btrbk_backup
   ```

2. Verify correct key is specified in aws_connection.env:
   ```bash
   cat aws_connection.env | grep SSH_KEY
   ```

3. Try manual connection with verbose output:
   ```bash
   ssh -v -i ~/.ssh/btrbk_backup btrbk@<instance-ip>
   ```

4. Verify the public key in terraform.tfvars matches your private key:
   ```bash
   ssh-keygen -y -f ~/.ssh/btrbk_backup  # Extract public key from private key
   ```

---

### 3. Volume Not Mounted

**Symptoms:**
- `check-volume` reports volume not mounted
- `/backup_volume` doesn't exist or is empty

**Causes:**
- user_data script failed during execution
- Volume didn't attach properly
- Filesystem creation failed

**Solutions:**
1. Check cloud-init logs:
   ```bash
   ./scripts/troubleshoot.sh check-logs
   ```

2. Check if volume is attached:
   ```bash
   aws ec2 describe-volumes --volume-ids <volume-id>
   ```

3. SSH to instance and check manually:
   ```bash
   ssh -i ~/.ssh/btrbk_backup btrbk@<instance-ip>
   # (may fail due to command restrictions)

   # Temporarily modify btrbk-ssh to allow shell access, or use EC2 console
   ```

4. Reboot instance to retry user_data (if it's set to run on every boot):
   ```bash
   aws ec2 reboot-instances --instance-ids <instance-id>
   ```

---

### 4. Disk Space Full

**Symptoms:**
- `check-volume` shows >90% usage
- Backup commands fail with "No space left on device"

**Causes:**
- Too many old snapshots retained
- Backup data has grown beyond volume size

**Solutions:**
1. Check disk usage:
   ```bash
   ./scripts/troubleshoot.sh check-volume
   ```

2. List snapshots (requires btrbk access):
   ```bash
   # TODO: Document once btrbk is set up
   ```

3. Increase EBS volume size:
   ```bash
   # In terraform.tfvars:
   ebs_volume_size = 200  # Increase from 100

   # Apply change:
   cd btrfs && tofu apply

   # Resize filesystem (after volume is resized):
   ssh -i ~/.ssh/btrbk_backup btrbk@<ip> "sudo btrfs filesystem resize max /backup_volume"
   ```

4. Adjust retention policy in btrbk config (future task)

---

### 5. Command Restrictions Too Strict

**Symptoms:**
- Legitimate btrbk commands fail with "Access denied"
- Can't run necessary btrfs commands

**Causes:**
- btrbk-ssh wrapper script is too restrictive

**Solutions:**
1. Check which command failed (look at SSH error)

2. Update btrbk-ssh whitelist on remote server:
   ```bash
   # Edit /usr/local/bin/btrbk-ssh
   # Add the command pattern to the case statement
   ```

3. For debugging, temporarily allow all commands:
   ```bash
   # On remote server, edit /home/btrbk/.ssh/authorized_keys
   # Temporarily remove the command="btrbk-ssh" restriction
   # REMEMBER TO RE-ADD IT AFTER DEBUGGING
   ```

---

### 6. Terraform Apply Fails

**Symptoms:**
- `tofu apply` errors during setup
- Resources partially created

**Common errors:**

**"InvalidAMIID.NotFound"**
- AMI ID doesn't exist in the region
- Using wrong region
- Solution: Check `aws_region` in terraform.tfvars

**"UnauthorizedOperation"**
- AWS credentials don't have sufficient permissions
- Solution: Ensure IAM user has EC2 and EBS permissions

**"VolumeInUse"**
- Trying to create resources that already exist
- Solution: Run `tofu destroy` first, or import existing resources

**"InvalidKeyPair.Duplicate"**
- SSH key pair with same name already exists
- Solution: Change `key_pair_name` in terraform.tfvars or delete old key pair

---

### 7. Instance Won't Become Ready

**Symptoms:**
- Setup script times out waiting for instance
- Instance is running but not accessible

**Causes:**
- user_data script is still running
- user_data script failed
- Network connectivity issues

**Solutions:**
1. Check instance system log:
   ```bash
   aws ec2 get-console-output --instance-id <instance-id>
   ```

2. Wait longer (user_data can take 5-10 minutes on slow connections)

3. Connect via EC2 Session Manager (if configured):
   ```bash
   aws ssm start-session --target <instance-id>
   ```

4. Check cloud-init status:
   ```bash
   # Via session manager or serial console:
   cloud-init status
   cat /var/log/cloud-init-output.log
   ```

---

## Getting Help

If you encounter an issue not covered here:

1. Run diagnostics: `./scripts/troubleshoot.sh check-all`
2. Collect logs: `./scripts/troubleshoot.sh check-logs`
3. Check Terraform state: `cd btrfs && tofu show`
4. Review AWS console for resource status
5. Open an issue with diagnostic output

## Destroying and Rebuilding

If all else fails, you can destroy and recreate the infrastructure:

```bash
cd btrfs

# Destroy everything
tofu destroy

# Wait for completion, then re-run setup
./scripts/setup-aws.sh
```

**Warning:** This will delete all backups stored on the server. Make sure you have local copies of any important data.
```

**Testing**:
```bash
# Verify markdown renders correctly
cat btrfs/docs/TROUBLESHOOTING.md
```

**Commit message**:
```
docs: add troubleshooting guide

- Document common SSH, volume, and deployment issues
- Provide solutions for each problem
- Add diagnostic commands and debugging steps
- Include guide for destroying and rebuilding

Co-authored-by: Sculptor <sculptor@imbue.com>
```

---

## Task 14: Create End-to-End Test Script (Part 1 - Structure)

**Goal**: Create a test script that validates the entire backup pipeline

**Files to create**:
- `btrfs/scripts/test-backup.sh`

**Content**:
```bash
#!/usr/bin/env bash
# End-to-end test script for btrfs backup system
#
# This script performs a complete test of the backup pipeline:
# 1. Creates a test subvolume with sample data
# 2. Takes a btrfs snapshot
# 3. Sends snapshot to AWS
# 4. Retrieves snapshot from AWS
# 5. Verifies data integrity
# 6. Cleans up test data
#
# Usage: ./scripts/test-backup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() { echo -e "${BLUE}INFO:${NC} $*"; }
log_success() { echo -e "${GREEN}SUCCESS:${NC} $*"; }
log_warning() { echo -e "${YELLOW}WARNING:${NC} $*"; }
log_error() { echo -e "${RED}ERROR:${NC} $*" >&2; }

# Test configuration
TEST_DIR="/tmp/btrbk_test_$$"
TEST_SUBVOL="$TEST_DIR/test_subvolume"
TEST_SNAPSHOT="$TEST_DIR/.snapshots/test_subvolume.$(date +%Y%m%d_%H%M%S)"
TEST_FILE="$TEST_SUBVOL/test_data.txt"
TEST_CONTENT="This is test data generated at $(date)"

# Track test results
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Load configuration
load_config() {
    local env_file="$PROJECT_DIR/aws_connection.env"

    if [[ ! -f "$env_file" ]]; then
        log_error "Configuration not found: $env_file"
        log_info "Run ./scripts/setup-aws.sh first"
        exit 1
    fi

    # shellcheck source=/dev/null
    source "$env_file"
}

# Cleanup function
cleanup() {
    local exit_code=$?

    log_info "Cleaning up test files..."

    # Remove local test directory (if it exists and is on btrfs)
    if [[ -d "$TEST_DIR" ]]; then
        # This will be implemented in part 2
        log_info "Removing $TEST_DIR"
        rm -rf "$TEST_DIR" 2>/dev/null || log_warning "Could not remove test directory"
    fi

    # Print summary
    echo ""
    echo "════════════════════════════════════════"
    echo "Test Summary"
    echo "════════════════════════════════════════"
    echo "Tests run:    $TESTS_RUN"
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    echo "════════════════════════════════════════"

    if [[ $TESTS_FAILED -eq 0 && $TESTS_RUN -gt 0 ]]; then
        log_success "All tests passed!"
        exit 0
    elif [[ $TESTS_RUN -eq 0 ]]; then
        log_warning "No tests were run"
        exit 1
    else
        log_error "$TESTS_FAILED test(s) failed"
        exit 1
    fi
}

trap cleanup EXIT

# Test helper functions
run_test() {
    local test_name=$1
    shift
    local test_command="$*"

    ((TESTS_RUN++))

    log_info "Running test: $test_name"

    if eval "$test_command"; then
        ((TESTS_PASSED++))
        log_success "PASS: $test_name"
        return 0
    else
        ((TESTS_FAILED++))
        log_error "FAIL: $test_name"
        return 1
    fi
}

# Test functions (to be implemented in part 2)
test_prerequisites() {
    log_info "TODO: Check prerequisites"
    return 0
}

test_create_subvolume() {
    log_info "TODO: Create test subvolume"
    return 0
}

test_send_snapshot() {
    log_info "TODO: Send snapshot to AWS"
    return 0
}

test_receive_snapshot() {
    log_info "TODO: Receive snapshot from AWS"
    return 0
}

test_verify_data() {
    log_info "TODO: Verify data integrity"
    return 0
}

# Main
main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║   Btrfs Backup System - End-to-End Test                   ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    load_config

    log_info "This test will validate the complete backup pipeline"
    log_warning "This test requires:"
    log_warning "  - Running on a system with btrfs filesystem"
    log_warning "  - btrbk installed locally"
    log_warning "  - Deployed AWS infrastructure"
    echo ""

    read -p "Continue with test? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Test cancelled"
        exit 0
    fi

    echo ""

    run_test "Check prerequisites" test_prerequisites
    run_test "Create test subvolume" test_create_subvolume
    run_test "Send snapshot to AWS" test_send_snapshot
    run_test "Receive snapshot from AWS" test_receive_snapshot
    run_test "Verify data integrity" test_verify_data

    # Summary printed by cleanup function
}

main "$@"
```

**Make executable**:
```bash
chmod +x btrfs/scripts/test-backup.sh
```

**Testing**:
```bash
./btrfs/scripts/test-backup.sh
# Should show structure but fail on TODO tests
```

**Commit message**:
```
feat: create test script skeleton

- Add end-to-end test framework
- Track test results (pass/fail counts)
- Add cleanup function with summary
- Prepare structure for test implementation

Co-authored-by: Sculptor <sculptor@imbue.com>
```

---

## Task 15: Create End-to-End Test Script (Part 2 - Implementation)

**Goal**: Implement actual backup tests

**Files to modify**:
- `btrfs/scripts/test-backup.sh`

**Changes**:
Replace the test function stubs with implementations:

```bash
# Test prerequisites
test_prerequisites() {
    # Check if we're on a btrfs filesystem
    local current_fs
    current_fs=$(stat -f -c %T /tmp 2>/dev/null || echo "unknown")

    if [[ "$current_fs" != "btrfs" ]]; then
        log_error "Not running on btrfs filesystem (detected: $current_fs)"
        log_info "This test requires a btrfs filesystem for test subvolumes"
        log_info "Create one with: sudo mkfs.btrfs /dev/sdX && sudo mount /dev/sdX /mnt/test"
        return 1
    fi

    # Check btrbk is installed
    if ! command -v btrbk &> /dev/null; then
        log_error "btrbk not installed"
        log_info "Install: apt install btrbk"
        return 1
    fi

    # Check btrfs tools
    if ! command -v btrfs &> /dev/null; then
        log_error "btrfs-progs not installed"
        return 1
    fi

    # Check SSH connectivity
    local ssh_cmd
    ssh_cmd="ssh -i ${BTRBK_AWS_SSH_KEY} -o ConnectTimeout=5 -o StrictHostKeyChecking=no ${BTRBK_AWS_USER}@${BTRBK_AWS_HOST}"

    if ! $ssh_cmd "exit" &>/dev/null; then
        log_error "Cannot connect to AWS backup server"
        log_info "Run: ./scripts/troubleshoot.sh check-ssh"
        return 1
    fi

    return 0
}

# Create test subvolume
test_create_subvolume() {
    # Create test directory
    mkdir -p "$TEST_DIR"

    # Create btrfs subvolume
    if ! sudo btrfs subvolume create "$TEST_SUBVOL" &>/dev/null; then
        log_error "Failed to create test subvolume"
        return 1
    fi

    # Create test data
    echo "$TEST_CONTENT" > "$TEST_FILE"

    # Verify file exists
    if [[ ! -f "$TEST_FILE" ]]; then
        log_error "Test file not created"
        return 1
    fi

    log_info "Created test subvolume with sample data"
    return 0
}

# Create and send snapshot
test_send_snapshot() {
    # Create snapshot directory
    mkdir -p "$(dirname "$TEST_SNAPSHOT")"

    # Take snapshot
    if ! sudo btrfs subvolume snapshot -r "$TEST_SUBVOL" "$TEST_SNAPSHOT" &>/dev/null; then
        log_error "Failed to create snapshot"
        return 1
    fi

    log_info "Created snapshot: $TEST_SNAPSHOT"

    # Send to AWS
    local ssh_cmd
    ssh_cmd="ssh -i ${BTRBK_AWS_SSH_KEY} -o StrictHostKeyChecking=no ${BTRBK_AWS_USER}@${BTRBK_AWS_HOST}"

    local remote_path="${BTRBK_AWS_PATH}/test_$(date +%Y%m%d_%H%M%S)"

    log_info "Sending snapshot to AWS: $remote_path"

    # Create remote directory (this might fail due to command restrictions, that's ok)
    $ssh_cmd "sudo mkdir -p $remote_path" &>/dev/null || true

    # Send snapshot
    if ! sudo btrfs send "$TEST_SNAPSHOT" | $ssh_cmd "sudo btrfs receive $remote_path"; then
        log_error "Failed to send snapshot to AWS"
        log_info "This might be due to SSH command restrictions or permissions"
        return 1
    fi

    # Store remote path for retrieval test
    echo "$remote_path" > "$TEST_DIR/remote_path.txt"

    log_info "Snapshot sent successfully"
    return 0
}

# Retrieve snapshot from AWS
test_receive_snapshot() {
    local remote_path
    remote_path=$(cat "$TEST_DIR/remote_path.txt" 2>/dev/null || echo "")

    if [[ -z "$remote_path" ]]; then
        log_error "Remote path not found (send test may have failed)"
        return 1
    fi

    local ssh_cmd
    ssh_cmd="ssh -i ${BTRBK_AWS_SSH_KEY} -o StrictHostKeyChecking=no ${BTRBK_AWS_USER}@${BTRBK_AWS_HOST}"

    local receive_path="$TEST_DIR/received"
    mkdir -p "$receive_path"

    log_info "Retrieving snapshot from AWS"

    # List remote snapshots to find ours
    local remote_snapshot
    remote_snapshot=$($ssh_cmd "sudo ls $remote_path" 2>/dev/null | head -n1 || echo "")

    if [[ -z "$remote_snapshot" ]]; then
        log_error "No snapshot found at remote path"
        return 1
    fi

    # Receive snapshot
    if ! $ssh_cmd "sudo btrfs send $remote_path/$remote_snapshot" | sudo btrfs receive "$receive_path"; then
        log_error "Failed to receive snapshot from AWS"
        return 1
    fi

    log_info "Snapshot retrieved successfully"

    # Store received snapshot path
    echo "$receive_path/$remote_snapshot" > "$TEST_DIR/received_path.txt"

    return 0
}

# Verify data integrity
test_verify_data() {
    local received_path
    received_path=$(cat "$TEST_DIR/received_path.txt" 2>/dev/null || echo "")

    if [[ -z "$received_path" ]]; then
        log_error "Received snapshot path not found"
        return 1
    fi

    # Check if received file exists
    local received_file="$received_path/test_data.txt"

    if [[ ! -f "$received_file" ]]; then
        log_error "Test file not found in received snapshot"
        return 1
    fi

    # Compare content
    local received_content
    received_content=$(cat "$received_file")

    if [[ "$received_content" != "$TEST_CONTENT" ]]; then
        log_error "Data mismatch!"
        log_error "Expected: $TEST_CONTENT"
        log_error "Received: $received_content"
        return 1
    fi

    log_info "Data integrity verified - content matches!"
    return 0
}
```

Update the cleanup function to handle btrfs subvolumes:

```bash
cleanup() {
    local exit_code=$?

    log_info "Cleaning up test files..."

    # Remove snapshots
    if [[ -d "$TEST_SNAPSHOT" ]]; then
        sudo btrfs subvolume delete "$TEST_SNAPSHOT" &>/dev/null || log_warning "Could not delete snapshot"
    fi

    # Remove received snapshot
    if [[ -f "$TEST_DIR/received_path.txt" ]]; then
        local received_path
        received_path=$(cat "$TEST_DIR/received_path.txt")
        if [[ -d "$received_path" ]]; then
            sudo btrfs subvolume delete "$received_path" &>/dev/null || log_warning "Could not delete received snapshot"
        fi
    fi

    # Remove test subvolume
    if [[ -d "$TEST_SUBVOL" ]]; then
        sudo btrfs subvolume delete "$TEST_SUBVOL" &>/dev/null || log_warning "Could not delete test subvolume"
    fi

    # Remove test directory
    rm -rf "$TEST_DIR" 2>/dev/null || true

    # Cleanup remote test data (best effort)
    if [[ -f "$PROJECT_DIR/aws_connection.env" ]]; then
        source "$PROJECT_DIR/aws_connection.env"
        local ssh_cmd
        ssh_cmd="ssh -i ${BTRBK_AWS_SSH_KEY} -o StrictHostKeyChecking=no ${BTRBK_AWS_USER}@${BTRBK_AWS_HOST}"

        if [[ -f "$TEST_DIR/remote_path.txt" ]]; then
            local remote_path
            remote_path=$(cat "$TEST_DIR/remote_path.txt")
            log_info "Cleaning up remote test data..."
            $ssh_cmd "sudo rm -rf $remote_path" &>/dev/null || log_warning "Could not clean remote test data"
        fi
    fi

    # Print summary (same as before)
    echo ""
    echo "════════════════════════════════════════"
    echo "Test Summary"
    echo "════════════════════════════════════════"
    echo "Tests run:    $TESTS_RUN"
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    echo "════════════════════════════════════════"

    if [[ $TESTS_FAILED -eq 0 && $TESTS_RUN -gt 0 ]]; then
        log_success "All tests passed!"
        exit 0
    elif [[ $TESTS_RUN -eq 0 ]]; then
        log_warning "No tests were run"
        exit 1
    else
        log_error "$TESTS_FAILED test(s) failed"
        exit 1
    fi
}
```

**Testing**:
```bash
# Requires:
# - System with btrfs (or /tmp on btrfs)
# - btrbk installed
# - Deployed AWS infrastructure

./btrfs/scripts/test-backup.sh

# Should:
# 1. Create test subvolume
# 2. Send to AWS
# 3. Retrieve from AWS
# 4. Verify data matches
# 5. Clean up everything
```

**Note**: This test might fail due to SSH command restrictions or permissions. That's expected and helps identify issues that need to be fixed in the btrbk-ssh wrapper or AWS user permissions.

**Commit message**:
```
feat: implement end-to-end backup test

- Test prerequisites (btrfs, btrbk, SSH)
- Create test subvolume with sample data
- Send snapshot to AWS via btrfs send
- Retrieve snapshot from AWS via btrfs receive
- Verify data integrity after round-trip
- Clean up all test artifacts (local and remote)

Co-authored-by: Sculptor <sculptor@imbue.com>
```

---

## Task 16: Update Main README

**Goal**: Document the complete AWS setup process

**Files to modify**:
- `btrfs/README.md`

**Changes**:
Replace or significantly expand the README:

```markdown
# Seamless Multi-Device Filesystem

A btrfs-based backup system that enables a single filesystem to be securely backed up across devices and cloud storage, with eventual consistency and bidirectional sync.

## Project Goals

### End Goal
Enable a filesystem to be shared seamlessly across multiple devices with:
- Automatic, eager backups to cloud storage
- Eventual consistency even with diverging changes on different machines
- Incremental, space-efficient snapshots using btrfs
- Secure, encrypted remote storage

### Current Status
**Phase 1 Complete**: AWS infrastructure setup with automated deployment

## Architecture Overview

### Technology Stack
- **btrfs**: Modern Linux filesystem with built-in snapshot support
- **btrbk**: Backup tool leveraging btrfs send/receive for incremental backups
- **OpenTofu**: Infrastructure-as-code for reproducible AWS deployment
- **AWS EC2 + EBS**: Cloud backup target with encrypted storage

### Design Rationale

**Why btrfs?**
- Built-in copy-on-write snapshots (instant, space-efficient)
- Incremental send/receive (only transfer changed blocks)
- Stable and production-ready on Linux

**Why btrbk?**
- Purpose-built for btrfs snapshot management
- Supports complex retention policies
- SSH-based remote sync
- Handles incremental backups automatically

**Why AWS?**
- Reliable, encrypted storage
- Pay-per-use pricing (~$3-5/month for 100GB)
- Global availability
- Easy to provision via IaC

**Why bidirectional sync?**
- Enables multi-device workflows
- Foundation for eventual consistency
- Allows pulling latest state to new/restored machines

---

## Setup Guide

### Prerequisites

- **OpenTofu** (or Terraform): [Install OpenTofu](https://opentofu.org/docs/intro/install/)
- **AWS Account**: With credentials configured (`aws configure`)
- **SSH**: Client for connecting to backup server
- **btrfs-progs**: For local backup operations (future use)

Check prerequisites:
```bash
./scripts/check-prerequisites.sh
```

### Quick Start

1. **Clone and navigate**:
   ```bash
   cd btrfs
   ```

2. **Configure deployment**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   $EDITOR terraform.tfvars
   ```

3. **Generate SSH key** (or use existing):
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/btrbk_backup -C "btrbk-backup"
   # Copy public key into terraform.tfvars
   cat ~/.ssh/btrbk_backup.pub
   ```

4. **Deploy AWS infrastructure**:
   ```bash
   ./scripts/setup-aws.sh
   ```

   This will:
   - Validate configuration and prerequisites
   - Initialize OpenTofu
   - Show deployment plan
   - Prompt for confirmation
   - Deploy EC2 instance with encrypted EBS volume
   - Configure btrfs filesystem and btrbk
   - Generate `aws_connection.env` with connection details
   - Run smoke tests to verify setup

5. **Test connection**:
   ```bash
   source aws_connection.env
   ssh -i ~/.ssh/btrbk_backup btrbk@$BTRBK_AWS_HOST
   ```

### What Gets Created

The setup script deploys:
- **EC2 Instance**: t3a.nano (minimal, cost-effective) in your specified region
- **EBS Volume**: 100GB encrypted storage for backups
- **Security Group**: SSH access from any IP (customizable in .tf file)
- **SSH Key Pair**: For secure authentication
- **User Configuration**: Dedicated `btrbk` user with restricted commands

### Cost Estimate

- EC2 t3a.nano: ~$3/month (us-west-1)
- EBS 100GB gp3: ~$8/month
- **Total**: ~$11/month

Costs vary by region. Stop the instance when not actively syncing to reduce costs.

---

## Usage

### Configuration

Connection details are in `aws_connection.env`:
```bash
source aws_connection.env
echo $BTRBK_AWS_TARGET  # Use this in btrbk.conf
```

### Troubleshooting

Run diagnostics:
```bash
./scripts/troubleshoot.sh check-all
```

Specific checks:
```bash
./scripts/troubleshoot.sh check-ssh      # Test connectivity
./scripts/troubleshoot.sh check-volume   # Check disk space
./scripts/troubleshoot.sh check-aws      # Verify AWS resources
./scripts/troubleshoot.sh check-logs     # View system logs
```

See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for common issues.

### Testing

Run end-to-end backup test:
```bash
./scripts/test-backup.sh
```

This validates the complete backup pipeline (requires local btrfs filesystem).

---

## Roadmap

### Phase 1: AWS Infrastructure ✅
- [x] Terraform configuration for AWS resources
- [x] Automated setup script
- [x] Troubleshooting tools
- [x] End-to-end testing
- [x] Documentation

### Phase 2: Local Configuration (In Progress)
- [ ] Local btrbk configuration script
- [ ] Scheduled backups (cron/systemd timer)
- [ ] Pre-sleep backup hook
- [ ] Pattern-based exclusions (secrets, build artifacts)

### Phase 3: Enhanced Features
- [ ] 1Password integration for credentials
- [ ] Symbolic reference to latest backup
- [ ] Automatic sync on wake/sleep
- [ ] Multi-device conflict detection

### Phase 4: Multi-Device Sync
- [ ] Device registry and metadata
- [ ] Merge strategies for diverging changes
- [ ] Eventual consistency guarantees
- [ ] Conflict resolution UI

---

## File Structure

```
btrfs/
├── README.md                      # This file
├── btrbk_aws.tf                   # OpenTofu infrastructure definition
├── terraform.tfvars.example       # Configuration template
├── btrbk_config                   # btrbk configuration (WIP)
├── aws_connection.env             # Generated connection details
├── scripts/
│   ├── check-prerequisites.sh     # Verify required tools
│   ├── setup-aws.sh               # Deploy AWS infrastructure
│   ├── troubleshoot.sh            # Diagnostic tools
│   └── test-backup.sh             # End-to-end tests
└── docs/
    ├── TROUBLESHOOTING.md         # Common issues and solutions
    └── plans/
        └── btrfs                  # Detailed implementation plan

```

---

## Security Considerations

### Implemented
- Encrypted EBS volume (AWS-managed keys)
- SSH public key authentication (no passwords)
- Restricted SSH commands (btrbk user can only run btrfs/btrbk commands)
- Dedicated system user with limited permissions

### Planned
- 1Password integration for SSH key management
- IP-restricted security groups (optional)
- Client-side encryption for sensitive data
- Audit logging for backup operations

### Best Practices
1. Never commit `terraform.tfvars` or SSH private keys
2. Rotate SSH keys periodically
3. Review security group rules for your threat model
4. Monitor AWS CloudWatch for unusual activity
5. Test restore procedures regularly

---

## Maintenance

### Updating Infrastructure

Edit `btrbk_aws.tf` or `terraform.tfvars`, then:
```bash
cd btrfs
tofu plan    # Review changes
tofu apply   # Apply updates
```

### Destroying Infrastructure

```bash
cd btrfs
tofu destroy
```

**Warning**: This permanently deletes all backups stored on the server.

### Checking Backup Status

```bash
./scripts/troubleshoot.sh check-volume  # See disk usage
# TODO: btrbk-specific commands (Phase 2)
```

---

## Contributing

This is a personal project, but suggestions and improvements are welcome. See `docs/plans/btrfs` for the detailed implementation plan.

---

## Known Limitations

- Currently requires manual local btrbk configuration (Phase 2)
- No automatic conflict resolution for diverging changes
- Single cloud backup target (AWS only)
- Requires btrfs on local machines
- SSH command restrictions may be too strict for some btrbk operations

---

## References

- [btrfs Documentation](https://btrfs.readthedocs.io/)
- [btrbk Documentation](https://digint.ch/btrbk/)
- [OpenTofu Documentation](https://opentofu.org/docs/)
- [AWS EC2 Pricing](https://aws.amazon.com/ec2/pricing/)
```

**Testing**:
```bash
cat btrfs/README.md  # Verify content
```

**Commit message**:
```
docs: comprehensive README for AWS setup

- Add architecture overview and design rationale
- Document complete setup process
- Add usage, troubleshooting, and testing sections
- Include roadmap and known limitations
- Document security considerations
- Add cost estimates and maintenance procedures

Co-authored-by: Sculptor <sculptor@imbue.com>
```

---

## Task 17: Create 1Password Integration Proposal

**Goal**: Document future 1Password integration approach

**Files to create**:
- `btrfs/docs/1PASSWORD_INTEGRATION.md`

**Content**:
```markdown
# 1Password Integration Proposal

This document outlines the planned integration with 1Password for secure credential and SSH key management.

## Goals

1. Store SSH keys in 1Password instead of filesystem
2. Use 1Password SSH agent for authentication
3. Store AWS connection details as secure notes
4. Eliminate plaintext credential files

## Current State

**Today:**
- SSH keys stored in `~/.ssh/` directory
- Connection details in `aws_connection.env` (gitignored)
- Users must manually manage keys and protect them
- Risk of accidental exposure or loss

**Limitations:**
- Keys can be accidentally committed
- No centralized credential management
- Difficult to share setup across devices
- Manual backup/restore of keys

## Proposed Integration

### Phase 1: SSH Key Management

**1Password SSH Agent** provides SSH key storage and authentication without filesystem keys.

#### Setup

1. Enable 1Password SSH agent:
   - 1Password Settings → Developer → SSH Agent → Enable
   - Configure `~/.ssh/config` to use 1Password socket

2. Generate SSH key in 1Password:
   - Create new item: Type "SSH Key"
   - Name: "btrbk-backup"
   - Generate ED25519 key
   - Add notes with server details

3. Export public key for Terraform:
   ```bash
   op item get "btrbk-backup" --fields "public key" > btrbk_backup.pub
   ```

4. Update `terraform.tfvars`:
   ```hcl
   ssh_public_key = file("btrbk_backup.pub")
   ```

#### Usage

Authentication happens automatically via 1Password agent:
```bash
# No need to specify -i flag, 1Password handles it
ssh btrbk@$BTRBK_AWS_HOST
```

#### Benefits
- Keys never touch filesystem
- Biometric unlock for SSH operations
- Automatic key management across devices
- Built-in secure backup

### Phase 2: Connection Details Storage

Store AWS connection info as structured data in 1Password.

#### Structure

Create 1Password item: Type "Secure Note"
- **Title**: "Btrfs Backup - AWS Connection"
- **Fields**:
  - `aws_host` (text): EC2 instance public IP
  - `aws_user` (text): btrbk
  - `aws_path` (text): /backup_volume/backups
  - `aws_instance_id` (text): i-xxxxx
  - `aws_volume_id` (text): vol-xxxxx
  - `aws_region` (text): us-west-1
  - `btrbk_target` (text): ssh://btrbk@X.X.X.X/backup_volume/backups/
- **Tags**: btrbk, backup, aws

#### Script Integration

Update scripts to read from 1Password:

```bash
# Load connection details
load_config() {
    local op_item="Btrfs Backup - AWS Connection"

    # Check 1Password CLI is available
    if ! command -v op &> /dev/null; then
        log_error "1Password CLI not installed"
        log_info "Install: https://developer.1password.com/docs/cli/get-started/"
        exit 1
    fi

    # Authenticate if needed
    if ! op account list &>/dev/null; then
        log_info "Sign in to 1Password"
        eval $(op signin)
    fi

    # Fetch values
    BTRBK_AWS_HOST=$(op item get "$op_item" --fields aws_host)
    BTRBK_AWS_USER=$(op item get "$op_item" --fields aws_user)
    BTRBK_AWS_PATH=$(op item get "$op_item" --fields aws_path)
    BTRBK_AWS_INSTANCE_ID=$(op item get "$op_item" --fields aws_instance_id)
    BTRBK_AWS_VOLUME_ID=$(op item get "$op_item" --fields aws_volume_id)
    BTRBK_AWS_REGION=$(op item get "$op_item" --fields aws_region)
    BTRBK_AWS_TARGET=$(op item get "$op_item" --fields btrbk_target)

    export BTRBK_AWS_HOST BTRBK_AWS_USER BTRBK_AWS_PATH
    export BTRBK_AWS_INSTANCE_ID BTRBK_AWS_VOLUME_ID BTRBK_AWS_REGION
    export BTRBK_AWS_TARGET
}
```

#### Benefits
- No plaintext credentials on disk
- Encrypted at rest and in transit
- Accessible from any device with 1Password
- Version history for connection details
- Searchable and taggable

### Phase 3: Automated Setup Workflow

**Goal**: Setup script automatically stores credentials in 1Password after deployment.

#### Implementation

Update `scripts/setup-aws.sh`:

```bash
# After successful deployment
store_credentials_in_1password() {
    log_info "Storing connection details in 1Password..."

    # Check if user wants this
    read -p "Store credentials in 1Password? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Skipping 1Password storage"
        return 0
    fi

    # Create or update 1Password item
    local item_name="Btrfs Backup - AWS Connection"

    # Check if item exists
    if op item get "$item_name" &>/dev/null; then
        log_info "Updating existing 1Password item"
        op item edit "$item_name" \
            aws_host="$instance_ip" \
            aws_instance_id="$instance_id" \
            aws_volume_id="$volume_id" \
            btrbk_target="$btrbk_target"
    else
        log_info "Creating new 1Password item"
        op item create \
            --category "Secure Note" \
            --title "$item_name" \
            aws_host="$instance_ip" \
            aws_user="btrbk" \
            aws_path="/backup_volume/backups" \
            aws_instance_id="$instance_id" \
            aws_volume_id="$volume_id" \
            aws_region="$aws_region" \
            btrbk_target="$btrbk_target" \
            --tags "btrbk,backup,aws"
    fi

    log_success "Credentials stored in 1Password"
    log_info "Access with: op item get '$item_name'"
}
```

#### Workflow

1. User runs `./scripts/setup-aws.sh`
2. Infrastructure is deployed
3. Script prompts to store in 1Password
4. Credentials automatically saved
5. User can delete `aws_connection.env`

### Phase 4: Multi-Device Sync

**Goal**: Make it seamless to use backups from multiple machines.

#### Device Registration

When setting up btrbk on a new machine:

```bash
./scripts/setup-local.sh

# Script prompts:
# 1. Sign in to 1Password
# 2. Fetch connection details automatically
# 3. Configure local btrbk with AWS target
# 4. Test connection
# 5. Register device metadata in 1Password
```

#### Device Metadata

Store each device as a separate 1Password item:
- **Title**: "Btrfs Backup - Device: hostname"
- **Fields**:
  - `hostname` (text): machine name
  - `last_backup` (date): timestamp of last successful backup
  - `btrbk_version` (text): installed version
  - `subvolumes` (text): list of backed up paths
- **Tags**: btrbk, device, hostname

#### Benefits
- Quick setup on new machines
- Track which devices are backing up
- Identify stale or orphaned devices
- Centralized configuration management

---

## Implementation Checklist

### Prerequisites
- [ ] Install 1Password CLI: `brew install 1password-cli`
- [ ] Enable 1Password SSH Agent in settings
- [ ] Sign in to 1Password: `op signin`

### Phase 1: SSH Keys
- [ ] Generate SSH key in 1Password
- [ ] Update `~/.ssh/config` to use 1Password agent
- [ ] Test SSH connection with 1Password key
- [ ] Update documentation

### Phase 2: Connection Details
- [ ] Create secure note template
- [ ] Update scripts to read from 1Password
- [ ] Add fallback to `aws_connection.env` for compatibility
- [ ] Test all scripts with 1Password integration

### Phase 3: Automated Storage
- [ ] Update `setup-aws.sh` to store credentials
- [ ] Add opt-in prompt for 1Password
- [ ] Handle item updates vs. creates
- [ ] Add error handling for 1Password failures

### Phase 4: Multi-Device
- [ ] Design device registration workflow
- [ ] Create `setup-local.sh` with 1Password integration
- [ ] Add device metadata storage
- [ ] Implement device listing command

---

## Security Considerations

### Advantages
- **No filesystem keys**: Keys in 1Password are encrypted at rest
- **Biometric unlock**: Touch ID/Face ID for SSH operations
- **Audit trail**: 1Password logs all access
- **Revocation**: Disable key access without deleting keys
- **Sharing**: Securely share with team members (if needed)

### Risks
- **Single point of failure**: 1Password account compromise exposes all credentials
- **Dependency**: System requires 1Password to function
- **Online requirement**: Initial setup requires internet access

### Mitigations
- Enable 2FA on 1Password account
- Use strong master password
- Keep 1Password Emergency Kit in secure physical location
- Maintain offline backup of critical keys (encrypted)
- Document recovery procedures

---

## Compatibility

### Backwards Compatibility

Scripts should support both approaches:
1. Try 1Password first
2. Fall back to `aws_connection.env` if 1Password unavailable
3. Log which method is used

Example:
```bash
load_config() {
    if command -v op &>/dev/null && op item get "Btrfs Backup - AWS Connection" &>/dev/null; then
        log_info "Loading configuration from 1Password"
        load_from_1password
    elif [[ -f "$PROJECT_DIR/aws_connection.env" ]]; then
        log_info "Loading configuration from aws_connection.env"
        source "$PROJECT_DIR/aws_connection.env"
    else
        log_error "No configuration found"
        exit 1
    fi
}
```

### Migration Path

For existing users:
1. Keep current setup working
2. Add opt-in flag: `--use-1password`
3. Provide migration script: `./scripts/migrate-to-1password.sh`
4. Document both approaches in README
5. Eventually deprecate file-based credentials (Phase 4+)

---

## Future Enhancements

- **Service account**: 1Password Service Account for CI/CD
- **Rotation**: Automated SSH key rotation with 1Password CLI
- **MFA**: Require 1Password MFA for backup operations
- **Sharing**: Share AWS connection with team via shared vault
- **Templates**: 1Password item templates for quick setup

---

## References

- [1Password SSH Agent](https://developer.1password.com/docs/ssh/)
- [1Password CLI](https://developer.1password.com/docs/cli/)
- [Secure Notes](https://support.1password.com/secure-notes/)
```

**Testing**:
```bash
cat btrfs/docs/1PASSWORD_INTEGRATION.md
```

**Commit message**:
```
docs: add 1password integration proposal

- Document SSH key management via 1Password agent
- Propose connection details storage in secure notes
- Design automated credential storage workflow
- Plan multi-device registration system
- Address security considerations and migration path

Co-authored-by: Sculptor <sculptor@imbue.com>
```

---

## Task 18: Create Local Setup Plan Document

**Goal**: Document the next phase (local btrbk configuration)

**Files to create**:
- `btrfs/docs/LOCAL_SETUP_PLAN.md`

**Content**:
```markdown
# Local Setup Plan (Phase 2)

This document outlines Phase 2 of the btrfs backup system: configuring local machines to back up to the AWS infrastructure.

## Goals

- Automated local btrbk configuration
- Scheduled backups (systemd timer or cron)
- Pre-sleep backup hook
- Pattern-based exclusions for sensitive data
- Documentation on incremental backups

## Prerequisites

- Phase 1 complete (AWS infrastructure deployed)
- Local machine running btrfs filesystem
- btrbk installed locally
- Connection details available (via `aws_connection.env` or 1Password)

---

## Tasks

### Task 1: Create Local Prerequisites Check

**File**: `btrfs/scripts/check-local-prerequisites.sh`

**Checks**:
- [ ] btrbk installed
- [ ] btrfs-progs installed
- [ ] At least one btrfs filesystem mounted
- [ ] SSH connectivity to AWS server
- [ ] Write permissions to backup directories

### Task 2: Generate btrbk Configuration

**File**: `btrfs/scripts/generate-btrbk-config.sh`

**Inputs**:
- AWS connection details (from Phase 1)
- List of subvolumes to back up (user specifies)
- Retention policy (prompt or use defaults)
- Exclusion patterns (optional)

**Outputs**:
- `/etc/btrbk/btrbk.conf` or `~/.config/btrbk/btrbk.conf`

**Features**:
- Detect existing btrfs subvolumes
- Suggest common paths (/home, /data, etc.)
- Validate subvolumes exist and are btrfs
- Set up bidirectional sync (send and receive)

### Task 3: Implement Exclusion Patterns

**Goal**: Allow excluding sensitive files from backups

**Approach**:
- btrbk doesn't natively support exclusions (snapshots are complete)
- Options:
  1. Create separate subvolumes for sensitive data
  2. Use btrbk's `snapshot_create` hook to exclude files
  3. Document best practices for organizing data

**Recommended**:
- Create separate subvolume for secrets: `/home/user/.secrets`
- Mount it separately or exclude from btrbk config
- Document in README

**File**: `btrfs/docs/EXCLUSION_PATTERNS.md`

### Task 4: Create Local Setup Script

**File**: `btrfs/scripts/setup-local.sh`

**Workflow**:
1. Check prerequisites
2. Load AWS connection details
3. Prompt for subvolumes to back up
4. Generate btrbk configuration
5. Test btrbk configuration (dry run)
6. Perform initial backup
7. Set up scheduling (next task)

**Features**:
- Interactive prompts with sensible defaults
- Validate configuration before writing
- Test SSH connection to AWS
- Show estimated backup size

### Task 5: Set Up Scheduled Backups

**File**: `btrfs/scripts/setup-backup-schedule.sh`

**Options**:
1. **systemd timer** (modern, recommended)
   - Create `btrbk-backup.service`
   - Create `btrbk-backup.timer`
   - Enable timer: `systemctl enable --user btrbk-backup.timer`

2. **cron** (traditional, compatible)
   - Add entry to user crontab
   - Run every 4 hours: `0 */4 * * * /usr/bin/btrbk run`

**Implementation**:
- Detect if systemd is available
- Offer both options, recommend systemd
- Configure logging to journal or file
- Set up failure notifications (systemd-notify or email)

### Task 6: Create Pre-Sleep Backup Hook

**Goal**: Automatically back up before laptop sleeps

**File**: `btrfs/scripts/pre-sleep-backup.sh`

**Approaches**:

**systemd-logind**:
```ini
# /etc/systemd/system/btrbk-pre-sleep.service
[Unit]
Description=Backup before sleep
Before=sleep.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/btrbk run --preserve-snapshots

[Install]
WantedBy=sleep.target
```

**Considerations**:
- Timeout: Don't delay sleep indefinitely
- Background: Run in background if takes too long
- Snapshot only: Quick local snapshot, sync later on wake
- User notification: Show notification when backup completes

### Task 7: Document Incremental Backups

**File**: `btrfs/docs/INCREMENTAL_BACKUPS.md`

**Content**:
- How btrfs snapshots work (COW, subvolumes)
- How btrbk send/receive works
- What "incremental" means (parent snapshot reference)
- Storage efficiency (shared extents)
- Performance characteristics
- Troubleshooting common issues

**Diagrams**:
- Snapshot hierarchy tree
- Data flow: local → AWS → other device
- Timeline of snapshots with retention

### Task 8: Test Local Setup End-to-End

**File**: `btrfs/scripts/test-local-setup.sh`

**Tests**:
- [ ] btrbk configuration is valid
- [ ] Can take local snapshot
- [ ] Can send snapshot to AWS
- [ ] Can list snapshots on AWS
- [ ] Can receive snapshot from AWS
- [ ] Scheduled backup runs successfully
- [ ] Pre-sleep hook works
- [ ] Exclusions are respected (if configured)

### Task 9: Create Backup Monitoring Script

**File**: `btrfs/scripts/monitor-backups.sh`

**Features**:
- List all local snapshots
- List all remote snapshots
- Show last backup time
- Check for failed backups
- Estimate disk space usage
- Warn if backups are stale (>24 hours)

**Output formats**:
- Human-readable text (default)
- JSON (for scripting)
- Table (for dashboard)

### Task 10: Update Documentation

**Files**:
- `btrfs/README.md`: Add local setup section
- `btrfs/docs/TROUBLESHOOTING.md`: Add local issues
- `btrfs/docs/LOCAL_SETUP_PLAN.md`: Mark as complete

**README updates**:
- Add "Local Configuration" section
- Document scheduled backups
- Show example btrbk configuration
- Explain backup workflow

---

## Technical Details

### btrbk Configuration Template

```ini
# Timestamp format for snapshot names
timestamp_format        YYYY-MM-DD-HHMM

# SSH identity (or use 1Password SSH agent)
ssh_identity           ~/.ssh/btrbk_backup

# Retention policy
# Keep: 24 hourly, 7 daily, 4 weekly, 6 monthly
snapshot_preserve_min  latest
snapshot_preserve      24h 7d 4w 6m
target_preserve_min    latest
target_preserve        24h 7d 4w 6m

# Remote target
target_preserve        yes

# Volume configuration
volume /mnt/data
  # Subvolume to back up
  subvolume home
    # Local snapshots directory
    snapshot_dir         .snapshots

    # Remote target (AWS)
    target               ssh://btrbk@X.X.X.X/backup_volume/backups/
    target_preserve_path yes

  # Add more subvolumes here
  subvolume code
    snapshot_dir         .snapshots
    target               ssh://btrbk@X.X.X.X/backup_volume/backups/
    target_preserve_path yes
```

### Bidirectional Sync Configuration

To enable pulling snapshots from AWS:

```ini
# On AWS server, create btrbk config that allows local machines to pull
# /etc/btrbk/btrbk.conf on AWS

timestamp_format        YYYY-MM-DD-HHMM

volume /backup_volume
  subvolume backups
    snapshot_dir         snapshots
    snapshot_preserve    24h 7d 4w 6m

    # Allow local machines to pull
    # This requires btrbk to be set up on AWS side too
```

### systemd Timer Example

**Service** (`~/.config/systemd/user/btrbk-backup.service`):
```ini
[Unit]
Description=Btrfs backup with btrbk
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/btrbk --config=/home/%u/.config/btrbk/btrbk.conf run
StandardOutput=journal
StandardError=journal
```

**Timer** (`~/.config/systemd/user/btrbk-backup.timer`):
```ini
[Unit]
Description=Run btrbk backup every 4 hours

[Timer]
OnBootSec=5min
OnUnitActiveSec=4h
Persistent=true

[Install]
WantedBy=timers.target
```

**Enable**:
```bash
systemctl --user enable btrbk-backup.timer
systemctl --user start btrbk-backup.timer
systemctl --user status btrbk-backup.timer
```

---

## Testing Strategy

### Unit Tests
- [ ] Config generation with various inputs
- [ ] Exclusion pattern handling
- [ ] Retention policy calculations
- [ ] Error handling for invalid inputs

### Integration Tests
- [ ] Full setup on clean system
- [ ] Scheduled backup execution
- [ ] Pre-sleep hook triggers
- [ ] Bidirectional sync works
- [ ] Recovery from backup

### Manual Tests
- [ ] User experience (prompts, messages)
- [ ] Documentation clarity
- [ ] Performance on large backups
- [ ] Network interruption handling

---

## Error Handling

### Common Errors

**No btrfs filesystem**:
- Detect during prerequisites check
- Provide clear error message
- Link to btrfs setup documentation

**SSH connection fails**:
- Test connection before starting backup
- Retry with exponential backoff
- Log failure for debugging
- Don't block system sleep indefinitely

**Insufficient space**:
- Check available space before backup
- Warn if <20% space remaining
- Suggest cleanup or volume expansion

**Retention policy conflicts**:
- Validate policy makes sense (e.g., keep daily for 7d, not 100d on small volume)
- Warn about aggressive retention

---

## Open Questions

1. **Subvolume detection**: How to automatically find which subvolumes to back up?
   - Parse `/proc/mounts` for btrfs mounts?
   - Use `btrfs subvolume list`?
   - Let user manually specify?

2. **Bidirectional sync**: Should AWS automatically send snapshots back?
   - On schedule?
   - On demand only?
   - Per-device policy?

3. **Conflict resolution**: What if a snapshot name collides?
   - btrbk handles this with timestamps
   - But what about diverging changes?

4. **Multi-device sync**: How to merge snapshots from different devices?
   - Future phase, but affects config design
   - Need device metadata tracking

5. **Large files**: How to handle very large files efficiently?
   - btrfs handles this well (COW)
   - But network transfer can be slow
   - Consider compression in SSH or btrfs

---

## Success Criteria

Phase 2 is complete when:
- [ ] User can run one script to set up local backups
- [ ] Backups run automatically on schedule
- [ ] Backups happen before system sleeps
- [ ] User can exclude sensitive data
- [ ] Documentation explains how incremental backups work
- [ ] Monitoring script shows backup status
- [ ] Tests validate the entire pipeline
- [ ] README is updated with local setup instructions

---

## Next Phase: Phase 3 (Enhanced Features)

After Phase 2:
- 1Password integration (see 1PASSWORD_INTEGRATION.md)
- Symbolic reference to latest backup
- Automatic sync on wake
- Web dashboard for monitoring
- Email notifications for failures
- Compression optimization
- Deduplication analysis
```

**Testing**:
```bash
cat btrfs/docs/LOCAL_SETUP_PLAN.md
```

**Commit message**:
```
docs: add local setup plan (phase 2)

- Outline local btrbk configuration tasks
- Design scheduled backup system
- Plan pre-sleep backup hook
- Document exclusion patterns approach
- Provide technical details and examples
- Define success criteria and testing strategy

Co-authored-by: Sculptor <sculptor@imbue.com>
```

---

## Summary

This implementation plan provides a complete roadmap for Phase 1 of the btrfs backup system. By following these tasks in order, an engineer with minimal context can:

1. Fix and deploy AWS infrastructure (Tasks 1-5)
2. Build automated setup tooling (Tasks 6-10)
3. Create troubleshooting utilities (Tasks 11-13)
4. Implement testing harness (Tasks 14-15)
5. Write comprehensive documentation (Tasks 16-18)

### Key Principles Applied

- **DRY**: Reusable functions, scripts call each other, shared configuration
- **YAGNI**: Build only what's needed for Phase 1, defer future features
- **TDD**: Test after each task, validate before proceeding
- **Frequent commits**: Each task is one commit, easy to review

### Testing Strategy

Each task includes specific testing instructions. The plan ensures:
- Syntax validation before deployment
- Integration tests after implementation
- End-to-end tests for complete pipeline
- Manual testing for user experience

### Documentation Hierarchy

- **README**: High-level overview, quick start, concepts
- **TROUBLESHOOTING**: Common issues and solutions
- **Implementation plans**: Detailed task breakdowns
- **Proposals**: Future enhancements (1Password, local setup)
- **Inline comments**: Technical details in code

### Next Steps

After completing these 18 tasks:
1. Review and merge all commits
2. Tag release: `v1.0.0-phase1`
3. Test on fresh AWS account
4. Gather feedback
5. Begin Phase 2 (local setup)
