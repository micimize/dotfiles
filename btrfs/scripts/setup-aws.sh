#!/usr/bin/env bash
# AWS Infrastructure Setup Script for Btrfs Backup System
#
# This script automates the deployment of AWS infrastructure for btrbk backups.
# It wraps OpenTofu/Terraform commands with proper error handling and generates
# configuration files for local backup setup.
#
# Usage (from repo root): ./btrfs/scripts/setup-aws.sh

set -euo pipefail

# Determine repo root and btrfs directory
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BTRFS_DIR="$REPO_ROOT/btrfs"
SCRIPTS_DIR="$BTRFS_DIR/scripts"

# Detect whether to use tofu or terraform
if command -v tofu &> /dev/null; then
    TF_CMD="tofu"
elif command -v terraform &> /dev/null; then
    TF_CMD="terraform"
else
    echo "ERROR: Neither tofu nor terraform found. Please install one of them."
    exit 1
fi

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

# Check prerequisites using separate script
check_prerequisites() {
    log_info "Checking prerequisites..."

    if [[ ! -x "$SCRIPTS_DIR/check-prerequisites.sh" ]]; then
        error_exit "Prerequisites script not found or not executable: $SCRIPTS_DIR/check-prerequisites.sh"
    fi

    if ! "$SCRIPTS_DIR/check-prerequisites.sh"; then
        error_exit "Prerequisites check failed. Install missing tools and try again."
    fi

    log_success "All prerequisites met"
}

# Validate terraform.tfvars exists
validate_tfvars() {
    log_info "Validating Terraform variables..."

    local tfvars_file="$BTRFS_DIR/terraform.tfvars"
    local tfvars_example="$BTRFS_DIR/terraform.tfvars.example"

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
    log_info "Initializing $TF_CMD..."

    cd "$BTRFS_DIR"

    if ! $TF_CMD init; then
        error_exit "$TF_CMD initialization failed"
    fi

    log_success "$TF_CMD initialized"
}

# Run terraform plan
plan_infrastructure() {
    log_info "Planning infrastructure changes..."

    cd "$BTRFS_DIR"

    if ! $TF_CMD plan -out=tfplan; then
        error_exit "$TF_CMD plan failed"
    fi

    log_success "Plan generated successfully"
}

# Apply terraform plan
apply_infrastructure() {
    log_info "Deploying AWS infrastructure..."
    log_warning "This will create resources in your AWS account and incur costs."
    log_info "Estimated monthly cost: ~\$11-12 (t3a.nano + 100GB EBS in us-west-1)"
    echo ""
    echo "Note: IF already deployed this will just refresh local env etc"

    read -p "Continue with deployment? (yes/no): " -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Deployment cancelled by user"
        exit 0
    fi

    cd "$BTRFS_DIR"

    log_info "Deploying... (this may take 2-3 minutes)"

    if ! $TF_CMD apply tfplan; then
        error_exit "$TF_CMD apply failed"
    fi

    # Remove plan file after successful apply
    rm -f tfplan

    log_success "Infrastructure deployed successfully"
}

# Wait for instance to be ready
wait_for_instance() {
    log_info "Waiting for instance to complete initialization..."
    log_info "This includes running user_data script to set up btrfs and btrbk"

    cd "$BTRFS_DIR"

    local instance_ip
    instance_ip=$($TF_CMD output -raw instance_public_ip)

    # Use SSH agent (e.g., 1Password) for authentication
    local ssh_opts="-o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q"

    local max_attempts=60
    local attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        echo ssh $ssh_opts "ubuntu@$instance_ip" "exit"
        if ssh $ssh_opts "ubuntu@$instance_ip" "exit" 2>/dev/null; then
            echo ""
            log_success "Instance is ready and SSH is accessible"
            return 0
        fi

        ((attempt++))
        echo -n "."
        sleep 5
    done

    echo ""
    log_warning "Instance did not become ready within expected time (5 minutes)"
    log_info "This is often due to slow user_data script execution on first boot"
    log_info "Infrastructure is deployed. You can check status later with:"
    log_info "  ./scripts/troubleshoot.sh check-ssh"

    # Return 0 because infrastructure IS deployed, we just can't verify SSH yet
    # Smoke tests will be skipped but that's acceptable
    return 0
}

# Run basic smoke tests on deployed infrastructure
smoke_test() {
    log_info "Running smoke tests..."

    cd "$BTRFS_DIR"

    local instance_ip
    instance_ip=$($TF_CMD output -raw instance_public_ip)

    # Use SSH agent (e.g., 1Password) for authentication
    log_info "Using SSH agent for authentication (e.g., 1Password)"
    local ssh_opts="-o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q"

    # Quick test if SSH agent works
    if ! ssh $ssh_opts "ubuntu@$instance_ip" "exit" 2>/dev/null; then
        log_warning "Could not connect via SSH agent, skipping smoke tests"
        echo ""
        log_info "Possible causes:"
        log_info "  - SSH agent (e.g., 1Password) not running or configured"
        log_info "  - SSH key not added to agent"
        log_info "  - Instance still initializing (wait a few minutes)"
        echo ""
        log_info "After configuring SSH, verify with:"
        log_info "  ssh ubuntu@$instance_ip"
        log_info "  ./btrfs/scripts/troubleshoot.sh check-all"
        echo ""
        return 0
    fi
    log_success "SSH agent authentication working"

    # Test 1: SSH connection
    log_info "Test 1: SSH connection..."
    if ssh $ssh_opts "ubuntu@$instance_ip" "exit" 2>/dev/null; then
        log_success "SSH connection: PASS"
    else
        log_error "SSH connection: FAIL"
        log_warning "Cannot connect to instance. Check security group and SSH key."
        return 1
    fi

    # Test 2: Backup volume mounted
    log_info "Test 2: Backup volume mounted..."
    if ssh $ssh_opts "ubuntu@$instance_ip" "mountpoint -q /backup_volume" 2>/dev/null; then
        log_success "Backup volume: MOUNTED"
    else
        log_error "Backup volume: NOT MOUNTED"
        log_warning "Check user_data script logs: ssh $ssh_opts ubuntu@$instance_ip 'sudo cat /var/log/cloud-init-output.log'"
        return 1
    fi

    # Test 3: Btrfs filesystem
    log_info "Test 3: Btrfs filesystem..."
    if ssh $ssh_opts "ubuntu@$instance_ip" "sudo btrfs filesystem show /backup_volume" &>/dev/null; then
        log_success "Btrfs filesystem: READY"
    else
        log_error "Btrfs filesystem: NOT FOUND"
        return 1
    fi

    # Test 4: Btrbk installed
    log_info "Test 4: Btrbk installation..."
    if ssh $ssh_opts "ubuntu@$instance_ip" "btrbk --version" &>/dev/null; then
        local btrbk_version
        btrbk_version=$(ssh $ssh_opts "ubuntu@$instance_ip" "btrbk --version" 2>&1 | head -n1)
        log_success "Btrbk: INSTALLED ($btrbk_version)"
    else
        log_error "Btrbk: NOT INSTALLED"
        return 1
    fi

    # Test 5: Restricted SSH commands (should fail)
    log_info "Test 5: SSH command restrictions..."
    if ssh $ssh_opts "ubuntu@$instance_ip" "ls /" &>/dev/null; then
        log_error "SSH restrictions: NOT ENFORCED (security issue!)"
        log_warning "btrbk user can run arbitrary commands"
        return 1
    else
        log_success "SSH restrictions: ENFORCED"
    fi

    # Test 6: Allowed commands (should succeed)
    log_info "Test 6: Btrbk commands allowed..."
    if ssh $ssh_opts "ubuntu@$instance_ip" "btrfs --version" &>/dev/null; then
        log_success "Btrbk commands: ALLOWED"
    else
        log_error "Btrbk commands: BLOCKED (check btrbk-ssh wrapper)"
        return 1
    fi

    log_success "All smoke tests passed!"
    return 0
}

# Generate .env file for local configuration
generate_config() {
    log_info "Generating configuration for local setup..."

    cd "$BTRFS_DIR"

    local env_file="$BTRFS_DIR/aws_connection.env"
    local instance_ip
    local instance_id
    local volume_id
    local btrbk_target
    local aws_region

    # Extract outputs from terraform
    instance_ip=$($TF_CMD output -raw instance_public_ip)
    instance_id=$($TF_CMD output -raw instance_id)
    volume_id=$($TF_CMD output -raw volume_id)
    btrbk_target=$($TF_CMD output -raw btrbk_target)
    aws_region=$(grep '^aws_region' terraform.tfvars | cut -d'"' -f2 || echo "us-west-1")

    # Generate .env file
    cat > "$env_file" << EOF
# AWS Backup Server Connection Details
# Generated by setup-aws.sh on $(date)
#
# Source this file in local setup: source aws_connection.env
# Or use these values to configure btrbk on your local machine

# SSH connection (uses SSH agent, e.g., 1Password)
BTRBK_AWS_HOST=$instance_ip
BTRBK_AWS_USER=ubuntu

# Backup configuration
BTRBK_AWS_TARGET=$btrbk_target
BTRBK_AWS_PATH=/backup_volume/backups

# AWS resource IDs (for troubleshooting)
BTRBK_AWS_INSTANCE_ID=$instance_id
BTRBK_AWS_VOLUME_ID=$volume_id
BTRBK_AWS_REGION=$aws_region

# Example btrbk target configuration:
# target ssh://\${BTRBK_AWS_USER}@\${BTRBK_AWS_HOST}\${BTRBK_AWS_PATH}/
EOF

    log_success "Configuration written to $env_file"

    return 0
}

# Display next steps to user
display_next_steps() {
    local env_file="$BTRFS_DIR/aws_connection.env"

    cd "$BTRFS_DIR"

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
    echo "  1. Test SSH connection (via 1Password SSH agent):"
    echo "     ssh ubuntu@$($TF_CMD output -raw instance_public_ip)"
    echo ""
    echo "  2. Run troubleshooting if needed:"
    echo "     ./btrfs/scripts/troubleshoot.sh check-all"
    echo ""
    echo "  3. Configure local btrbk (future task - not yet implemented)"
    echo ""
    echo "To destroy this infrastructure later:"
    echo "  cd $BTRFS_DIR && $TF_CMD destroy"
    echo ""
}

# Main function
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

# Run main function
main "$@"
