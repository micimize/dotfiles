#!/usr/bin/env bash
# Convert existing directories to btrfs subvolumes for btrbk backup
#
# WARNING: This script modifies filesystem structure. Back up important data first!
#
# Usage: sudo ./convert-to-subvolumes.sh [--dry-run]

set -euo pipefail

readonly HOME_DIR="/home/mjr"
readonly BACKUP_TARGETS=(
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

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() { echo -e "${BLUE}INFO:${NC} $*"; }
log_success() { echo -e "${GREEN}SUCCESS:${NC} $*"; }
log_warning() { echo -e "${YELLOW}WARNING:${NC} $*"; }
log_error() { echo -e "${RED}ERROR:${NC} $*" >&2; }

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

# Check if HOME_DIR is on btrfs
if ! btrfs filesystem show "$HOME_DIR" &>/dev/null; then
    log_error "$HOME_DIR is not on a btrfs filesystem"
    exit 1
fi

log_info "Checking current subvolume status..."
echo ""

for dir in "${BACKUP_TARGETS[@]}"; do
    full_path="$HOME_DIR/$dir"

    if [[ ! -e "$full_path" ]]; then
        log_warning "Directory does not exist: $full_path (will skip)"
        continue
    fi

    # Check if already a subvolume
    if btrfs subvolume show "$full_path" &>/dev/null; then
        log_success "$dir - Already a subvolume"
    else
        log_info "$dir - Regular directory (needs conversion)"

        if [[ "$DRY_RUN" == true ]]; then
            log_info "  [DRY RUN] Would convert to subvolume"
        else
            log_info "  Converting to subvolume..."

            # Create temporary name
            temp_path="${full_path}.btrbk-conversion-tmp"

            # Move original directory
            log_info "    Moving $dir to temporary location..."
            mv "$full_path" "$temp_path"

            # Create new subvolume
            log_info "    Creating subvolume..."
            btrfs subvolume create "$full_path"

            # Copy data using CoW reflinks
            log_info "    Copying data with CoW reflinks..."
            cp -a --reflink=always "$temp_path/." "$full_path/"

            # Preserve ownership
            chown --reference="$temp_path" "$full_path"
            chmod --reference="$temp_path" "$full_path"

            # Remove temporary directory
            log_info "    Cleaning up..."
            rm -rf "$temp_path"

            log_success "  Converted $dir to subvolume"
        fi
    fi
done

echo ""
if [[ "$DRY_RUN" == true ]]; then
    log_info "Dry run complete. Run without --dry-run to apply changes."
else
    log_success "Conversion complete!"
    echo ""
    log_info "Next steps:"
    log_info "  1. Verify subvolumes: btrfs subvolume list $HOME_DIR"
    log_info "  2. Configure btrbk: edit btrfs/local/btrbk.conf"
    log_info "  3. Test backup: btrbk -c btrfs/local/btrbk.conf -v -n run"
fi
