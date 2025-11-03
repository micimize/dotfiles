#!/usr/bin/env bash
# Troubleshooting script for btrfs backup system
#
# Usage (from repo root): ./btrfs/scripts/troubleshoot.sh <command>
#
# Commands:
#   check-ssh          Test SSH connectivity to backup server
#   check-volume       Check backup volume status and space
#   check-aws          Verify AWS resources are running
#   check-logs         View remote system logs
#   check-setup        View detailed user-data setup log
#   check-all          Run all checks
#   help               Show this help message

set -euo pipefail

# Determine repo root and btrfs directory
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BTRFS_DIR="$REPO_ROOT/btrfs"

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
    local env_file="$BTRFS_DIR/aws_connection.env"

    if [[ ! -f "$env_file" ]]; then
        log_error "Configuration file not found: $env_file"
        log_info "Run ./btrfs/scripts/setup-aws.sh first to deploy infrastructure"
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

# Get SSH connection command (uses SSH agent, e.g., 1Password)
get_ssh_cmd() {
    echo "ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${BTRBK_AWS_USER}@${BTRBK_AWS_HOST}"
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
  check-setup        View detailed user-data setup log
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

# Check SSH connectivity
cmd_check_ssh() {
    local ssh_cmd
    ssh_cmd=$(get_ssh_cmd)
    log_info "Checking SSH connectivity... ($ssh_cmd)"

    # Test basic connectivity
    if $ssh_cmd "exit" 2>/dev/null; then
        log_success "SSH connection: OK"
    else
        log_error "SSH connection: FAILED"
        log_info "Troubleshooting steps:"
        log_info "  1. Check instance is running: aws ec2 describe-instances --instance-ids ${BTRBK_AWS_INSTANCE_ID}"
        log_info "  2. Check security group allows SSH from your IP"
        log_info "  3. Verify SSH agent has key: ssh-add -l"
        log_info "  4. Try manual connection: $ssh_cmd"
        return 1
    fi

    # Test ubuntu user
    local remote_user
    remote_user=$($ssh_cmd "whoami" 2>/dev/null || echo "unknown")

    if [[ "$remote_user" == "ubuntu" ]]; then
        log_success "Connected as ubuntu user: OK"
    else
        log_error "Connected as unexpected user: $remote_user"
        return 1
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
        backup_count=$($ssh_cmd "find /backup_volume/backups -type d -maxdepth 2 2>/dev/null | wc -l" || echo "0")
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

# Check detailed user-data setup log
cmd_check_setup() {
    log_info "Fetching detailed user-data setup log..."

    local ssh_cmd
    ssh_cmd=$(get_ssh_cmd)

    # Try to connect to ubuntu user first (btrbk user might not be set up yet)
    local ubuntu_ssh="ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@${BTRBK_AWS_HOST}"

    log_info "User-data setup log:"
    echo "========================================"
    if $ubuntu_ssh "sudo cat /var/log/user-data.log" 2>/dev/null; then
        echo "========================================"
        log_success "Setup log retrieved successfully"
    else
        log_warning "Could not fetch user-data.log (may not exist yet or SSH as ubuntu failed)"
        log_info "Trying cloud-init-output.log instead..."
        echo "========================================"
        $ssh_cmd "sudo cat /var/log/cloud-init-output.log" 2>/dev/null || log_error "Could not fetch any logs"
        echo "========================================"
    fi

    # Check if setup completed
    if $ubuntu_ssh "test -f /var/lib/cloud/instance/user-data-finished" 2>/dev/null; then
        log_success "User-data script completed successfully"
    else
        log_warning "User-data script may still be running or failed"
    fi

    return 0
}

# Run all checks
cmd_check_all() {
    log_info "Running all checks..."
    echo ""

    local all_passed=0

    cmd_check_ssh || all_passed=1
    echo ""
    cmd_check_volume || all_passed=1
    echo ""
    cmd_check_aws || all_passed=1
    echo ""
    cmd_check_logs

    echo ""
    if [[ $all_passed -eq 0 ]]; then
        log_success "All checks passed!"
    else
        log_warning "Some checks failed. Review output above."
    fi

    return $all_passed
}

# Main
main() {
    local command="${1:-help}"

    case "$command" in
        check-ssh)
            load_config
            cmd_check_ssh
            ;;
        check-setup)
            load_config
            cmd_check_setup
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
