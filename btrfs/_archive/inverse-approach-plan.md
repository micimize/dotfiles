# Inverse Approach: Backup Entire Home, Remove Excluded Directories

## Executive Summary

**Proposed Approach**: Instead of creating multiple subvolumes for specific directories, backup the entire `/home/mjr` as a single subvolume and use an enhanced snapshot cleanup hook to remove directories NOT in a configured inclusion list.

**Key Insight**: This inverts the current approach from "backup these specific subvolumes" to "backup everything except these exclusions."

**Result**: Eliminates all cross-subvolume boundary issues (trash, hard links, renames, etc.) while maintaining efficient backups via btrfs CoW.

## Conceptual Analysis

### How This Would Work

1. **Single Subvolume**: `/home/mjr` is already or becomes a single btrfs subvolume
2. **Snapshot Creation**: btrbk creates writable snapshot of entire home directory
3. **Hook Execution**: Enhanced cleanup hook runs and:
   - Reads inclusion list from config (code, Documents, Pictures, etc.)
   - Removes ALL top-level directories NOT in inclusion list
   - Applies git-ignore cleanup to remaining directories (existing functionality)
4. **Finalization**: btrbk makes snapshot read-only and sends to AWS

### Efficiency Considerations

**Question**: Is this efficient given btrfs CoW?

**Answer**: YES, with important caveats.

#### Why It's Efficient (Space)

1. **Snapshot Creation**: Instant and zero-copy due to CoW
   - btrbk creates snapshot → metadata operation only
   - All file data is initially shared between original and snapshot
   - Disk usage increase: ~0 MB (just metadata)

2. **Directory Removal from Snapshot**: Efficient
   - Removing directories from snapshot doesn't affect original
   - Removal just decrements reference counts on extents
   - No data is actually copied or moved
   - Disk usage change: Minimal (just metadata updates)

3. **Final Snapshot Size**: Only includes desired directories
   - When sent to AWS, only included directories are transmitted
   - Local snapshot shares most data with live filesystem via CoW
   - Storage savings: Significant compared to backing up everything

#### Why It Might Be Inefficient (Performance)

1. **Removal Operations**: Can be slow for large directory trees
   - btrfs-cleaner must update metadata for every file removed
   - Removing node_modules, .cache, etc. could involve millions of files
   - Performance impact: Seconds to minutes per snapshot
   - BUT: This is one-time cost during snapshot, not ongoing

2. **Reference Counting**: Extra metadata overhead
   - Every excluded file adds metadata operations during removal
   - More complex than never snapshotting them at all
   - Impact: Modest CPU/IO during snapshot creation

3. **Snapshot Retention**: More local disk usage than current approach
   - With multiple subvolumes: Each has its own snapshot history
   - With single subvolume: All snapshot history shares one namespace
   - Risk: If retention is high, more metadata complexity
   - Mitigation: Aggressive local retention policy (keep fewer snapshots)

### Comparison to Current Approach

| Aspect | Multiple Subvolumes (Current) | Single Subvolume + Exclusions (Proposed) |
|--------|-------------------------------|------------------------------------------|
| **Usability** | ❌ Breaks trash, hard links, renames | ✅ Normal filesystem behavior |
| **Setup Complexity** | ❌ Must convert directories to subvolumes | ✅ Simpler: one subvolume |
| **Maintenance** | ❌ Must manage multiple subvolume configs | ✅ Simple inclusion list |
| **Snapshot Speed** | ✅ Fast (small subvolumes) | ⚠️  Moderate (removal overhead) |
| **Backup Size** | ✅ Minimal (only included dirs) | ✅ Same (only included dirs sent) |
| **Local Disk Usage** | ✅ Lower (separate snapshot histories) | ⚠️  Slightly higher (single history) |
| **Flexibility** | ❌ Must redefine subvolumes to change | ✅ Edit config file |
| **Restore Process** | ⚠️  Complex (multiple subvolumes) | ✅ Simple (single snapshot) |
| **Application Compatibility** | ❌ Many issues documented | ✅ No issues |

**Verdict**: Proposed approach trades modest performance/storage overhead for major usability gains.

## Technical Implementation Plan

### Phase 1: Analysis and Preparation

#### 1.1 Verify Current State

```bash
# Check if /home/mjr is already a subvolume
btrfs subvolume show /home/mjr

# Check existing subvolumes under /home/mjr
btrfs subvolume list /home/mjr

# Estimate sizes to understand what we're working with
du -sh /home/mjr/*
du -sh /home/mjr/.* 2>/dev/null | grep -v "^0"
```

**Expected outcome**:
- Determine if /home/mjr is a subvolume
- Identify any nested subvolumes that need handling
- Understand size distribution

#### 1.2 Design Inclusion Configuration

Create a simple config format for the hook to read:

```python
# btrfs/local/backup-inclusion-list.conf
# Directories to INCLUDE in backups (all others will be removed from snapshots)
# One directory per line, relative to /home/mjr

code
Dygma
Documents
Desktop
Templates
Pictures
Public
Videos
Music
.config
.dev_sculptor
.sculptor
.mozilla
```

**Rationale**: Simple text file, easy to edit, version controllable.

### Phase 2: Hook Enhancement

#### 2.1 Enhanced Hook Design

Modify `snapshot-cleanup-hook.py` to:

1. **Read inclusion list** from config file
2. **Identify top-level directories** in snapshot
3. **Remove directories NOT in inclusion list** (inverse of current)
4. **Apply git-ignore cleanup** to remaining directories (existing)

#### 2.2 Critical Design Decisions

**Q: What level to apply exclusions?**
- Top-level directories only (e.g., remove entire `Downloads/`, `.cache/`)
- Recursive patterns (e.g., remove all `node_modules/` anywhere)

**A: Top-level only (simpler, more predictable)**

**Q: What about dot-files at top level?**
- Include everything by default?
- Require explicit inclusion (e.g., `.bashrc`, `.vimrc`)?

**A: Separate handling**
- Remove ALL top-level directories not in inclusion list
- Keep ALL top-level regular files (config files like .bashrc, .profile, etc.)
- This preserves user configs while excluding bulk data

**Q: What about symlinks?**
- Remove if target not in inclusion list?
- Keep all symlinks?

**A: Keep all symlinks** (they're tiny, and removal is complex)

**Q: How to handle nested subvolumes?**
- `.snapshots/` directories from btrbk
- Docker volumes, VMs, etc.

**A: Skip them** (btrfs won't let you remove nested subvolumes easily)

#### 2.3 Functional Design

```python
@dataclass(frozen=True)
class BackupConfig:
    included_directories: tuple[str, ...]

def read_inclusion_list_from_config(config_path: Path) -> tuple[str, ...]:
    """Read and parse inclusion list config file."""
    with open(config_path) as f:
        return tuple(
            line.strip()
            for line in f
            if line.strip() and not line.startswith('#')
        )

def get_top_level_directory_names_from_snapshot(snapshot_path: Path) -> tuple[str, ...]:
    """Get all top-level directory names in snapshot."""
    return tuple(
        item.name
        for item in snapshot_path.iterdir()
        if item.is_dir()
    )

def calculate_directories_to_remove(
    all_directories: tuple[str, ...],
    included_directories: tuple[str, ...]
) -> tuple[str, ...]:
    """Return directories that should be removed (inverse of inclusion list)."""
    included_set = set(included_directories)
    return tuple(
        dirname
        for dirname in all_directories
        if dirname not in included_set and dirname != '.snapshots'  # Never remove btrbk snapshots
    )

def remove_directory_from_snapshot(snapshot_path: Path, dirname: str) -> bool:
    """Remove a directory from snapshot, return success status."""
    dir_path = snapshot_path / dirname
    try:
        if dir_path.is_symlink():
            # Don't follow symlinks, just remove the link itself
            dir_path.unlink()
            logger.info(f"    Removed symlink: {dirname}")
            return True

        # Check if it's a nested subvolume
        result = subprocess.run(
            ('btrfs', 'subvolume', 'show', str(dir_path)),
            capture_output=True,
            stderr=subprocess.DEVNULL
        )
        if result.returncode == 0:
            # It's a subvolume, skip it
            logger.warning(f"    Skipping nested subvolume: {dirname}")
            return False

        # Regular directory, remove it
        shutil.rmtree(dir_path)
        logger.info(f"    Removed directory: {dirname}")
        return True

    except Exception as e:
        logger.error(f"    Error removing {dirname}: {e}")
        return False

def remove_excluded_directories_from_snapshot(
    snapshot_path: Path,
    config: BackupConfig
) -> int:
    """Remove all directories NOT in inclusion list, return count removed."""
    logger.info("  Removing excluded directories...")

    all_dirs = get_top_level_directory_names_from_snapshot(snapshot_path)
    dirs_to_remove = calculate_directories_to_remove(all_dirs, config.included_directories)

    if not dirs_to_remove:
        logger.info("    No directories to remove")
        return 0

    logger.info(f"    Found {len(dirs_to_remove)} directories to remove")

    removed_count = 0
    for dirname in dirs_to_remove:
        if remove_directory_from_snapshot(snapshot_path, dirname):
            removed_count += 1

    logger.info(f"    Removed {removed_count} directories")
    return removed_count

def clean_snapshot_with_inverse_approach(
    snapshot_path: Path,
    config: BackupConfig
) -> tuple[int, int]:
    """
    Clean snapshot using inverse approach:
    1. Remove directories NOT in inclusion list
    2. Remove git-ignored files from remaining directories

    Returns: (directories_removed, git_ignored_items_removed)
    """
    if not snapshot_path.exists():
        raise ValueError(f"Snapshot path does not exist: {snapshot_path}")

    if not snapshot_path.is_dir():
        raise ValueError(f"Snapshot path is not a directory: {snapshot_path}")

    logger.info(f"Cleaning snapshot (inverse approach): {snapshot_path}")

    # Phase 1: Remove excluded directories
    dirs_removed = remove_excluded_directories_from_snapshot(snapshot_path, config)

    # Phase 2: Remove git-ignored files from included directories (existing logic)
    git_items_removed = remove_git_ignored_files_from_remaining_directories(snapshot_path)

    logger.info(f"Cleanup complete: {snapshot_path}")
    logger.info(f"  Directories removed: {dirs_removed}")
    logger.info(f"  Git-ignored items removed: {git_items_removed}")

    return dirs_removed, git_items_removed
```

### Phase 3: Migration from Current Setup

#### 3.1 Revert Subvolumes to Regular Directories

**CRITICAL**: This is the dangerous part. Must be done carefully.

**Strategy**: Use the existing `~/migrating_to_subvolumes/` backup as safety net.

```bash
#!/bin/bash
# btrfs/local/revert-subvolumes-to-directories.sh

set -e

BACKUP_BASE="$HOME/migrating_to_subvolumes"

# List of directories that were converted to subvolumes
SUBVOLUMES=(
    "code"
    "Dygma"
    "Documents"
    "Desktop"
    "Templates"
    "Pictures"
    "Public"
    "Videos"
    "Music"
    ".config"
    ".dev_sculptor"
    ".sculptor"
    ".mozilla"
)

echo "This script will revert subvolumes back to regular directories"
echo "WARNING: This modifies your home directory structure"
echo ""
echo "Prerequisites:"
echo "  1. Backup exists in $BACKUP_BASE"
echo "  2. You have sudo access"
echo "  3. No critical applications are running"
echo ""
read -p "Continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted"
    exit 1
fi

for subvol in "${SUBVOLUMES[@]}"; do
    subvol_path="$HOME/$subvol"
    backup_path="$BACKUP_BASE/$subvol"

    echo ""
    echo "Processing: $subvol"

    # Check if it's actually a subvolume
    if ! sudo btrfs subvolume show "$subvol_path" &>/dev/null; then
        echo "  Not a subvolume, skipping"
        continue
    fi

    # Check if backup exists
    if [ ! -d "$backup_path" ]; then
        echo "  ERROR: No backup found at $backup_path"
        echo "  Skipping for safety"
        continue
    fi

    # Create temporary name
    temp_path="${subvol_path}.reverting"

    echo "  1. Moving subvolume to temporary location..."
    sudo mv "$subvol_path" "$temp_path"

    echo "  2. Deleting subvolume..."
    sudo btrfs subvolume delete "$temp_path"

    echo "  3. Creating regular directory..."
    mkdir "$subvol_path"

    echo "  4. Restoring content from backup..."
    cp -a "$backup_path/." "$subvol_path/"

    echo "  ✓ Reverted $subvol to regular directory"
done

echo ""
echo "Reversion complete!"
echo "Verify everything works, then you can delete $BACKUP_BASE"
```

**Safety Features**:
- Uses existing backups in `~/migrating_to_subvolumes/`
- Processes one directory at a time
- Checks for backups before proceeding
- User confirmation required

#### 3.2 Ensure /home/mjr is a Subvolume

```bash
# Check if /home/mjr is a subvolume
if ! btrfs subvolume show /home/mjr &>/dev/null; then
    echo "ERROR: /home/mjr is not a btrfs subvolume"
    echo "This is required for btrbk to work"
    echo ""
    echo "Your /home/mjr needs to be converted to a subvolume first."
    echo "This is complex and should be done with expert guidance."
    exit 1
fi
```

**Note**: If `/home/mjr` is NOT a subvolume, conversion is complex:
- Requires moving all data out
- Creating subvolume
- Moving data back
- Updating `/etc/fstab` if needed
- This is beyond scope of automated script - needs manual intervention

#### 3.3 Update btrbk Configuration

```bash
# btrfs/local/btrbk.conf (new version)

timestamp_format        long
snapshot_preserve_min   latest
snapshot_preserve       14d 8w 12m
target_preserve_min     latest
target_preserve         7d 4w 6m
snapshot_dir            .snapshots
snapshot_create_always  yes

# Enhanced snapshot cleanup hook
# Removes directories NOT in inclusion list, then removes git-ignored files
snapshot_create_exec /home/mjr/code/personal/dotfiles/btrfs/local/snapshot-cleanup-hook.py

backend btrfs-progs-sudo
ssh_identity            /dev/null
ssh_user                ubuntu
ssh_compression         yes
stream_compress         xz

# Single subvolume: entire home directory
volume /home/mjr
  snapshot_dir            .snapshots
  target ssh://ubuntu@54.177.219.117/backup_volume/backups/home/

  # No individual subvolume declarations - just backup the whole thing
  # The hook will handle exclusions
```

**Key change**: No more `subvolume` lines. Just `volume /home/mjr`.

### Phase 4: Testing Strategy

#### 4.1 Dry-Run Testing

```bash
# Test hook in isolation (if possible)
# Would need to create a test snapshot manually

# Create a test subvolume
sudo btrfs subvolume create /tmp/test-home
cp -a ~/Documents /tmp/test-home/
cp -a ~/Downloads /tmp/test-home/  # This should be removed
mkdir -p /tmp/test-home/code/.git
echo "node_modules/" > /tmp/test-home/code/.gitignore
mkdir /tmp/test-home/code/node_modules

# Create snapshot
sudo btrfs subvolume snapshot /tmp/test-home /tmp/test-home-snapshot

# Test hook
SNAPSHOT_SUBVOLUME_PATH=/tmp/test-home-snapshot \
  ./btrfs/local/snapshot-cleanup-hook.py

# Verify:
# - Downloads/ removed? (not in inclusion list)
# - Documents/ present? (in inclusion list)
# - code/node_modules/ removed? (git-ignored)

# Cleanup
sudo btrfs subvolume delete /tmp/test-home-snapshot
sudo btrfs subvolume delete /tmp/test-home
```

#### 4.2 btrbk Dry-Run

```bash
# Test btrbk with new config (dry-run)
sudo btrbk -c btrfs/local/btrbk.conf -v -n run

# Expected output:
# - Creates snapshot of /home/mjr
# - Runs cleanup hook
# - Shows what would be sent to AWS
# - Doesn't actually send anything (-n flag)
```

#### 4.3 Local-Only Test

```bash
# Test local snapshot only (no AWS transfer)
# Temporarily remove 'target' line from btrbk.conf

sudo btrbk -c btrfs/local/btrbk.conf -v run

# Verify:
ls -la /home/mjr/.snapshots/
# Should see new snapshot

# Check snapshot contents
ls /home/mjr/.snapshots/<snapshot-name>/
# Should NOT contain excluded directories
# Should contain included directories
# Should NOT contain git-ignored files in repos

# Check sizes
sudo btrfs filesystem du -s /home/mjr/.snapshots/<snapshot-name>/
du -sh /home/mjr/.snapshots/<snapshot-name>/
```

#### 4.4 Full Test with AWS

```bash
# Re-enable 'target' in btrbk.conf
# Run actual backup
sudo btrbk -c btrfs/local/btrbk.conf -v run

# Verify remote
ssh ubuntu@54.177.219.117 "sudo btrfs subvolume list /backup_volume/backups/"

# Check remote size
ssh ubuntu@54.177.219.117 "sudo btrfs filesystem du -s /backup_volume/backups/home/<snapshot-name>/"
```

### Phase 5: Edge Cases and Pitfalls

#### 5.1 Nested Subvolumes

**Pitfall**: If you have nested subvolumes (e.g., Docker volumes, VMs), they won't be included in the parent snapshot.

**Example**:
```bash
# If /home/mjr/libvirt is a subvolume, it won't be captured
btrfs subvolume show /home/mjr/libvirt
```

**Solution**:
- Document: Nested subvolumes are NOT backed up by this approach
- Alternative: Backup nested subvolumes separately with additional btrbk configs
- Detection: Hook should detect and warn about nested subvolumes

**Implementation**:
```python
def detect_nested_subvolumes(base_path: Path) -> tuple[Path, ...]:
    """Detect any nested subvolumes within base_path."""
    nested = []
    for item in base_path.rglob('*'):
        if item.is_dir():
            result = subprocess.run(
                ('btrfs', 'subvolume', 'show', str(item)),
                capture_output=True,
                stderr=subprocess.DEVNULL
            )
            if result.returncode == 0 and item != base_path:
                nested.append(item)
    return tuple(nested)

# In hook main():
nested = detect_nested_subvolumes(snapshot_path)
if nested:
    logger.warning("WARNING: Nested subvolumes detected (will NOT be backed up):")
    for subvol in nested:
        logger.warning(f"  - {subvol.relative_to(snapshot_path)}")
```

#### 5.2 Large Excluded Directories

**Pitfall**: Removing very large directories (e.g., `.cache` with 10GB, `.local` with 5GB) can take significant time.

**Impact**:
- Snapshot creation takes longer
- More CPU/IO during backup
- Could slow down system if btrbk runs during active use

**Mitigation**:
- Run backups during low-activity periods (systemd timer)
- Monitor hook execution time
- Consider reducing retention to minimize frequency

**Measurement**:
```python
import time

def remove_directory_from_snapshot(snapshot_path: Path, dirname: str) -> tuple[bool, float]:
    """Remove directory and return (success, duration_seconds)."""
    start_time = time.time()
    # ... existing removal logic ...
    duration = time.time() - start_time

    if duration > 5.0:  # Warn if removal takes more than 5 seconds
        logger.warning(f"    Slow removal: {dirname} took {duration:.1f}s")

    return success, duration
```

#### 5.3 File Churn Between Snapshots

**Pitfall**: High file churn in excluded directories means every snapshot must remove the same files.

**Example**: If you download 1GB of files to `~/Downloads` between each backup, the hook must remove 1GB each time.

**Impact**:
- Consistent overhead for each snapshot
- More work than never snapshotting those directories

**Mitigation**:
- This is inherent to the approach
- Performance cost is acceptable tradeoff for usability
- Could add size-based warnings in hook

#### 5.4 Permission Issues

**Pitfall**: Hook runs as root (via btrbk), but some files might have restrictive permissions.

**Impact**: Unlikely to cause issues (root can delete anything), but edge cases exist.

**Mitigation**:
- Hook already handles exceptions in removal
- Log any permission errors for investigation

#### 5.5 Symlinks to Excluded Directories

**Pitfall**: If included directory has symlinks to excluded directory, symlink becomes broken.

**Example**:
```bash
# In ~/code/project/
ln -s ~/Downloads/library.tar.gz library.tar.gz

# After snapshot cleanup:
# ~/Downloads removed, but ~/code/project/library.tar.gz still exists (broken)
```

**Solution**:
- This is expected behavior
- Document that symlinks to excluded directories will break in backups
- Alternative: Hook could detect and remove broken symlinks

#### 5.6 Restore Complexity

**Pitfall**: Restoring a full-home snapshot requires more care than restoring individual directories.

**Impact**:
- Can't just restore one directory easily
- Must extract specific directories from monolithic snapshot

**Mitigation**:
- Document restore procedures clearly
- Provide helper scripts for selective restore

**Example restore script**:
```bash
#!/bin/bash
# btrfs/local/restore-directory.sh <snapshot-name> <directory>

SNAPSHOT_NAME="$1"
DIRECTORY="$2"

# Receive snapshot from AWS
ssh ubuntu@54.177.219.117 \
  "sudo btrfs send /backup_volume/backups/home/$SNAPSHOT_NAME" | \
  sudo btrfs receive /home/mjr/.restore/

# Extract just the requested directory
rsync -av "/home/mjr/.restore/$SNAPSHOT_NAME/$DIRECTORY/" \
  "/home/mjr/${DIRECTORY}-restored/"

echo "Restored to: /home/mjr/${DIRECTORY}-restored/"
```

#### 5.7 Backup Size Verification

**Pitfall**: Without testing, you might not realize how much space is actually saved.

**Mitigation**: Test and measure actual backup sizes.

**Verification commands**:
```bash
# Local snapshot size (apparent)
du -sh /home/mjr/.snapshots/<snapshot>/

# Local snapshot size (actual with CoW)
sudo btrfs filesystem du -s /home/mjr/.snapshots/<snapshot>/

# Remote backup size
ssh ubuntu@54.177.219.117 \
  "sudo btrfs filesystem du -s /backup_volume/backups/home/<snapshot>/"

# Compare to original
du -sh /home/mjr/
```

#### 5.8 Config File Location

**Pitfall**: Hook needs to know where inclusion list config is located.

**Solution**: Hardcode path or use environment variable.

```python
# Option 1: Hardcoded (simple)
DEFAULT_CONFIG_PATH = Path('/home/mjr/code/personal/dotfiles/btrfs/local/backup-inclusion-list.conf')

# Option 2: Environment variable (flexible)
config_path = Path(os.environ.get(
    'BTRBK_INCLUSION_CONFIG',
    '/home/mjr/code/personal/dotfiles/btrfs/local/backup-inclusion-list.conf'
))
```

**Recommendation**: Hardcoded with fallback to environment variable for testing.

### Phase 6: Rollback Plan

If the inverse approach doesn't work well, how to roll back?

#### 6.1 Keep Subvolume Backups Temporarily

```bash
# Don't delete ~/migrating_to_subvolumes/ until confirmed working
# Keep it for at least 2-4 weeks of successful inverse backups
```

#### 6.2 Rollback Procedure

```bash
# 1. Stop btrbk automation
sudo systemctl stop btrbk-backup.timer

# 2. Re-convert directories to subvolumes
# Use create-subvolumes.py with data from ~/migrating_to_subvolumes/

# 3. Restore old btrbk.conf
git checkout HEAD~1 btrfs/local/btrbk.conf

# 4. Restore old hook
git checkout HEAD~1 btrfs/local/snapshot-cleanup-hook.py

# 5. Test old approach
sudo btrbk -c btrfs/local/btrbk.conf -v -n run

# 6. Resume if satisfied
sudo systemctl start btrbk-backup.timer
```

### Phase 7: Long-term Maintenance

#### 7.1 Monitoring Hook Performance

Add timing metrics to hook:

```python
@dataclass(frozen=True)
class CleanupMetrics:
    total_duration_seconds: float
    directories_removed: int
    git_items_removed: int
    largest_removal_seconds: float
    largest_removal_name: str

def log_metrics_to_file(metrics: CleanupMetrics, log_path: Path) -> None:
    """Append metrics to CSV log for trend analysis."""
    import csv
    from datetime import datetime

    with open(log_path, 'a') as f:
        writer = csv.writer(f)
        writer.writerow([
            datetime.now().isoformat(),
            metrics.total_duration_seconds,
            metrics.directories_removed,
            metrics.git_items_removed,
            metrics.largest_removal_seconds,
            metrics.largest_removal_name
        ])
```

**Analysis**:
```bash
# Check if hook is getting slower over time
tail -20 /var/log/btrbk-hook-metrics.csv

# Alert if hook takes > 5 minutes
```

#### 7.2 Inclusion List Management

**Process for adding directories**:
1. Edit `backup-inclusion-list.conf`
2. Test with dry-run
3. Monitor backup size increase

**Process for removing directories**:
1. Edit `backup-inclusion-list.conf`
2. Next snapshot will exclude it
3. Verify old backups still accessible
4. Wait for retention to age out old snapshots

#### 7.3 Disaster Recovery Testing

**Quarterly test**:
```bash
# 1. List available backups
ssh ubuntu@54.177.219.117 "sudo btrfs subvolume list /backup_volume/backups/"

# 2. Restore latest snapshot to test location
# (Use restore script from Phase 5.6)

# 3. Verify contents
# 4. Delete test restoration
```

## Critical Pitfalls Summary

### HIGH RISK

1. **If /home/mjr is not a subvolume**: Entire approach requires /home/mjr to be a btrfs subvolume. If it's not, conversion is complex and risky.

2. **Nested subvolume blind spots**: Docker volumes, VMs, or other nested subvolumes won't be backed up and won't be obvious without explicit detection.

3. **Large excluded directories**: If you have 50GB+ in excluded directories, hook performance could be unacceptable.

### MEDIUM RISK

4. **Restoration is all-or-nothing**: Unlike multiple subvolumes where you can restore individual pieces easily, full-home snapshot requires extraction.

5. **Local disk usage**: Single subvolume with high retention could use more local disk than multiple smaller subvolumes.

6. **First-time conversion**: Reverting from subvolumes to directories and back to single subvolume is complex with many steps.

### LOW RISK

7. **Symlink breakage**: Symlinks to excluded directories become broken in backups (expected behavior).

8. **Hook reliability**: If hook fails, entire snapshot is backed up (including excluded directories), wasting space but not losing data.

## Recommendation

**This approach is SOUND** and addresses the fundamental usability issues with multiple subvolumes.

### Pros Summary
- ✅ Eliminates ALL cross-subvolume boundary issues
- ✅ Normal filesystem behavior restored
- ✅ Simpler configuration (inclusion list vs subvolume management)
- ✅ Easier restore process (single snapshot)
- ✅ More flexible (change inclusions without restructuring)
- ✅ CoW efficiency maintained for space

### Cons Summary
- ⚠️  Moderate performance overhead during snapshot (removal operations)
- ⚠️  Slightly higher local disk usage (single snapshot history)
- ⚠️  Complex migration from current setup
- ⚠️  Requires /home/mjr to be a subvolume

### Decision Factors

**Choose this approach if**:
- Usability is top priority
- You frequently move/delete files across directories
- You value normal filesystem behavior
- You're willing to accept modest performance overhead
- Your excluded directories are < 20GB total

**Stick with current approach if**:
- You rarely interact with backed-up directories
- Performance is critical (every second counts)
- You don't want to risk complex migration
- Your excluded directories are > 50GB (removal would be very slow)

### My Assessment

Given your stated requirement: "it is critical that I be able to interact with the subvolumes as I would a normal filesystem - this is a basic requirement for usability"

**The inverse approach is the correct solution.**

The performance trade-off is acceptable, and the usability gains are substantial. The migration has risks but is manageable with the existing backups in `~/migrating_to_subvolumes/`.

## Next Steps (If Proceeding)

1. **Verify /home/mjr is a subvolume** (CRITICAL)
2. **Implement enhanced hook with inclusion list** (2-3 hours)
3. **Test with synthetic data** (1 hour)
4. **Create reversion script** (1 hour)
5. **Dry-run reversion in test environment** if possible (1-2 hours)
6. **Execute migration during low-risk window** (weekend, when you can afford downtime)
7. **Test thoroughly** before deleting subvolume backups
8. **Monitor performance** for first few backup cycles
9. **Adjust retention** if local disk usage is problematic

Estimated total effort: 8-12 hours including testing and safety measures.
