#!/usr/bin/env bash
# Stage: tpm2-enroll - LUKS2 auto-unlock via TPM2, bound to PCR 7 only.
# MUST run last: after Secure Boot is on, the MOK is enrolled and the
# nvidia module loads.  PCR 7 changes when the Secure Boot state/keys
# change, so enrolling before that would silently break unlock.
set -Eeuo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

usage() {
  cat <<'EOF'
tpm2-enroll [--yes]

Refuses unless: Secure Boot enabled, efivar SecureBoot == 1, nvidia loaded.
Prints the rollback command when done.
EOF
}

parse_args() {
  while (( $# )); do
    case "$1" in
      --yes) FEDORA_KDE_ASSUME_YES=1; export FEDORA_KDE_ASSUME_YES ;;
      --dry-run) FEDORA_KDE_DRY_RUN=1; export FEDORA_KDE_DRY_RUN ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown argument: $1" ;;
    esac
    shift
  done
}

secureboot_on() {
  local efivar
  efivar="$(find /sys/firmware/efi/efivars -maxdepth 1 -name 'SecureBoot-*' 2>/dev/null | head -1)"
  [[ -n "$efivar" ]] || return 1
  # 4-byte efivar header, then the byte value
  [[ "$(od -An -t u1 -j 4 -N 1 "$efivar" | xargs)" == 1 ]]
}

luks_device() {
  local src mapper
  src="$(findmnt -no SOURCE /)"
  [[ "$src" == /dev/mapper/* ]] || die "root is not on a LUKS mapper ($src)"
  mapper="$(basename "$src")"
  cryptsetup status "$mapper" | awk '/device:/{print $2; exit}'
}

main() {
  parse_args "$@"
  init_log tpm2-enroll
  [[ "$FEDORA_KDE_DRY_RUN" == 1 ]] || require_root

  if ! secureboot_on; then
    die "Secure Boot is not enabled (efivar SecureBoot != 1); enable it in BIOS first"
  fi
  if have mokutil && ! mokutil --sb-state 2>/dev/null | grep -qi 'SecureBoot enabled'; then
    die "mokutil reports Secure Boot disabled"
  fi
  if ! lsmod | grep -q '^nvidia '; then
    die "the nvidia module is not loaded; finish the MOK enrollment and reboot first"
  fi

  local dev
  dev="$(luks_device)"
  [[ -b "$dev" ]] || die "cannot resolve the LUKS device"
  log "LUKS device: $dev"

  if cryptsetup luksDump "$dev" | grep -q 'systemd-tpm2'; then
    ok "a systemd-tpm2 token is already enrolled"
    exit 0
  fi

  if [[ "$FEDORA_KDE_DRY_RUN" == 1 ]]; then
    log "dry-run: would run systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 $dev"
    exit 0
  fi
  systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 "$dev"
  cryptsetup luksDump "$dev" | grep -q 'systemd-tpm2' || die "TPM2 token missing after enrollment"
  if [[ "$(cryptsetup luksDump "$dev" | sed -n '/^Keyslots:/,/^Tokens:/p' | grep -cE '^[[:space:]]+[0-9]+: luks2')" -lt 2 ]]; then
    warn "only one keyslot found; verify the passphrase slot with: cryptsetup luksDump $dev"
  fi
  ok "TPM2 auto-unlock enrolled (PCR 7)"
  cat <<EOF

Rollback if unlock fails:
  sudo systemd-cryptenroll --wipe-slot=tpm2 $dev

The passphrase keyslot is retained as the recovery path.
EOF
}

main "$@"
