#!/usr/bin/env python3
"""
btrbk snapshot cleanup hook

This hook is called AFTER btrbk creates a snapshot but BEFORE it's made read-only.
We use this window to remove git-ignored files from the snapshot.

Environment variables provided by btrbk:
    SNAPSHOT_SUBVOLUME_PATH: Full path to the newly created snapshot
    SNAPSHOT_NAME: Name of the snapshot
    SOURCE_SUBVOLUME: Path to the source subvolume

Usage:
    Called automatically by btrbk via snapshot_create_exec hook

IMPORTANT: This script runs with the privileges of the btrbk process (usually root)
"""

import os
import sys
import subprocess
import shutil
from pathlib import Path
from typing import List, Optional
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='[snapshot-cleanup] %(message)s',
    stream=sys.stderr
)
logger = logging.getLogger(__name__)


class SnapshotCleaner:
    """Removes git-ignored files from btrfs snapshots before they're finalized."""

    def __init__(self, snapshot_path: Path):
        """
        Initialize the snapshot cleaner.

        Args:
            snapshot_path: Path to the snapshot to clean

        Raises:
            ValueError: If snapshot path is invalid
        """
        if not snapshot_path.exists():
            raise ValueError(f"Snapshot path does not exist: {snapshot_path}")

        if not snapshot_path.is_dir():
            raise ValueError(f"Snapshot path is not a directory: {snapshot_path}")

        self.snapshot_path = snapshot_path
        logger.info(f"Cleaning up snapshot: {snapshot_path}")

    def find_git_repositories(self) -> List[Path]:
        """
        Find all git repositories within the snapshot.

        Returns:
            List of paths to git repository root directories
        """
        git_repos: List[Path] = []

        for git_dir in self.snapshot_path.rglob('.git'):
            if git_dir.is_dir():
                repo_root = git_dir.parent
                git_repos.append(repo_root)
                logger.info(f"  Found git repo: {repo_root}")

        return git_repos

    def get_ignored_files(self, repo_path: Path) -> List[Path]:
        """
        Get list of git-ignored files in a repository.

        Args:
            repo_path: Path to the git repository root

        Returns:
            List of paths to ignored files/directories (relative to repo_path)
        """
        try:
            # Run git ls-files to get ignored files
            # --others: Show untracked files
            # --ignored: Show ignored files
            # --exclude-standard: Use standard ignore rules (.gitignore, .git/info/exclude, etc.)
            # --directory: Show directories (for ignored directories like node_modules)
            result = subprocess.run(
                ['git', 'ls-files', '--others', '--ignored', '--exclude-standard', '--directory'],
                cwd=repo_path,
                capture_output=True,
                text=True,
                check=True
            )

            ignored_files = [
                repo_path / line.strip()
                for line in result.stdout.splitlines()
                if line.strip()
            ]

            return ignored_files

        except subprocess.CalledProcessError as e:
            logger.error(f"    Error running git ls-files in {repo_path}: {e}")
            return []

    def remove_path(self, path: Path) -> bool:
        """
        Safely remove a file or directory.

        Args:
            path: Path to remove

        Returns:
            True if successfully removed, False otherwise
        """
        try:
            if not path.exists():
                return True

            if path.is_dir() and not path.is_symlink():
                shutil.rmtree(path)
                logger.info(f"      Removed directory: {path.relative_to(self.snapshot_path)}")
            else:
                path.unlink()
                logger.info(f"      Removed file: {path.relative_to(self.snapshot_path)}")

            return True

        except Exception as e:
            logger.error(f"      Error removing {path}: {e}")
            return False

    def clean_repository(self, repo_path: Path) -> int:
        """
        Remove git-ignored files from a repository.

        Args:
            repo_path: Path to the git repository root

        Returns:
            Number of files/directories removed
        """
        logger.info(f"    Processing git repo: {repo_path}")

        ignored_files = self.get_ignored_files(repo_path)

        if not ignored_files:
            logger.info(f"      No ignored files found")
            return 0

        removed_count = 0
        for ignored_path in ignored_files:
            if self.remove_path(ignored_path):
                removed_count += 1

        logger.info(f"      Removed {removed_count} ignored items")
        return removed_count

    def clean(self) -> int:
        """
        Remove all git-ignored files from the snapshot.

        Returns:
            Total number of files/directories removed
        """
        logger.info("  Removing git-ignored files...")

        git_repos = self.find_git_repositories()

        if not git_repos:
            logger.info("  No git repositories found in snapshot")
            return 0

        total_removed = 0
        for repo_path in git_repos:
            removed = self.clean_repository(repo_path)
            total_removed += removed

        logger.info(f"Cleanup complete for: {self.snapshot_path}")
        logger.info(f"Total items removed: {total_removed}")

        return total_removed


def main() -> int:
    """
    Main entry point for the snapshot cleanup hook.

    Returns:
        Exit code (0 for success, 1 for error)
    """
    # Get snapshot path from environment variable
    snapshot_path_str: Optional[str] = os.environ.get('SNAPSHOT_SUBVOLUME_PATH')

    if not snapshot_path_str:
        logger.error("ERROR: SNAPSHOT_SUBVOLUME_PATH environment variable not set")
        return 1

    snapshot_path = Path(snapshot_path_str)

    try:
        cleaner = SnapshotCleaner(snapshot_path)
        cleaner.clean()
        return 0

    except ValueError as e:
        logger.error(f"ERROR: {e}")
        return 1

    except Exception as e:
        logger.error(f"ERROR: Unexpected error: {e}")
        import traceback
        traceback.print_exc(file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
