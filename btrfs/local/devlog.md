# Local btrbk Configuration - Development Log

## Overview

This document tracks the implementation of local btrbk configuration for backing up `/home/mjr` to AWS.

## Context

**What we're building**: A btrbk configuration that backs up the user's home directory to the AWS EC2 instance we already provisioned, with complex exclusion rules.

**Why it's complex**: The user wants to back up `/home/mjr` but exclude many common patterns (node_modules, .venv, cache directories, git-ignored files, etc.). btrbk doesn't natively support complex exclusions, so we need a solution.

**Prerequisites completed**:
- ✅ AWS infrastructure deployed (EC2 instance + encrypted EBS volume)
- ✅ btrfs filesystem mounted at `/backup_volume/backups` on remote
- ✅ SSH authentication working via 1Password agent
- ✅ Connection details in `btrfs/aws_connection.env`

## Requirements

### What to Back Up
- **Source**: `/home/mjr` (entire home directory)

### What to Exclude
1. Environment/dependency directories:
   - `.env` files
   - `.venv` directories (Python virtual environments)
   - `*secret*` (any file/dir with "secret" in name)
   - `node_modules` (JavaScript dependencies)

2. Cache and temporary data:
   - `$HOME/.var`
   - `$HOME/.cache`
   - `$HOME/.local`

3. Sensitive data:
   - `$HOME/.aws` (AWS credentials)

4. Other exclusions:
   - `$HOME/old_backup`
   - Git-ignored files within git repositories

### Technical Constraints

**btrbk limitation**: btrbk operates on btrfs subvolumes, not arbitrary directories. It doesn't have built-in exclusion support.

**btrfs send/receive limitation**: These operations work at the subvolume level and transfer everything in the subvolume. You can't exclude files during send/receive.

## Solution Approaches

### Option 1: Subvolume per Directory (NOT RECOMMENDED)
Create separate btrfs subvolumes for major directories under `/home/mjr`:
- `/home/mjr/code` → subvolume
- `/home/mjr/Documents` → subvolume
- etc.

**Pros**:
- Native btrbk support
- Clean snapshot management

**Cons**:
- **Major restructuring** of existing filesystem
- Requires copying/moving all data
- User has to decide upfront what directories to make subvolumes
- Complex to maintain

### Option 2: Single Subvolume + Pre-backup Exclusion Script (RECOMMENDED)
Make `/home/mjr` a single btrfs subvolume, but use a pre-backup script to:
1. Create temporary copies excluding unwanted files
2. Snapshot the cleaned data
3. Clean up temporary data

**Pros**:
- Works with existing directory structure
- Flexible exclusion rules
- Can use rsync/find for complex patterns

**Cons**:
- Extra disk space needed during backup (for temporary copy)
- More complex scripting
- Slower (needs to copy data first)

### Option 3: Wrapper Script with Bind Mounts (HYBRID)
Use Linux bind mounts to create a temporary view of the filesystem with exclusions applied.

**Pros**:
- No data copying
- Fast
- Flexible

**Cons**:
- Very complex to implement correctly
- Bind mount limitations with btrfs subvolumes

### Option 4: Backup Everything, Restore Selectively (SIMPLEST)
Back up the entire `/home/mjr` subvolume without exclusions. When restoring, use rsync with exclusions.

**Pros**:
- **Simplest implementation**
- No pre-backup complexity
- Can always restore everything if needed

**Cons**:
- **Wastes storage** on unnecessary files (node_modules, caches, etc.)
- Slower backups (more data to transfer)
- More expensive (more EBS storage)

### Option 5: Git-aware Selective Backup (PRACTICAL MIDDLE GROUND)
For each important directory (like `~/code`), create a dedicated subvolume. Use a script that:
1. Identifies git repositories
2. Uses `.gitignore` rules to exclude files
3. Excludes common patterns (node_modules, .venv, etc.)
4. Creates rsync-based "views" into temporary subvolumes for backup

**Pros**:
- Respects developer workflows (.gitignore)
- Reduces storage significantly
- More targeted approach

**Cons**:
- More complex than Option 4
- Requires identifying which directories matter most

## Recommended Approach: Option 5 (Git-aware Selective Backup)

### High-Level Plan

1. **Identify backup targets**: Determine which subdirectories under `/home/mjr` should be backed up as separate units (e.g., `~/code`, `~/Documents`)

2. **Create btrfs subvolumes**: For each target, create a dedicated subvolume
   ```bash
   btrfs subvolume create /home/mjr/.btrbk-staging/code
   btrfs subvolume create /home/mjr/.btrbk-staging/documents
   ```

3. **Pre-backup sync script**: Before btrbk runs, sync data with exclusions
   ```bash
   rsync -a --delete \
     --exclude='.env' \
     --exclude='.venv' \
     --exclude='*secret*' \
     --exclude='node_modules' \
     --exclude='.var' \
     --exclude='.cache' \
     --exclude='.local' \
     --exclude='.aws' \
     --exclude='old_backup' \
     --filter=':- .gitignore' \
     /home/mjr/code/ \
     /home/mjr/.btrbk-staging/code/
   ```

4. **btrbk configuration**: Configure btrbk to snapshot the staging subvolumes
   ```
   subvolume /home/mjr/.btrbk-staging/code
     snapshot_dir .snapshots
     target ssh://ubuntu@<aws-ip>/backup_volume/backups/
   ```

5. **Systemd timer**: Automate with systemd timer that:
   - Runs pre-backup sync
   - Runs btrbk
   - Cleans up old snapshots

### Implementation Checklist

- [ ] **Task 1**: Create staging subvolumes script
  - Script: `btrfs/local/create-staging-subvolumes.sh`
  - Creates `.btrbk-staging/` directory under `/home/mjr`
  - Creates subvolumes for each backup target

- [ ] **Task 2**: Create pre-backup sync script
  - Script: `btrfs/local/pre-backup-sync.sh`
  - Reads exclusion patterns from config file
  - Syncs each source → staging subvolume with rsync
  - Handles git-aware exclusions

- [ ] **Task 3**: Create btrbk configuration
  - File: `btrfs/local/btrbk.conf`
  - Uses staging subvolumes as source
  - Targets AWS EC2 instance
  - Sets retention policies

- [ ] **Task 4**: Test manual backup
  - Run sync script manually
  - Run btrbk manually with dry-run
  - Verify snapshots created locally and remotely

- [ ] **Task 5**: Create systemd service and timer
  - Service: `btrfs/local/btrbk-backup.service`
  - Timer: `btrfs/local/btrbk-backup.timer`
  - Runs daily at specified time

- [ ] **Task 6**: Documentation
  - Update `btrfs/local/README.md`
  - Document how to add/remove backup targets
  - Document how to modify exclusions
  - Document restore procedures

## Alternative: Simpler "Backup Important Directories Only" Approach

If the user wants to start simpler, we could:

1. **Backup only `~/code`** (most important)
2. **Check if `/home/mjr/code` is already a subvolume**:
   ```bash
   btrfs subvolume show /home/mjr/code
   ```
3. **If not, make it a subvolume**:
   ```bash
   # Requires moving data temporarily
   mv /home/mjr/code /home/mjr/code.tmp
   btrfs subvolume create /home/mjr/code
   rsync -a /home/mjr/code.tmp/ /home/mjr/code/
   rm -rf /home/mjr/code.tmp
   ```
4. **Configure btrbk for just that subvolume**

This is much simpler but only backs up one directory.

## Questions for User

1. **Storage constraints**: How much space are we willing to use for staging copies?
2. **Backup targets**: Besides `~/code`, what other directories are critical?
3. **Frequency**: How often should backups run? Daily? Hourly?
4. **Complexity tolerance**: Prefer simpler (backup less) or complex (backup more with exclusions)?

## Next Steps

1. ✅ Create this devlog
2. Wait for user input on preferred approach
3. Implement chosen approach
4. Test and iterate

## Notes

- The user's system is entirely on btrfs (confirmed earlier)
- 1Password SSH agent is working for remote connections
- Remote server has btrbk installed and ready
- Current `btrfs/btrbk_config` is just a template, not actively used
