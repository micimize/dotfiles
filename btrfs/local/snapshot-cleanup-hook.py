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
from typing import Generator, Optional
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='[snapshot-cleanup] %(message)s',
    stream=sys.stderr
)
logger = logging.getLogger(__name__)

def generate_git_repo_directories(snapshot_path: Path) -> Generator[Path, None, None]:
    for git_dir in snapshot_path.rglob('.git'):
        if git_dir.is_dir():
            yield git_dir.parent


def get_all_git_ignored_files_and_directories(repo_path: Path) -> tuple[Path, ...]:
    try:
        # Run git ls-files to get ignored files
        # --others: Show untracked files
        # --ignored: Show ignored files
        # --exclude-standard: Use standard ignore rules (.gitignore, .git/info/exclude, etc.)
        # --directory: Show directories (for ignored directories like node_modules)
        result = subprocess.run(
            ('git', 'ls-files', '--others', '--ignored', '--exclude-standard', '--directory'),
            cwd=repo_path,
            capture_output=True,
            text=True,
            check=True
        )

        return tuple(
            repo_path / line.strip()
            for line in result.stdout.splitlines()
            if line.strip()
        )

    except subprocess.CalledProcessError as e:
        logger.error(f"    Error running git ls-files in {repo_path}: {e}")
        return tuple()


def remove_path(path: Path) -> bool:
    try:
        if not path.exists():
            return True

        if path.is_dir() and not path.is_symlink():
            shutil.rmtree(path)
            logger.info(f"      Removed directory: {path}")
        else:
            path.unlink()
            logger.info(f"      Removed file: {path}")

        return True

    except Exception as e:
        logger.error(f"      Error removing {path}: {e}")
        return False


def remove_and_count_git_ignored_paths_from_repository(repo_path: Path) -> int:
    logger.info(f"    Processing git repo: {repo_path}")

    ignored_files = get_all_git_ignored_files_and_directories(repo_path)

    if not ignored_files:
        logger.info("      No ignored files found")
        return 0

    removed_count = 0
    for ignored_path in ignored_files:
        if remove_path(ignored_path):
            removed_count += 1

    logger.info(f"      Removed {removed_count} ignored items")
    return removed_count


def remove_git_ignored_files_from_snapshot(snapshot_path: Path) -> None:
    if not snapshot_path.exists():
        raise ValueError(f"Snapshot path does not exist: {snapshot_path}")

    if not snapshot_path.is_dir():
        raise ValueError(f"Snapshot path is not a directory: {snapshot_path}")

    logger.info(f"Cleaning up snapshot: {snapshot_path}")
    logger.info("  Removing git-ignored files...")

    git_repos = tuple(generate_git_repo_directories(snapshot_path))

    if not git_repos:
        logger.info("  No git repositories found in snapshot")
        return

    total_removed = 0
    for repo_path in git_repos:
        removed = remove_and_count_git_ignored_paths_from_repository(repo_path)
        total_removed += removed

    logger.info(f"Cleanup complete for: {snapshot_path}")
    logger.info(f"Total items removed: {total_removed}")


def main() -> int:
    # Get snapshot path from environment variable
    snapshot_paths = sys.argv[1:]

    if not snapshot_paths:
        logger.error("ERROR: SNAPSHOT_SUBVOLUME_PATH environment variable not set")
        return 1


    for snapshot_path_str in snapshot_paths:
        snapshot_path = Path(snapshot_path_str)
        print(snapshot_path_str)
        print(snapshot_path.exists())
        print(snapshot_path.is_dir())
        assert snapshot_path.exists() and snapshot_path.is_dir(), f"Snapshot path does not exist or isn't a dir: {snapshot_path}"
        remove_git_ignored_files_from_snapshot(snapshot_path)

    return 0


if __name__ == '__main__':
    sys.exit(main())
