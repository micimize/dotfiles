#!/usr/bin/env python3
"""
Create btrfs subvolumes from btrbk configuration.

Parses btrbk.conf to find subvolume declarations and converts regular
directories to btrfs subvolumes.

Usage:
    sudo ./create-subvolumes.py [--dry-run] [--config PATH] [--interactive]
"""

import argparse
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Generator


@dataclass(frozen=True)
class BtrbkConfig:
    volume_base: Path
    subvolume_names: tuple[str, ...]


def read_lines_from_file(file_path: Path) -> tuple[str, ...]:
    with open(file_path) as f:
        return tuple(line.strip() for line in f)


def filter_out_comments_and_blank_lines(lines: tuple[str, ...]) -> tuple[str, ...]:
    return tuple(line for line in lines if line and not line.startswith('#'))


def extract_volume_base_from_lines(lines: tuple[str, ...]) -> Path:
    for line in lines:
        if line.startswith('volume '):
            return Path(line.split(maxsplit=1)[1])
    raise ValueError("No 'volume' declaration found in config")


def extract_subvolume_names_from_lines(lines: tuple[str, ...]) -> tuple[str, ...]:
    names = tuple(
        line.split(maxsplit=1)[1]
        for line in lines
        if line.startswith('subvolume ')
    )
    if not names:
        raise ValueError("No 'subvolume' declarations found in config")
    return names


def parse_btrbk_config_file(config_path: Path) -> BtrbkConfig:
    if not config_path.exists():
        raise FileNotFoundError(f"Config file not found: {config_path}")

    lines = read_lines_from_file(config_path)
    cleaned_lines = filter_out_comments_and_blank_lines(lines)

    return BtrbkConfig(
        volume_base=extract_volume_base_from_lines(cleaned_lines),
        subvolume_names=extract_subvolume_names_from_lines(cleaned_lines)
    )


def check_if_path_is_btrfs_subvolume(path: Path) -> bool:
    try:
        subprocess.run(
            ('btrfs', 'subvolume', 'show', str(path)),
            capture_output=True,
            check=True
        )
        return True
    except subprocess.CalledProcessError:
        return False


def run_btrfs_subvolume_create(path: Path) -> None:
    subprocess.run(
        ('btrfs', 'subvolume', 'create', str(path)),
        capture_output=True,
        text=True,
        check=True
    )


def get_owner_uid_and_gid_from_path(path: Path) -> tuple[int, int]:
    stat = path.stat()
    return stat.st_uid, stat.st_gid


def move_directory_to_migration_area(source: Path, migration_base: Path) -> Path:
    destination = migration_base / source.name
    migration_base.mkdir(parents=True, exist_ok=True)
    shutil.move(str(source), str(destination))
    return destination


def recursively_change_ownership_of_path(path: Path, uid: int, gid: int) -> None:
    import os
    os.chown(path, uid, gid)
    if path.is_dir():
        for item in path.rglob('*'):
            os.chown(item, uid, gid, follow_symlinks=False)


def copy_contents_from_migration_to_subvolume(migration_path: Path, subvolume_path: Path) -> None:
    for item in migration_path.iterdir():
        destination = subvolume_path / item.name
        if item.is_dir():
            shutil.copytree(item, destination, symlinks=True, dirs_exist_ok=True)
        else:
            shutil.copy2(item, destination)


def ask_user_yes_or_no(prompt: str) -> bool:
    while True:
        response = input(f"{prompt} [y/n]: ").lower().strip()
        if response in ('y', 'yes'):
            return True
        if response in ('n', 'no'):
            return False
        print("Please answer 'y' or 'n'")


def convert_existing_directory_to_subvolume_interactively(
    directory_path: Path,
    migration_base: Path,
    dry_run: bool
) -> bool:
    print(f"\n  Path exists as regular directory: {directory_path}")
    print(f"  Will migrate to: {migration_base / directory_path.name}")
    print(f"  Then copy contents back to new subvolume")
    print(f"  Original will be preserved in migration area")

    if not ask_user_yes_or_no("  Convert this directory?"):
        print("  Skipped")
        return False

    if dry_run:
        print("  [DRY RUN] Would convert to subvolume")
        return True

    try:
        # Capture original ownership before moving
        print(f"    Capturing original ownership...")
        original_uid, original_gid = get_owner_uid_and_gid_from_path(directory_path)

        # Move existing directory to migration area
        print(f"    Moving to migration area...")
        migrated_path = move_directory_to_migration_area(directory_path, migration_base)

        # Create new subvolume (will be owned by root initially)
        print(f"    Creating subvolume...")
        run_btrfs_subvolume_create(directory_path)

        # Copy contents back
        print(f"    Copying contents to subvolume...")
        copy_contents_from_migration_to_subvolume(migrated_path, directory_path)

        # Restore original ownership
        print(f"    Restoring ownership (uid={original_uid}, gid={original_gid})...")
        recursively_change_ownership_of_path(directory_path, original_uid, original_gid)

        print(f"  ✓ Converted to subvolume")
        print(f"    Original preserved at: {migrated_path}")
        return True

    except Exception as e:
        print(f"  ✗ Failed: {e}")
        return False


def generate_subvolume_paths_from_config(config: BtrbkConfig) -> Generator[Path, None, None]:
    for name in config.subvolume_names:
        yield config.volume_base / name


def process_all_subvolumes_from_config(
    config: BtrbkConfig,
    dry_run: bool,
) -> tuple[int, int, int]:
    interactive = not dry_run
    migration_base = config.volume_base / 'migrating_to_subvolumes'

    existing_count = 0
    created_count = 0
    failed_count = 0

    for path in generate_subvolume_paths_from_config(config):
        print(f"\nProcessing: {path}")

        # Already a subvolume
        if check_if_path_is_btrfs_subvolume(path):
            print("  ✓ Already a subvolume")
            existing_count += 1
            continue

        # Path exists as regular directory
        if path.exists():
            if interactive:
                if convert_existing_directory_to_subvolume_interactively(path, migration_base, dry_run):
                    created_count += 1
                else:
                    failed_count += 1
            else:
                print("  ⚠ Exists as regular directory - use --interactive to convert")
                failed_count += 1
            continue

        # Path doesn't exist - create subvolume
        try:
            if dry_run:
                print("  [DRY RUN] Would create subvolume")
            else:
                run_btrfs_subvolume_create(path)
                print("  ✓ Created subvolume")
            created_count += 1
        except subprocess.CalledProcessError as e:
            print(f"  ✗ Failed to create: {e}")
            failed_count += 1

    return existing_count, created_count, failed_count


def check_running_as_root() -> bool:
    result = subprocess.run(('id', '-u'), capture_output=True)
    return result.stdout.strip() == b'0'


def main() -> int:
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

    if not args.dry_run and not check_running_as_root():
        print("ERROR: This script must be run as root (use sudo)")
        print("Or use --dry-run to preview what would be done")
        return 1

    try:
        print(f"Reading config: {args.config}")
        config = parse_btrbk_config_file(args.config)
        print(f"Volume base: {config.volume_base}")
        print(f"Subvolumes: {len(config.subvolume_names)}")

        if args.dry_run:
            print("\n=== DRY RUN MODE - No changes will be made ===")

        existing, created, failed = process_all_subvolumes_from_config(
            config,
            args.dry_run
        )

        print("\n=== Summary ===")
        print(f"Already subvolumes: {existing}")
        print(f"{'Would create' if args.dry_run else 'Created'}: {created}")
        print(f"Failed/Skipped: {failed}")

        if created > 0 and not args.dry_run:
            print(f"\nOriginal directories preserved in: {config.volume_base}/migrating_to_subvolumes/")
            print("You can safely delete them after verifying backups work correctly")

        return 0

    except (FileNotFoundError, ValueError) as e:
        print(f"ERROR: {e}")
        return 1

    except KeyboardInterrupt:
        print("\n\nInterrupted by user")
        return 130

    except Exception as e:
        print(f"ERROR: Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    sys.exit(main())
