#!/usr/bin/env bash
# FedoraKDE - one entrypoint for the Fedora 45 KDE migration.
# Stages run in different environments; see --help.
set -Eeuo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/scripts/lib/common.sh"
export FEDORA_KDE_ROOT="$HERE"

usage() {
  cat <<'EOF'
FedoraKDE - Fedora 45 KDE migration kit

Usage:
  install.sh <stage> [options]

Stages:
  preflight     Run on the CURRENT Garuda system (read-only checks):
                backup integrity, data-triage manifest, disk/ISO guards,
                Secure Boot / TPM2 report.  Blocks until the manifest is
                accepted (--accept-manifest or typing ACCEPT).
  usb           Run on the CURRENT Garuda system as root.  Builds the
                installer USB: dd the ISO, add a FAT partition labelled
                OEMDRV holding ks.cfg + the provisioning bundle.
  provision     Run on the NEW Fedora system as root, first boot.
                Installs repos, NVIDIA, ASUS tools, hardening, snapshots,
                restores the UX from the backup tarball, installs apps.
  tpm2-enroll   Run on the NEW Fedora system LAST, after Secure Boot and
                MOK are verified and the nvidia module loads.
  verify        Read-only acceptance test for the new system.

Examples:
  sudo ./install.sh preflight
  sudo ./install.sh usb --device /dev/sdb --mode live --yes
  sudo ./install.sh provision --yes
  sudo ./install.sh tpm2-enroll --yes
  sudo ./install.sh verify --expect-tpm2

Live USB:       boot it, click "Install to Hard Drive"; the kickstart on the
                OEMDRV partition is picked up by Anaconda automatically.
Netinstall:     fully unattended (Anaconda starts by itself).

All stages log to /var/log/fedora-kde/ (override: FEDORA_KDE_LOG_DIR).
EOF
}

main() {
  local stage="${1:-}" script=""
  [[ -n "$stage" ]] || { usage >&2; exit 2; }
  shift
  case "$stage" in
    preflight)     script="preflight.sh" ;;
    usb)           script="build-usb.sh" ;;
    provision)     script="provision.sh" ;;
    tpm2-enroll)   script="tpm2-enroll.sh" ;;
    verify)        script="verify.sh" ;;
    -h|--help|help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  [[ -x "$HERE/scripts/$script" ]] || die "missing stage script: scripts/$script"
  exec "$HERE/scripts/$script" "$@"
}

main "$@"
