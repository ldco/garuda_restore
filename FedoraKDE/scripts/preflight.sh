#!/usr/bin/env bash
# Stage: preflight - read-only checks on the current Garuda system.
set -Eeuo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"
export FEDORA_KDE_ROOT="${FEDORA_KDE_ROOT:-$(cd -- "$HERE/.." && pwd)}"

HOME_DIR="${FEDORA_KDE_HOME:-$HOME}"
BACKUP_DIR="${FEDORA_KDE_BACKUP_DIR:-}"
BACKUP_TARBALL="${FEDORA_KDE_BACKUP_TARBALL:-}"
ISO="${FEDORA_KDE_ISO:-}"
ISO_SHA=""
TARGET="${FEDORA_KDE_TARGET:-/dev/nvme1n1}"
ACCEPT_MANIFEST=0
ACCEPT_NO_SECUREBOOT=0
HARD_FAIL=0

usage() {
  cat <<'EOF'
preflight [options]

  --accept-manifest        accept the generated data-triage manifest
  --no-secureboot          acknowledge that Secure Boot is disabled
  --target /dev/DEV        install target (default: /dev/nvme1n1)
  --iso PATH               Fedora KDE live ISO
  --iso-sha256 HEX         expected ISO sha256 (offline fallback)
  --backup-dir DIR         directory holding garuda-backup-*-last.tar.gz
  --dry-run                perform the gate, then stop before network/ISO work
EOF
}

hard_fail() { warn "HARD: $*"; HARD_FAIL=1; }

parse_args() {
  while (( $# )); do
    case "$1" in
      --accept-manifest) ACCEPT_MANIFEST=1 ;;
      --no-secureboot) ACCEPT_NO_SECUREBOOT=1 ;;
      --target) TARGET="${2:?--target needs a value}"; shift ;;
      --iso) ISO="${2:?--iso needs a value}"; shift ;;
      --iso-sha256) ISO_SHA="${2:?--iso-sha256 needs a value}"; shift ;;
      --backup-dir) BACKUP_DIR="${2:?--backup-dir needs a value}"; shift ;;
      --dry-run) FEDORA_KDE_DRY_RUN=1; export FEDORA_KDE_DRY_RUN ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown argument: $1" ;;
    esac
    shift
  done
}

detect_backup_dir() {
  [[ -n "$BACKUP_DIR" ]] && return 0
  local d
  while read -r d; do
    [[ -d "$d" ]] || continue
    BACKUP_DIR="$d"
    return 0
  done < <(printf '%s\n' /run/media/*/*/LinuxDCO/backups /run/media/*/*/backups "$HOME/garuda-backup" 2>/dev/null)
  return 1
}

detect_tarball() {
  [[ -n "$BACKUP_TARBALL" ]] && return 0
  detect_backup_dir || die "no backup directory found; pass --backup-dir"
  BACKUP_TARBALL="$(find "$BACKUP_DIR" -maxdepth 1 -name 'garuda-backup-*-last.tar.gz' \
    -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)"
  [[ -n "$BACKUP_TARBALL" ]] || die "no garuda-backup-*-last.tar.gz in $BACKUP_DIR"
}

detect_iso() {
  [[ -n "$ISO" ]] && return 0
  ISO="$(find /run/media/*/*/LinuxDCO "$HOME/Downloads" -maxdepth 2 \
    -iname '*Fedora-KDE-Desktop-Live-45*.iso' -printf '%T@ %p\n' 2>/dev/null \
    | sort -n | tail -1 | cut -d' ' -f2-)"
  [[ -n "$ISO" ]] || die "Fedora KDE 45 ISO not found; pass --iso"
}

check_backup() {
  log "backup tarball: $BACKUP_TARBALL"
  [[ -f "$BACKUP_TARBALL" ]] || { hard_fail "backup tarball missing"; return; }
  local size
  size="$(stat -c %s "$BACKUP_TARBALL")"
  if [[ "$FEDORA_KDE_DRY_RUN" != 1 ]] && (( size < 5 * 1024 * 1024 * 1024 )); then
    hard_fail "backup tarball is suspiciously small (${size} bytes)"
  fi
  local age_h
  age_h="$(( ( $(date +%s) - $(stat -c %Y "$BACKUP_TARBALL") ) / 3600 ))"
  if (( age_h > 72 )); then warn "backup is ${age_h}h old (>72h); run scripts/backup.sh first"; fi
  ok "backup size ${size} bytes, age ${age_h}h"
  if [[ "$FEDORA_KDE_DRY_RUN" == 1 ]]; then
    log "dry-run: skipping gzip integrity scan"
    return
  fi
  log "verifying gzip integrity (this reads the whole archive) ..."
  if gzip -t "$BACKUP_TARBALL"; then
    ok "gzip integrity ok"
  else
    hard_fail "gzip integrity check failed"
  fi
  if tar -tzf "$BACKUP_TARBALL" 2>/dev/null | grep -qm1 'packages/explicitly-installed.txt'; then
    ok "tarball contains packages/explicitly-installed.txt"
  else
    hard_fail "tarball does not look like a garuda backup"
  fi
}

build_manifest() {
  local out="$1"
  {
    printf '# FedoraKDE data-triage manifest\n'
    printf 'generated: %s\nhost: %s\nhome: %s\n' "$(date -Is)" "$(uname -n)" "$HOME_DIR"
    printf 'tarball: %s (%s)\n' "$BACKUP_TARBALL" "$(du -h "$BACKUP_TARBALL" | cut -f1)"
    printf '\n## Home top-level usage\n'
    du -xhd1 "$HOME_DIR" 2>/dev/null | sort -h
    printf '\n## Backup top-level entries\n'
    if [[ "$FEDORA_KDE_DRY_RUN" == 1 ]]; then
      printf '(dry-run: not scanned)\n'
    else
      tar -tzf "$BACKUP_TARBALL" 2>/dev/null | awk -F/ 'NF>1 && $2!=""{print $2}' | sort -u
    fi
    printf '\n## Backup disk free space\n'
    df -h "$BACKUP_DIR" 2>/dev/null | tail -1
    printf '\n## Large home dirs (>=1 GiB) with no obvious backup counterpart\n'
    local size dir name
    while read -r size dir; do
      [[ -n "$dir" && "$dir" != "$HOME_DIR" ]] || continue
      name="$(basename -- "$dir")"
      case "$name" in
        .config|.fonts|.cache|config|dotfiles|wallpapers|Pictures|.local|.ssh|.gnupg) continue ;;
      esac
      if (( size >= 1073741824 )); then
        printf '%s\t%s\n' "$(numfmt --to=iec "$size")" "$dir"
      fi
    done < <(du -xhd1 --block-size=1 "$HOME_DIR" 2>/dev/null)
    printf '\n## Note\n'
    printf 'The tarball covers config/, dotfiles/, .fonts/, wallpapers/,\n'
    printf 'packages/ and installed-software/.  Everything listed under\n'
    printf '"Large home dirs" above is NOT preserved unless you copy it now.\n'
  } >"$out"
}

check_manifest() {
  mkdir -p "$FEDORA_KDE_LOG_DIR"
  local manifest
  manifest="$FEDORA_KDE_LOG_DIR/manifest-$(date +%Y%m%d-%H%M%S).txt"
  build_manifest "$manifest"
  log "manifest written: $manifest"
  cat "$manifest"
  if [[ "$ACCEPT_MANIFEST" != 1 ]]; then
    die "data-triage manifest not accepted; review it and re-run with --accept-manifest"
  fi
  state_mark "manifest-accepted"
  ok "manifest accepted"
}

resolve_wd() {
  find /dev/disk/by-id -maxdepth 1 -name 'nvme-WD_Blue_SN570_1TB_*' ! -name '*-part*' \
    -printf '%l\n' 2>/dev/null | head -1
}

check_disks() {
  guard_target_disk "$TARGET"
  local wd
  wd="$(resolve_wd)"
  if [[ -n "$wd" ]]; then
    log "backup disk: $wd ($(readlink -f "$wd"))"
  else
    warn "WD SN570 backup disk not found by id"
  fi
  lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,MOUNTPOINTS "$TARGET" ${wd:+"$wd"} 2>/dev/null || true
}

verify_sha() {
  local iso="$1" want="$2" got
  got="$(sha256sum "$iso" | awk '{print $1}')"
  [[ "${got,,}" == "${want,,}" ]]
}

checksum_from_fedora() {
  local base="$1" sum="" url
  local -a urls=(
    "https://download.fedoraproject.org/pub/fedora/linux/releases/45/KDE/x86_64/iso/Fedora-KDE-Desktop-Live-45-1.4-x86_64-CHECKSUM"
    "https://download.fedoraproject.org/pub/fedora/linux/releases/45/KDE/x86_64/iso/Fedora-KDE-Desktop-Live-45-1.4.x86_64-CHECKSUM"
    "https://fedoraproject.org/kde/download/checksum/Fedora-KDE-Desktop-Live-45-1.4-x86_64-CHECKSUM"
  )
  for url in "${urls[@]}"; do
    sum="$(curl -fsSL --max-time 25 "$url" 2>/dev/null \
      | awk -v f="$base" 'toupper($1)=="SHA256" && index($0,f){print $NF; exit}' || true)"
    [[ -n "$sum" ]] && { printf '%s\n' "$sum"; return 0; }
  done
  return 1
}

check_iso() {
  log "ISO: $ISO"
  [[ -f "$ISO" ]] || { hard_fail "ISO not found: $ISO"; return; }
  local bytes
  bytes="$(stat -c %s "$ISO")"
  if (( bytes < 3400000000 )); then hard_fail "ISO too small: ${bytes} bytes"; fi
  if [[ -n "$ISO_SHA" ]]; then
    verify_sha "$ISO" "$ISO_SHA" && ok "ISO sha256 matches --iso-sha256" \
      || hard_fail "ISO sha256 does not match --iso-sha256"
    return
  fi
  if [[ "$FEDORA_KDE_DRY_RUN" == 1 ]]; then
    log "dry-run: skipping Fedora CHECKSUM download"
    return
  fi
  local base sum
  base="$(basename -- "$ISO")"
  if sum="$(checksum_from_fedora "$base")"; then
    verify_sha "$ISO" "$sum" && ok "ISO sha256 matches Fedora CHECKSUM" \
      || hard_fail "ISO sha256 mismatch against Fedora CHECKSUM"
  else
    hard_fail "could not download Fedora CHECKSUM; pass --iso-sha256 <hash>"
  fi
}

check_secureboot() {
  local sb="unknown"
  if have mokutil; then
    if mokutil --sb-state 2>/dev/null | grep -qi 'SecureBoot enabled'; then sb=enabled; else sb=disabled; fi
  fi
  if [[ -b /dev/tpm0 ]]; then log "TPM2: present (/dev/tpm0)"; else warn "TPM2: /dev/tpm0 not found"; fi
  log "Secure Boot: $sb"
  if have bootctl; then bootctl status 2>/dev/null | sed -n '1,8p' || true; fi
  if [[ "$sb" == enabled ]]; then
    state_set secureboot 1
    ok "Secure Boot enabled - hardened path available"
  else
    state_set secureboot 0
    if [[ "$ACCEPT_NO_SECUREBOOT" == 1 ]]; then
      warn "Secure Boot disabled (acknowledged with --no-secureboot); TPM2 enrollment will refuse"
    else
      warn "Secure Boot disabled. Enable it in BIOS for the hardened path, or pass --no-secureboot."
    fi
  fi
}

main() {
  parse_args "$@"
  init_log preflight
  detect_tarball
  detect_iso
  detect_backup_dir || true

  check_backup
  check_manifest
  check_disks
  check_iso
  check_secureboot

  if [[ "$FEDORA_KDE_DRY_RUN" == 1 ]]; then
    log "dry-run complete; no network writes, no device writes"
  fi

  if (( HARD_FAIL )); then
    die "preflight failed; fix the HARD items above"
  fi
  ok "preflight passed"
}

main "$@"
