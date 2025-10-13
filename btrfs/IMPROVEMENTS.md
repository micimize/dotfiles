# btrfs-sync Infrastructure Improvements

## Summary of Changes

This document explains the major simplifications and fixes applied to the AWS infrastructure setup for the btrfs backup system.

## Problems Identified

1. **EBS Volume Timing Issue**: The user_data script ran immediately on instance boot, but the EBS volume attachment happened AFTER the instance was created. This created a race condition where the script would wait forever for `/dev/sdh` to appear.

2. **Device Naming Assumptions**: The code assumed the EBS volume would appear as `/dev/sdh`, but modern EC2 instances (like t3a.nano) use NVMe device naming (`/dev/nvme1n1`).

3. **No Logging/Debugging**: All setup logic was inline in Terraform with no way to see what went wrong if the user_data script failed.

4. **SSH Key Formatting**: The authorized_keys entry was being written with improper shell quoting, causing the SSH public key to be malformed.

5. **Limited Debugging Access**: If the btrbk user setup failed, there was no way to SSH into the instance to debug.

## Solutions Implemented

### 1. Externalized user_data Script

**File**: `btrfs/user-data.sh`

- Moved all inline bash from `btrbk_aws.tf` into a separate, maintainable script
- Added comprehensive logging to `/var/log/user-data.log`
- Each step logs with timestamps for easy debugging
- Script exits on error (`set -e`) and logs all output

### 2. Smart Device Detection

The new script automatically detects the EBS volume regardless of device naming:

```bash
# Look for NVMe devices first (modern instance types)
for dev in /dev/nvme*n1; do
    if [ -b "$dev" ]; then
        # Check if this device has no partitions and is not the root device
        if ! lsblk "$dev" -no MOUNTPOINT | grep -q '/' && ! lsblk "$dev" -no PKNAME | grep -q '.'; then
            # Check if device has no filesystem yet (brand new EBS volume)
            if ! blkid "$dev" > /dev/null 2>&1; then
                DEVICE="$dev"
                break
            fi
        fi
    fi
done

# Fallback: check traditional device naming
if [ -b "/dev/sdh" ]; then
    DEVICE="/dev/sdh"
fi
```

This handles both:
- Modern NVMe naming (`/dev/nvme1n1`)
- Traditional naming (`/dev/sdh`)

### 3. UUID-based Mounting

Instead of device names in `/etc/fstab` (which can change), we now use UUIDs:

```bash
UUID=$(blkid -s UUID -o value "$DEVICE")
echo "UUID=$UUID /backup_volume btrfs defaults 0 0" >> /etc/fstab
```

This ensures the volume is mounted correctly even if device names change between reboots.

### 4. Fixed SSH Key Format

Changed from problematic shell quoting:
```bash
# OLD (broken)
echo 'command="/usr/local/bin/btrbk-ssh" '${var.ssh_public_key} >> ...
```

To proper template substitution:
```bash
# NEW (working)
templatefile("${path.module}/user-data.sh", {
  ssh_authorized_keys_entry = "command=\"/usr/local/bin/btrbk-ssh\" ${var.ssh_public_key}"
})
```

### 5. Dual User Access

The infrastructure now provides two ways to access the instance:

1. **btrbk user**: For normal backup operations (command-restricted)
2. **ubuntu user**: For debugging and troubleshooting (full access via AWS key pair)

This means if the btrbk user setup fails, you can still SSH as ubuntu to investigate.

### 6. Enhanced Troubleshooting

New command in `troubleshoot.sh`:

```bash
./btrfs/scripts/troubleshoot.sh check-setup
```

This fetches the detailed user-data setup log, showing exactly what happened during instance initialization.

## Testing the Changes

### 1. Deploy Infrastructure

```bash
cd btrfs
tofu destroy -auto-approve  # Clean up old infrastructure
tofu apply
cd ..
```

### 2. Check Setup Progress

```bash
# Wait a minute for user_data to run, then:
./btrfs/scripts/troubleshoot.sh check-setup
```

You should see detailed logs showing each step of the setup process.

### 3. Verify SSH Access

```bash
# Test btrbk user
./btrfs/scripts/troubleshoot.sh check-ssh

# Or manually test ubuntu user for debugging
ssh ubuntu@<instance-ip>
sudo cat /var/log/user-data.log
```

### 4. Check Volume Status

```bash
./btrfs/scripts/troubleshoot.sh check-volume
```

## What to Look For

### Success Indicators

1. `/var/log/user-data.log` shows all 11 steps completed
2. `/var/lib/cloud/instance/user-data-finished` marker file exists
3. `/backup_volume` is mounted with btrfs filesystem
4. `/home/btrbk/.ssh/authorized_keys` exists with proper key
5. SSH connection to btrbk@<ip> works

### Common Issues

**Issue**: "EBS volume not found after 300s"
- **Cause**: Volume attachment hasn't happened yet
- **Fix**: AWS is slow, or there's an attachment problem
- **Debug**: Check `tofu show` output for volume attachment state

**Issue**: "Permission denied (publickey)" when connecting to btrbk
- **Cause**: authorized_keys file is malformed
- **Fix**: SSH as ubuntu and check `/home/btrbk/.ssh/authorized_keys`
- **Debug**: Look for proper format: `command="..." ssh-ed25519 AAAA...`

**Issue**: User-data script failed partway through
- **Cause**: Network issue, package installation failure, etc.
- **Fix**: Check `/var/log/user-data.log` for the exact error
- **Debug**: SSH as ubuntu and manually run failed commands

## Key Improvements Summary

| Aspect | Before | After |
|--------|--------|-------|
| **Device detection** | Hardcoded `/dev/sdh` | Smart NVMe/traditional detection |
| **Timing** | Race condition possible | Waits up to 5 minutes for volume |
| **Logging** | None (black box) | Detailed timestamped logs |
| **Debugging** | No access if btrbk failed | Ubuntu user always available |
| **Maintainability** | 80 lines inline bash | External script with comments |
| **SSH keys** | Broken quoting | Proper template substitution |
| **Mounting** | Device name in fstab | UUID-based mounting |

## Next Steps

After confirming the infrastructure deploys correctly:

1. Update `TESTING_GUIDE.md` with new troubleshooting steps
2. Test actual btrbk backup operations
3. Document the command-restricted SSH wrapper behavior
4. Create monitoring/alerting for backup failures
