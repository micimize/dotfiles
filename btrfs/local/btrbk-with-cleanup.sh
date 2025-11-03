#!/usr/bin/env bash
#
# btrbk-with-cleanup.sh - Wrapper script for btrbk with git-ignored file cleanup
#
# This script wraps btrbk to provide snapshot cleanup functionality that btrbk
# itself doesn't support via hooks. It creates snapshots, cleans up git-ignored
# files, then continues with the backup process.
#
# Usage:
#   ./btrbk-with-cleanup.sh [btrbk options]
#
# Examples:
#   ./btrbk-with-cleanup.sh -v -n run    # dry-run
#   ./btrbk-with-cleanup.sh -v run       # full backup with cleanup
#   ./btrbk-with-cleanup.sh -v snapshot  # only snapshots with cleanup
#
# The script will:
#   1. Create snapshots using btrbk
#   2. Run cleanup on each newly created snapshot (while still writable)
#   3. Continue with btrbk run to send backups to remote
#
# Note: This script must be run with appropriate privileges (usually via sudo)
#

set -euo pipefail

# Configuration
BTRBK_CONFIG="${BTRBK_CONFIG:-btrfs/local/btrbk.conf}"
CLEANUP_SCRIPT="$(dirname "$0")/snapshot-cleanup-hook.py"
BTRBK_BIN="${BTRBK_BIN:-btrbk}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Check if cleanup script exists
if [[ ! -f "$CLEANUP_SCRIPT" ]]; then
    log_error "Cleanup script not found: $CLEANUP_SCRIPT"
    log_info "Falling back to running btrbk without cleanup"
    exec "$BTRBK_BIN" -c "$BTRBK_CONFIG" "$@"
fi

# Check if btrbk is installed
if ! command -v "$BTRBK_BIN" &> /dev/null; then
    log_error "btrbk command not found: $BTRBK_BIN"
    exit 1
fi

# Parse arguments to determine if this is a dry-run
DRY_RUN=false
for arg in "$@"; do
    if [[ "$arg" == "-n" || "$arg" == "--dry-run" ]]; then
        DRY_RUN=true
        break
    fi
done

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "Dry-run mode: Running btrbk without cleanup"
    exec "$BTRBK_BIN" -c "$BTRBK_CONFIG" "$@"
fi

# Determine what operation we're performing
OPERATION="run"
for arg in "$@"; do
    case "$arg" in
        run|snapshot|resume|prune|archive|clean)
            OPERATION="$arg"
            break
            ;;
    esac
done

log_info "Starting btrbk with cleanup (operation: $OPERATION)"
log_info "Config: $BTRBK_CONFIG"
log_info "Cleanup script: $CLEANUP_SCRIPT"

# For snapshot or run operations, we need to:
# 1. Create snapshots
# 2. Clean them up
# 3. Continue with the rest of btrbk operations

case "$OPERATION" in
    run|snapshot)
        # Step 1: Create snapshots only (don't send to remote yet)
        log_info "Step 1: Creating snapshots..."
        "$BTRBK_BIN" -c "$BTRBK_CONFIG" "$@" snapshot || {
            log_error "Failed to create snapshots"
            exit 1
        }
        log_success "Snapshots created"

        # Step 2: Get list of newly created snapshots and clean them up
        log_info "Step 2: Cleaning up git-ignored files from snapshots..."

        # Get list of snapshot directories
        # We need to parse btrbk's output to find snapshot locations
        SNAPSHOT_DIRS=()
        while IFS= read -r line; do
            # Parse btrbk list output to find snapshot paths
            if [[ "$line" =~ ^snapshot[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+) ]]; then
                snapshot_path="${BASH_REMATCH[2]}"
                if [[ -d "$snapshot_path" ]]; then
                    SNAPSHOT_DIRS+=("$snapshot_path")
                fi
            fi
        done < <("$BTRBK_BIN" -c "$BTRBK_CONFIG" list snapshots --format=raw)

        if [[ ${#SNAPSHOT_DIRS[@]} -eq 0 ]]; then
            log_warning "No snapshots found to clean up"
        else
            log_info "Found ${#SNAPSHOT_DIRS[@]} snapshots to clean"

            # Clean up each snapshot
            for snapshot_dir in "${SNAPSHOT_DIRS[@]}"; do
                log_info "Cleaning: $snapshot_dir"

                # Export environment variables that the cleanup script expects
                export SNAPSHOT_SUBVOLUME_PATH="$snapshot_dir"
                export SNAPSHOT_NAME="$(basename "$snapshot_dir")"
                export SOURCE_SUBVOLUME="$(dirname "$(dirname "$snapshot_dir")")"

                # Run cleanup script
                if "$CLEANUP_SCRIPT"; then
                    log_success "Cleaned: $snapshot_dir"
                else
                    log_warning "Cleanup failed for: $snapshot_dir (continuing anyway)"
                fi

                unset SNAPSHOT_SUBVOLUME_PATH SNAPSHOT_NAME SOURCE_SUBVOLUME
            done

            log_success "Cleanup complete"
        fi

        # Step 3: If this was a 'run' operation, continue with sending backups
        if [[ "$OPERATION" == "run" ]]; then
            log_info "Step 3: Sending backups to remote..."
            "$BTRBK_BIN" -c "$BTRBK_CONFIG" "$@" resume || {
                log_error "Failed to send backups to remote"
                exit 1
            }
            log_success "Backups sent to remote"
        fi
        ;;

    *)
        # For other operations (prune, archive, clean, etc.), just run btrbk directly
        log_info "Running btrbk directly (no cleanup needed for $OPERATION)"
        exec "$BTRBK_BIN" -c "$BTRBK_CONFIG" "$@"
        ;;
esac

log_success "btrbk with cleanup completed successfully"
