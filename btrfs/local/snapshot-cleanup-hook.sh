#!/usr/bin/env bash
# btrbk snapshot cleanup hook
#
# This hook is called AFTER btrbk creates a snapshot but BEFORE it's made read-only.
# We use this window to remove sensitive files from the snapshot.
#
# btrbk provides these environment variables:
#   $SNAPSHOT_SUBVOLUME_PATH - full path to the newly created snapshot
#   $SNAPSHOT_NAME - name of the snapshot
#   $SOURCE_SUBVOLUME - path to the source subvolume
#
# Usage: Called automatically by btrbk via snapshot_create_exec hook
#
# IMPORTANT: This script runs with the privileges of the btrbk process (usually root)

set -euo pipefail

# Exclusion patterns (relative to snapshot root)
readonly EXCLUSIONS=(
    # Credentials and secrets
    ".env"
    ".venv"
    "*secret*"
    ".aws"

    # Development artifacts
    "node_modules"
    ".cache"
    ".local"
    ".var"

    # User-specified
    "old_backup"
)

# Git-ignored files
readonly EXCLUDE_GIT_IGNORED=true

log() {
    echo "[snapshot-cleanup] $*" >&2
}

# Main cleanup function
cleanup_snapshot() {
    local snapshot_path="${SNAPSHOT_SUBVOLUME_PATH:-}"

    if [[ -z "$snapshot_path" ]]; then
        log "ERROR: SNAPSHOT_SUBVOLUME_PATH not set"
        return 1
    fi

    if [[ ! -d "$snapshot_path" ]]; then
        log "ERROR: Snapshot path does not exist: $snapshot_path"
        return 1
    fi

    log "Cleaning up snapshot: $snapshot_path"

    # Remove files matching exclusion patterns
    for pattern in "${EXCLUSIONS[@]}"; do
        log "  Removing pattern: $pattern"

        # Use find with -delete for safety (won't cross filesystem boundaries)
        find "$snapshot_path" -name "$pattern" -type f -delete 2>/dev/null || true
        find "$snapshot_path" -name "$pattern" -type d -exec rm -rf {} + 2>/dev/null || true
    done

    # Remove git-ignored files
    if [[ "$EXCLUDE_GIT_IGNORED" == true ]]; then
        log "  Removing git-ignored files..."

        # Find all git repositories in the snapshot
        while IFS= read -r -d '' gitdir; do
            repo_root=$(dirname "$gitdir")
            log "    Processing git repo: $repo_root"

            # Use git clean to remove ignored files (dry-run first to be safe)
            # -X = remove only ignored files (keep tracked and untracked non-ignored)
            # -d = remove directories
            # -f = force
            # -n = dry-run (remove -n for actual deletion)

            cd "$repo_root"

            # Get list of ignored files
            git ls-files --others --ignored --exclude-standard --directory | while IFS= read -r ignored_file; do
                local full_path="$repo_root/$ignored_file"
                if [[ -e "$full_path" ]]; then
                    log "      Removing: $ignored_file"
                    rm -rf "$full_path"
                fi
            done

        done < <(find "$snapshot_path" -name .git -type d -print0)
    fi

    log "Cleanup complete for: $snapshot_path"
    return 0
}

# Execute cleanup
cleanup_snapshot

exit 0
