#!/usr/bin/env bash
# Install showmethekey on Fedora Atomic (rpm-ostree) with a secure polkit override.
# Idempotent — safe to rerun.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_SRC="${SCRIPT_DIR}/49-showmethekey-require-auth.rules"
RULES_DST="/etc/polkit-1/rules.d/49-showmethekey-require-auth.rules"
COPR_REPO="pesader/showmethekey"

need_reboot=false

# --- COPR repo ---
if dnf copr list --enabled 2>/dev/null | grep -q "${COPR_REPO}"; then
  echo "COPR repo ${COPR_REPO} already enabled."
else
  echo "Enabling COPR repo ${COPR_REPO}..."
  sudo dnf copr enable -y "${COPR_REPO}"
fi

# --- rpm-ostree layer ---
if rpm-ostree status --json | grep -q '"showmethekey"'; then
  echo "showmethekey already layered."
else
  echo "Installing showmethekey via rpm-ostree..."
  sudo rpm-ostree install showmethekey
  need_reboot=true
fi

# --- Polkit override rule ---
if [ ! -f "${RULES_SRC}" ]; then
  echo "ERROR: polkit rule not found at ${RULES_SRC}" >&2
  exit 1
fi

if cmp -s "${RULES_SRC}" "${RULES_DST}" 2>/dev/null; then
  echo "Polkit override rule already in place."
else
  echo "Installing polkit override rule to ${RULES_DST}..."
  sudo cp "${RULES_SRC}" "${RULES_DST}"
  echo "Polkit rule installed (effective immediately, no reboot needed)."
fi

# --- Summary ---
echo ""
if [ "${need_reboot}" = true ]; then
  echo "Reboot required to complete rpm-ostree install."
  echo "After reboot, launch showmethekey-gtk from the app menu."
else
  echo "showmethekey is ready. Launch showmethekey-gtk from the app menu."
fi
echo "pkexec will prompt for a password once per session (cached 5 min)."
