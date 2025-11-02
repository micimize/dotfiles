#!/usr/bin/env python3
"""
Create btrfs subvolumes from btrbk configuration

Parses the btrbk.conf file to find all 'subvolume' declarations and creates
btrfs subvolumes for directories that aren't already subvolumes.

IMPORTANT: This script must be run as root since it modifies filesystem structure.

Usage:
    sudo ./create-subvolumes.py [--dry-run] [--config PATH]
"""

import argparse
import subprocess
import sys
from pathlib import Path
from typing import Optional
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='[create-subvolumes] %(message)s',
)
logger = logging.getLogger(__name__)


def parse_btrbk_config(config_path: Path) -> tuple[Path, tuple[str, ...]]:
    """
    Parse btrbk configuration to extract volume base path and subvolume names.

    Args:
        config_path: Path to btrbk.conf

    Returns:
        Tuple of (volume_base_path, tuple of subvolume names)

    Example:
        volume /home/mjr
          subvolume code
          subvolume Documents

        Returns: (Path('/home/mjr'), ('code', 'Documents'))
    """
    if not config_path.exists():
        raise FileNotFoundError(f"Config file not found: {config_path}")

    volume_base: Optional[Path] = None
    subvolumes: list[str] = []

    with open(config_path) as f:
        for line in f:
            line = line.strip()

            # Skip comments and empty lines
            if not line or line.startswith('#'):
                continue

            # Parse volume line
            if line.startswith('volume '):
                volume_path = line.split(maxsplit=1)[1]
                volume_base = Path(volume_path)
                logger.info(f"Found volume base: {volume_base}")

            # Parse subvolume line
            elif line.startswith('subvolume '):
                subvol_name = line.split(maxsplit=1)[1]
                subvolumes.append(subvol_name)
                logger.info(f"  Found subvolume: {subvol_name}")

    if volume_base is None:
        raise ValueError("No 'volume' declaration found in config")

    if not subvolumes:
        raise ValueError("No 'subvolume' declarations found in config")

    return volume_base, tuple(subvolumes)


def is_btrfs_subvolume(path: Path) -> bool:
    """
    Check if a path is a btrfs subvolume.

    Args:
        path: Path to check

    Returns:
        True if path is a btrfs subvolume, False otherwise
    """
    try:
        result = subprocess.run(
            ('btrfs', 'subvolume', 'show', str(path)),
            capture_output=True,
            check=True
        )
        return True
    except subprocess.CalledProcessError:
        return False


def create_btrfs_subvolume(path: Path, dry_run: bool = False) -> bool:
    """
    Create a btrfs subvolume at the given path.

    IMPORTANT: This only works for directories that don't exist yet or are empty.
    Cannot convert existing directory with data to subvolume without moving data.

    Args:
        path: Path where subvolume should be created
        dry_run: If True, only log what would be done

    Returns:
        True if successful or would be successful (dry run)
    """
    if dry_run:
        logger.info(f"    [DRY RUN] Would create subvolume: {path}")
        return True

    try:
        subprocess.run(
            ('btrfs', 'subvolume', 'create', str(path)),
            capture_output=True,
            text=True,
            check=True
        )
        logger.info(f"    Created subvolume: {path}")
        return True

    except subprocess.CalledProcessError as e:
        logger.error(f"    Failed to create subvolume {path}: {e.stderr}")
        return False


def process_subvolumes(
    volume_base: Path,
    subvolume_names: tuple[str, ...],
    dry_run: bool = False
) -> tuple[int, int, int]:
    """
    Process subvolumes: check status and create if needed.

    Args:
        volume_base: Base path for all subvolumes
        subvolume_names: Names of subvolumes to process
        dry_run: If True, only show what would be done

    Returns:
        Tuple of (existing_count, created_count, failed_count)
    """
    existing = 0
    created = 0
    failed = 0

    for subvol_name in subvolume_names:
        full_path = volume_base / subvol_name

        logger.info(f"Processing: {full_path}")

        # Check if already a subvolume
        if is_btrfs_subvolume(full_path):
            logger.info(f"  ✓ Already a subvolume")
            existing += 1
            continue

        # Check if path exists as regular directory
        if full_path.exists():
            logger.warning(f"  ⚠ Path exists as regular directory/file")
            logger.warning(f"    Cannot convert in-place - manual intervention required")
            logger.warning(f"    See docs for how to convert directory with data")
            failed += 1
            continue

        # Path doesn't exist - can create subvolume
        if create_btrfs_subvolume(full_path, dry_run):
            created += 1
        else:
            failed += 1

    return existing, created, failed


def main() -> int:
    """
    Main entry point.

    Returns:
        Exit code (0 for success, non-zero for error)
    """
    parser = argparse.ArgumentParser(
        description='Create btrfs subvolumes from btrbk configuration'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Show what would be done without making changes'
    )
    parser.add_argument(
        '--config',
        type=Path,
        default=Path(__file__).parent / 'btrbk.conf',
        help='Path to btrbk.conf (default: ./btrbk.conf)'
    )

    args = parser.parse_args()

    # Check root privileges (unless dry-run)
    if not args.dry_run and subprocess.run(['id', '-u'], capture_output=True).stdout.strip() != b'0':
        logger.error("ERROR: This script must be run as root (use sudo)")
        logger.info("Or use --dry-run to preview what would be done")
        return 1

    try:
        # Parse config
        logger.info(f"Reading config: {args.config}")
        volume_base, subvolume_names = parse_btrbk_config(args.config)
        logger.info(f"Found {len(subvolume_names)} subvolumes to process\n")

        # Process subvolumes
        if args.dry_run:
            logger.info("=== DRY RUN MODE - No changes will be made ===\n")

        existing, created, failed = process_subvolumes(
            volume_base,
            subvolume_names,
            args.dry_run
        )

        # Summary
        logger.info("\n=== Summary ===")
        logger.info(f"Already subvolumes: {existing}")
        if args.dry_run:
            logger.info(f"Would create: {created}")
        else:
            logger.info(f"Created: {created}")
        logger.info(f"Failed/Manual intervention needed: {failed}")

        if failed > 0:
            logger.warning("\nSome directories need manual conversion.")
            logger.warning("For directories with existing data, you need to:")
            logger.warning("  1. Move data out: mv dir dir.tmp")
            logger.warning("  2. Create subvolume: btrfs subvolume create dir")
            logger.warning("  3. Move data back: mv dir.tmp/* dir/")
            logger.warning("  4. Clean up: rm -rf dir.tmp")
            return 1

        return 0

    except (FileNotFoundError, ValueError) as e:
        logger.error(f"ERROR: {e}")
        return 1

    except Exception as e:
        logger.error(f"ERROR: Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    sys.exit(main())
