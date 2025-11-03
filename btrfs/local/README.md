# btrfs Backup Configuration

Multi-subvolume backup system using btrbk for backing up `/home/mjr` to AWS.

## Overview

This setup uses btrbk to manage btrfs snapshots and backups. Each directory under `/home/mjr` is converted to a btrfs subvolume and backed up independently with its own snapshot history and retention policy.

## Files

- **btrbk.conf** - Main btrbk configuration file
- **create-subvolumes.py** - Script to convert regular directories to btrfs subvolumes
- **snapshot-cleanup-hook.py** - Script to remove git-ignored files from snapshots
- **btrbk-with-cleanup.sh** - Wrapper script that runs btrbk with cleanup

## Quick Start

1. **Convert directories to subvolumes** (one-time setup):
   ```bash
   sudo ./create-subvolumes.py --dry-run  # preview changes
   sudo ./create-subvolumes.py             # actually convert
   ```

2. **Test the backup** (dry-run):
   ```bash
   ./btrbk-with-cleanup.sh -v -n run
   ```

3. **Run the backup**:
   ```bash
   sudo ./btrbk-with-cleanup.sh -v run
   ```

## Snapshot Cleanup

### The Problem

btrbk does **not** support exec hooks like `snapshot_create_exec`. The maintainer has explicitly rejected this feature due to security concerns (see [issue #58](https://github.com/digint/btrbk/issues/58)).

Originally, the config attempted to use:
```conf
snapshot_create_exec /path/to/snapshot-cleanup-hook.py  # This doesn't work!
```

This resulted in the error:
```
ERROR: Unknown option "snapshot_create_exec" in "btrbk.conf" line 52
```

### The Solution

We provide a **wrapper script** (`btrbk-with-cleanup.sh`) that:

1. Creates snapshots using btrbk
2. Runs the cleanup script on each snapshot while it's still writable
3. Continues with the backup process (sending to remote, etc.)

**Usage:**
```bash
# With cleanup (removes git-ignored files):
./btrbk-with-cleanup.sh -v run

# Without cleanup (faster, simpler):
btrbk -c btrfs/local/btrbk.conf -v run
```

### What Gets Cleaned Up?

The `snapshot-cleanup-hook.py` script removes git-ignored files from snapshots, including:
- `node_modules/` directories
- Build artifacts (`.o`, `.pyc`, etc.)
- Editor temporary files
- Any other files listed in `.gitignore`

This significantly reduces snapshot size for directories containing git repositories.

## Configuration Highlights

### Retention Policy

**Local snapshots:**
- Keep 14 daily, 8 weekly, 12 monthly snapshots
- Minimum: always keep latest

**Remote backups (AWS):**
- Keep 90 daily, 52 weekly, 120 monthly backups
- More aggressive retention to save on EBS costs

### Backed Up Subvolumes

Each of these directories is backed up independently:
- `code` - Source code repositories
- `Documents`, `Desktop`, `Templates` - Personal files
- `Pictures`, `Videos`, `Music` - Media libraries
- `.config`, `.mozilla` - Application configurations
- `.dev_sculptor`, `.sculptor` - Development tools
- `Dygma` - Keyboard configuration

## Common Operations

```bash
# Dry-run (always test first!)
./btrbk-with-cleanup.sh -v -n run

# Create local snapshots only (no remote backup)
btrbk -c btrfs/local/btrbk.conf -v snapshot

# Full backup (snapshot + send to remote)
./btrbk-with-cleanup.sh -v run

# List snapshots and backups
btrbk -c btrfs/local/btrbk.conf list snapshots
btrbk -c btrfs/local/btrbk.conf list backups

# Clean up old snapshots
btrbk -c btrfs/local/btrbk.conf clean
```

## Restoring from Backup

1. **List available backups:**
   ```bash
   ssh ubuntu@54.177.219.117 "sudo btrfs subvolume list /backup_volume/backups"
   ```

2. **Receive snapshot from remote:**
   ```bash
   ssh ubuntu@54.177.219.117 "sudo btrfs send /backup_volume/backups/home/mjr/code/code.20250103-1430" | \
     sudo btrfs receive /tmp/restore/
   ```

3. **Make snapshot writable:**
   ```bash
   sudo btrfs property set -ts /tmp/restore/code.20250103-1430 ro false
   ```

4. **Copy files to destination:**
   ```bash
   sudo rsync -av /tmp/restore/code.20250103-1430/ /home/mjr/code-restored/
   ```

5. **Clean up:**
   ```bash
   sudo btrfs subvolume delete /tmp/restore/code.20250103-1430
   ```

## Troubleshooting

### Verify subvolumes exist
```bash
sudo btrfs subvolume list /home
sudo btrfs subvolume show /home/mjr/code
```

### Check SSH access
```bash
ssh ubuntu@54.177.219.117 "sudo btrfs subvolume list /backup_volume"
```

### Debug btrbk
```bash
btrbk -c btrfs/local/btrbk.conf -v -l debug run
```

### Test btrfs send/receive locally
```bash
sudo btrfs subvolume snapshot -r /home/mjr/code /tmp/test-snapshot
sudo btrfs send /tmp/test-snapshot | sudo btrfs receive /tmp/test-receive/
```

## Architecture Notes

### Why Multi-Subvolume?

Each directory is a separate subvolume, providing:
- **Independent backup/restore** - Restore just one directory without affecting others
- **Efficient incremental backups** - Only changed data is transferred
- **Per-directory snapshots** - Different retention policies per directory
- **Granular control** - Back up or restore specific directories

### SSH Authentication

Uses 1Password SSH agent for authentication. Requires `SSH_AUTH_SOCK` environment variable to be set:
```bash
export SSH_AUTH_SOCK=~/.1password/agent.sock
```

### Compression

- **SSH compression**: Enabled (reduces bandwidth)
- **Stream compression**: xz (good compression, CPU-intensive)
- Alternative: lz4 (faster, less compression)

## References

- [btrbk GitHub](https://github.com/digint/btrbk)
- [btrbk documentation](https://digint.ch/btrbk/)
- [btrbk.conf man page](https://digint.ch/btrbk/doc/btrbk.conf.5.html)
- [Issue #58 - No exec hooks](https://github.com/digint/btrbk/issues/58)
