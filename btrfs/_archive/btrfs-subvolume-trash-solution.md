# Btrfs Subvolumes and Trash Functionality

## The Problem

After converting directories like `.config`, `code`, `Documents`, etc. into btrfs subvolumes for btrbk backup purposes, you're experiencing issues with trash functionality. Files cannot be moved to trash from within these subvolumes.

## Root Cause

### Technical Background

**Btrfs subvolumes are treated as filesystem boundaries by the Linux desktop stack.**

Even though all your subvolumes are on the same physical btrfs filesystem, each subvolume has:
- A unique subvolume ID
- Its own internal filesystem structure
- Separate mount semantics (can be mounted independently)

### Why This Breaks Trash

The FreeDesktop.org Trash Specification (which KDE/Dolphin, GNOME/Nautilus, and other file managers follow) defines two methods for handling trash:

**Method 1: Home Trash** (`~/.local/share/Trash/`)
- Works when the file is on the same filesystem as your home directory
- Uses a simple `rename()` system call to move files into the trash

**Method 2: Per-Filesystem Trash** (`$topdir/.Trash-$uid` or `$topdir/.Trash/$uid/`)
- Used when a file is on a different filesystem than home
- Creates a trash directory at the "top directory" (mount point) of that filesystem

### The Subvolume Problem

When you have:
- `~/.config` as a btrfs subvolume
- `~/.local/share/Trash` as part of a different subvolume (or not a subvolume)

The file manager detects these are on "different filesystems" and cannot use a simple `rename()` to move files to trash. Instead, it needs to:
1. Copy the file to the trash location
2. Delete the original

**However**, many file manager libraries (gvfs, gio, glib) don't handle this cross-subvolume case properly. They either:
- Fail silently and permanently delete the file
- Create hidden `.Trash-$uid` directories in each subvolume that aren't recognized by the trash UI
- Refuse to delete the file at all

## Solutions

### Solution 1: Mount Subvolumes with `x-gvfs-trash` Option (RECOMMENDED FOR GNOME 47+)

If you're using GNOME 47 or later, you can mount btrfs subvolumes with the `x-gvfs-trash` option to enable proper trash handling.

**For subvolumes in `/etc/fstab`:**
```fstab
UUID=<uuid>  /home/mjr/.config  btrfs  subvol=.config,x-gvfs-trash  0  0
UUID=<uuid>  /home/mjr/code     btrfs  subvol=code,x-gvfs-trash     0  0
# etc.
```

**How to implement:**
1. Find your btrfs filesystem UUID:
   ```bash
   findmnt -n -o UUID /home/mjr
   ```

2. Add entries to `/etc/fstab` for each subvolume you want to mount:
   ```bash
   sudo nano /etc/fstab
   ```

3. Create mount points if they don't exist (they already do for your directories)

4. Test the mount:
   ```bash
   sudo mount -a
   ```

**Limitations:**
- Requires GNOME 47+ (check with `gnome-shell --version` if using GNOME)
- KDE/Dolphin support unclear - may or may not work
- Requires each subvolume to have an entry in `/etc/fstab` or be explicitly mounted

### Solution 2: Create Per-Subvolume Trash Directories

Create `.Trash-$UID` directories at the root of each subvolume and configure your file manager to recognize them.

**Implementation:**
```bash
# Get your user ID
UID=$(id -u)

# Create trash directories for each subvolume
for dir in ~/.config ~/code ~/Documents ~/Desktop ~/Templates ~/Pictures ~/Public ~/Videos ~/Music ~/.dev_sculptor ~/.sculptor ~/.mozilla ~/Dygma; do
    if [ -d "$dir" ]; then
        mkdir -p "$dir/.Trash-$UID"/{files,info}
        chmod 700 "$dir/.Trash-$UID"
    fi
done
```

**Configure file manager to use them:**

For KDE/Dolphin, this should work automatically according to the FreeDesktop spec.

For GNOME/Nautilus, you may need to configure gvfs settings (varies by version).

**Limitations:**
- These trash directories are hidden and won't show in your normal Trash view
- You'll need to manually empty them periodically
- Different file managers may behave differently

### Solution 3: Unified Trash Subvolume (EXPERIMENTAL)

Create a dedicated trash subvolume and symlink `~/.local/share/Trash` to it.

**Implementation:**
```bash
# Backup existing trash
mv ~/.local/share/Trash ~/.local/share/Trash.backup

# Create trash subvolume
sudo btrfs subvolume create /home/mjr/.trash-subvolume

# Set ownership
sudo chown -R $(id -u):$(id -g) /home/mjr/.trash-subvolume

# Create proper structure
mkdir -p /home/mjr/.trash-subvolume/{files,info,expunged}

# Symlink
ln -s /home/mjr/.trash-subvolume ~/.local/share/Trash
```

**How it works:**
- All trash operations now target a single subvolume
- This subvolume can handle cross-subvolume moves via copy+delete
- Your trash UI should work normally

**Limitations:**
- Deleting files will now trigger copy operations (slower)
- Uses more disk space temporarily during deletion
- Untested - may have edge cases

### Solution 4: Reduce Subvolumes to Critical-Only (PRAGMATIC)

Remove less-critical directories from your backup configuration, keeping only directories where:
- You absolutely need snapshot-based backup
- Cross-subvolume operations are minimal

**Candidates to keep as subvolumes:**
- `~/code` - Critical, but you may not delete files often
- `~/Documents` - Important documents
- `~/Pictures`, `~/Videos`, `~/Music` - Large media files you want to protect

**Candidates to remove from subvolumes:**
- `~/.config` - **This is likely causing most of your issues**
- `~/.mozilla` - Browser data, can be problematic
- Desktop/Templates/Public - Mostly empty or transient

**How to revert a subvolume to a regular directory:**

**WARNING: This is a destructive operation. Back up data first!**

```bash
# For .config example
cd ~
sudo btrfs subvolume delete .config
mkdir .config
cp -a ~/migrating_to_subvolumes/.config/* .config/
```

**Benefits:**
- Reduces complexity
- Restores normal filesystem behavior for interactive directories
- Still backs up the most critical data

### Solution 5: Use Trash-CLI for Subvolume-Aware Deletion (WORKAROUND)

Install a command-line trash tool that handles cross-filesystem moves properly.

**Installation:**
```bash
sudo dnf install trash-cli
```

**Usage:**
```bash
trash-put file.txt           # Move to trash
trash-list                   # List trashed files
trash-restore                # Restore files
trash-empty                  # Empty trash
```

**Integration:**
- Configure file manager to use `trash-put` for deletions (if supported)
- Use keyboard shortcuts mapped to `trash-put`
- Create `.desktop` file actions for right-click menu

**Limitations:**
- Command-line workflow required
- May not integrate seamlessly with GUI file managers
- Need to remember to use it instead of Delete key

## Recommended Approach for Your Setup

Given your requirements for usability and that you're using KDE on Fedora, I recommend:

### Short-term (Immediate Fix)

**Remove `.config` from subvolume backups:**

`.config` is a high-interaction directory (applications constantly read/write to it). Having it as a subvolume causes friction with trash, but the backup value is questionable:
- Most `.config` files are application settings that can be regenerated
- Sensitive configs (SSH keys, etc.) should be managed separately anyway
- The truly critical configs (Dolphin, KDE settings) are small

**Steps:**
```bash
# 1. Remove .config subvolume
cd ~
sudo btrfs subvolume delete .config

# 2. Restore from migration area
mkdir .config
cp -a ~/migrating_to_subvolumes/.config/* .config/

# 3. Remove from btrbk.conf
# Edit /code/btrfs/local/btrbk.conf and remove the "subvolume .config" line

# 4. Test trash functionality
# Try deleting a file from .config/
```

### Medium-term (Better Trash Support)

**Try `x-gvfs-trash` mount option for remaining subvolumes:**

Even though you're using KDE, this mount option may still help since it's part of the broader freedesktop stack.

**Steps:**
```bash
# 1. Find your btrfs UUID
UUID=$(findmnt -n -o UUID /home/mjr)

# 2. Add to /etc/fstab for subvolumes you're keeping
sudo tee -a /etc/fstab <<EOF
# btrbk backup subvolumes with trash support
UUID=$UUID  /home/mjr/code          btrfs  subvol=code,x-gvfs-trash          0  0
UUID=$UUID  /home/mjr/Documents     btrfs  subvol=Documents,x-gvfs-trash     0  0
UUID=$UUID  /home/mjr/Pictures      btrfs  subvol=Pictures,x-gvfs-trash      0  0
UUID=$UUID  /home/mjr/Videos        btrfs  subvol=Videos,x-gvfs-trash        0  0
UUID=$UUID  /home/mjr/Music         btrfs  subvol=Music,x-gvfs-trash         0  0
UUID=$UUID  /home/mjr/Desktop       btrfs  subvol=Desktop,x-gvfs-trash       0  0
UUID=$UUID  /home/mjr/Templates     btrfs  subvol=Templates,x-gvfs-trash     0  0
UUID=$UUID  /home/mjr/Public        btrfs  subvol=Public,x-gvfs-trash        0  0
UUID=$UUID  /home/mjr/Dygma         btrfs  subvol=Dygma,x-gvfs-trash         0  0
UUID=$UUID  /home/mjr/.dev_sculptor btrfs  subvol=.dev_sculptor,x-gvfs-trash 0  0
UUID=$UUID  /home/mjr/.sculptor     btrfs  subvol=.sculptor,x-gvfs-trash     0  0
UUID=$UUID  /home/mjr/.mozilla      btrfs  subvol=.mozilla,x-gvfs-trash      0  0
EOF

# 3. Test mounting (this won't break existing mounts)
sudo mount -a

# 4. Verify
mount | grep btrfs | grep home
```

### Long-term (Evaluate Backup Strategy)

**Consider which directories truly need individual snapshots:**

The subvolume approach is most valuable for:
- Large directories with important but mostly-static content (Pictures, Videos, Music, Documents)
- Directories where you want point-in-time recovery (code)

Less valuable for:
- Rapidly-changing directories (.config, .mozilla)
- Directories with many small files
- Directories you interact with constantly

**Alternative backup approaches for different data types:**
- **Code**: Keep as subvolume, this is your most critical data
- **Documents**: Keep as subvolume, important work
- **Media** (Pictures/Videos/Music): Keep as subvolume, large and valuable
- **Config/Settings**: Consider using dotfile management (git) instead of btrbk
- **Browser data**: Consider Firefox Sync or similar instead of file-level backup

## Other Potential Cross-Subvolume Issues

Beyond trash, here are other operations that may have issues with the subvolume setup:

### 1. Hard Links Across Subvolumes

**Problem:** Hard links cannot span btrfs subvolume boundaries.

**Impact:**
- Package managers (rpm, dnf) sometimes use hard links
- Some backup tools use hard links for deduplication
- Development tools that create hard links may fail

**Detection:**
```bash
ln ~/code/file.txt ~/Documents/hardlink.txt
# This will fail with "Invalid cross-device link" if they're different subvolumes
```

**Mitigation:**
- Most package managers fall back to copying
- Ensure backup tools support reflinks instead of hard links
- Use symlinks instead of hard links where possible

### 2. Rename/Move Operations

**Problem:** Moving files between subvolumes requires copy+delete, not simple rename.

**Impact:**
- File managers may be slow when moving large files between subvolumes
- Progress bars may not work correctly
- Risk of incomplete moves if process is interrupted
- Some applications expect instant renames and may have issues

**Example:**
```bash
# Fast (same subvolume)
mv ~/code/project1/file.txt ~/code/project2/file.txt

# Slow (different subvolumes)
mv ~/code/file.txt ~/Documents/file.txt  # This copies then deletes
```

**Mitigation:**
- Be aware of this when organizing files
- Use rsync for large moves between subvolumes
- Keep related files in the same subvolume

### 3. Atomic Operations

**Problem:** Operations that expect atomic rename() across directories may fail.

**Impact:**
- Database files or other applications using atomic renames for safety
- Text editors that save files atomically (write to .tmp, then rename)
- May result in data corruption if application doesn't handle EXDEV error

**Example:**
If an application in `~/.config/` tries to atomically update a file but temp files are in a different subvolume:
```bash
# Application tries:
# 1. Write to ~/.config/app/data.tmp
# 2. rename(~/.config/app/data.tmp, ~/.config/app/data)
# This fails if .tmp ends up in different subvolume
```

**Mitigation:**
- Keep `.config` as regular directory (recommended above)
- Ensure temp directories are in same subvolume as target files
- Configure applications to use correct temp directories

### 4. Quota and Space Accounting

**Problem:** Btrfs quota is per-subvolume, making space accounting complex.

**Impact:**
- `df` may show confusing results
- `du` doesn't account for shared extents between snapshots
- Hard to understand actual disk usage

**Example:**
```bash
df -h /home/mjr/code
# May show full filesystem size, not per-subvolume limit

btrfs filesystem usage /home/mjr
# Shows actual usage, but complex output
```

**Mitigation:**
- Use `btrfs filesystem usage` for accurate reporting
- Don't rely on traditional tools for space accounting
- Consider enabling btrfs quotas if you need per-subvolume limits

### 5. Backup Tool Compatibility

**Problem:** Some backup tools don't understand btrfs subvolumes.

**Impact:**
- Tools may try to backup the same data multiple times
- Tools may not preserve subvolume structure on restore
- Snapshots within subvolumes may confuse backup tools

**Examples:**
- rsync: Works but doesn't understand subvolumes are boundaries
- tar: May enter `.snapshots` directories and backup snapshots
- borg/restic: May deduplicate across subvolumes unexpectedly

**Mitigation:**
- Use btrbk (you're already doing this!) for primary backups
- Exclude `.snapshots` directories from other backup tools
- Test restore procedures to ensure subvolume structure is preserved

### 6. File Manager Bookmarks and Recent Files

**Problem:** File manager metadata may get confused by subvolume boundaries.

**Impact:**
- "Recent files" may not work across subvolumes
- Bookmarks may break if subvolumes are remounted
- Thumbnail caches may not work correctly

**Mitigation:**
- Generally minor annoyances
- Clearing caches resolves most issues
- Keep frequently-accessed directories in same subvolume

### 7. Search and Indexing

**Problem:** Desktop search tools may treat each subvolume as separate filesystem.

**Impact:**
- Baloo (KDE search) may index subvolumes separately
- Search results may be incomplete or duplicated
- Extra CPU/IO for indexing multiple subvolumes

**Mitigation:**
- Configure search indexer to understand your subvolume layout
- Exclude snapshot directories from indexing
- May need to manually rebuild search index

## Testing Your Setup

After implementing the recommended changes, test these operations:

```bash
# 1. Test trash from each subvolume
cd ~/code && touch test-trash-code.txt
# Delete via Dolphin, verify it appears in Trash

cd ~/Documents && touch test-trash-docs.txt
# Delete via Dolphin, verify it appears in Trash

# 2. Test move operations
cd ~
touch code/test-move.txt
# Use Dolphin to move from code/ to Documents/
# Verify it works and check if it's fast or slow

# 3. Test hard links
ln ~/code/file.txt ~/Documents/hardlink.txt
# Should fail - verify you get clear error message

# 4. Test symlinks
ln -s ~/code/project ~/Documents/project-link
# Should work fine

# 5. Test disk usage reporting
btrfs filesystem usage /home/mjr
df -h /home/mjr
du -sh ~/code
# Compare results, understand the differences

# 6. Test with applications
# Open a file in .config with an editor
# Make sure saves work correctly
# Try deleting files from GUI applications
```

## Conclusion

The trash issue is a known limitation of using btrfs subvolumes for directories you interact with frequently. The recommended approach is:

1. **Remove `.config` from subvolumes** - restores normal trash functionality for most use cases
2. **Try `x-gvfs-trash` mount option** - may improve trash support for remaining subvolumes
3. **Be aware of cross-subvolume operation limitations** - plan your file organization accordingly
4. **Test thoroughly** - ensure your workflow works smoothly with the remaining subvolumes

For your backup requirements, you can still achieve excellent protection for your critical data (code, documents, media) while maintaining full usability by reducing the number of subvolumes to those that truly benefit from snapshot-based backup.
