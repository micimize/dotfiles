# Seamless multi-device filesystem
The goal of this project is to enable a single eagerly-backed-up filesystem to be shared across devices.

Initially, it is alright for this setup to have limitations, like effectively requiring each physical machine pull the latest snapshot before pushing new snapshots,
but the end goal is a system that is "seamless" and eventually consistent, even if one machine has "diverging" changes.

## btrfs backup system (current WIP approach)
near-term goals
- idempotent, well-documented setup script to configure the system in an aws instance with opentofu 
- similar script for local configuration of scheduled backups
- documentation on how incremental btrbk backups are given this setup
- hook to automatically take a backup before sleeping
- ability to exclude patterns from backups to avoid backing up sensitive data/keys


future goals:
- 1password integration and documentation
- "symbolic reference" in the aws setup that always points to the most recent backup
- system for automatically:
  1. ensuring a backup is taken before the local system sleeps
  2. loading from the latest 