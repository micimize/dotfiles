#!/bin/bash
# User data script for btrbk backup target EC2 instance
# This script runs on first boot via cloud-init

set -e  # Exit on error
exec > >(tee -a /var/log/user-data.log)
exec 2>&1

echo "=== Starting btrbk backup target setup at $$(date) ==="

# Function to log with timestamp
log() {
    echo "[$$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "Step 1: Waiting for EBS volume to be attached..."
# Wait for the EBS volume to appear. On modern instances (t3a), AWS maps /dev/sdh to NVMe devices.
# We need to find the volume by checking for an unpartitioned block device that's not the root volume.
MAX_WAIT=300  # 5 minutes
ELAPSED=0
DEVICE=""

while [ $ELAPSED -lt $MAX_WAIT ]; do
    # Look for NVMe devices first (modern instance types)
    for dev in /dev/nvme*n1; do
        if [ -b "$dev" ]; then
            # Check if this device has no partitions and is not the root device
            if ! lsblk "$dev" -no MOUNTPOINT | grep -q '/' && ! lsblk "$dev" -no PKNAME | grep -q '.'; then
                # Check if device has no filesystem yet (brand new EBS volume)
                if ! blkid "$dev" > /dev/null 2>&1; then
                    DEVICE="$dev"
                    log "Found new EBS volume at $DEVICE (NVMe)"
                    break 2
                fi
            fi
        fi
    done

    # Fallback: check traditional device naming
    if [ -b "/dev/sdh" ]; then
        DEVICE="/dev/sdh"
        log "Found EBS volume at $DEVICE (traditional naming)"
        break
    fi

    sleep 2
    ELAPSED=$$((ELAPSED + 2))
done

if [ -z "$DEVICE" ]; then
    log "ERROR: EBS volume not found after $${MAX_WAIT}s. Available block devices:"
    lsblk
    exit 1
fi

log "Step 2: Installing required packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq btrfs-progs btrbk

log "Step 3: Formatting EBS volume with btrfs..."
mkfs.btrfs -f "$DEVICE"

log "Step 4: Creating mount point and mounting volume..."
mkdir -p /backup_volume
mount "$DEVICE" /backup_volume

log "Step 5: Adding volume to /etc/fstab for persistent mounting..."
# Get the UUID of the device for more reliable mounting
UUID=$$(blkid -s UUID -o value "$DEVICE")
echo "UUID=$UUID /backup_volume btrfs defaults 0 0" >> /etc/fstab

log "Step 6: Creating backup directory structure..."
mkdir -p /backup_volume/backups
chmod 755 /backup_volume/backups

log "Step 7: Creating btrbk user..."
useradd -m -s /bin/bash btrbk

log "Step 8: Setting up SSH for btrbk user..."
mkdir -p /home/btrbk/.ssh
touch /home/btrbk/.ssh/authorized_keys
chown -R btrbk:btrbk /home/btrbk
chmod 700 /home/btrbk/.ssh
chmod 600 /home/btrbk/.ssh/authorized_keys

log "Step 9: Adding SSH public key with command restriction..."
# The public key will be added by Terraform via template substitution
cat << 'SSH_KEY_MARKER' >> /home/btrbk/.ssh/authorized_keys
${ssh_authorized_keys_entry}
SSH_KEY_MARKER

log "Step 10: Creating btrbk-ssh wrapper script..."
cat << 'WRAPPER_SCRIPT' > /usr/local/bin/btrbk-ssh
#!/bin/bash
# SSH command wrapper that restricts what commands can be executed
# Only allows btrfs and btrbk commands needed for backup operations

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
WRAPPER_SCRIPT

chmod +x /usr/local/bin/btrbk-ssh

log "Step 11: Giving btrbk user permissions on backup volume..."
chown -R btrbk:btrbk /backup_volume/backups

log "=== Setup completed successfully at $$(date) ==="
log "Device: $DEVICE"
log "UUID: $UUID"
log "Mount point: /backup_volume"
log "Backup directory: /backup_volume/backups"

# Write completion marker
touch /var/lib/cloud/instance/user-data-finished
