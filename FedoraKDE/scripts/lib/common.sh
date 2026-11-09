#!/usr/bin/env bash
# shellcheck shell=bash
# FedoraKDE common library: logging, guards, state markers, Fedora helpers.
# Sourced by every stage script. Never executed on its own.

set -Eeuo pipefail

: "${FEDORA_KDE_LOG_DIR:=/var/log/fedora-kde}"
: "${FEDORA_KDE_STATE_DIR:=${FEDORA_KDE_LOG_DIR}/state}"
: "${FEDORA_KDE_ACTIVE_LOG:=}"
: "${FEDORA_KDE_DRY_RUN:=0}"
: "${FEDORA_KDE_SELFTEST:=0}"
: "${FEDORA_KDE_ASSUME_YES:=0}"
: "${FEDORA_KDE_USER:=ldco}"
: "${FEDORA_KDE_FORCE_UNMOUNT:=0}"
: "${FEDORA_KDE_TARGET_MODEL:=INTEL SSDPEKNU512GZ}"

# ---------------------------------------------------------------- logging
_fk_line() {
  local line
  line="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  printf '%s\n' "$line"
  if [[ -n "$FEDORA_KDE_ACTIVE_LOG" ]]; then
    printf '%s\n' "$line" >>"$FEDORA_KDE_ACTIVE_LOG"
  fi
}

log()  { _fk_line "INFO  $*"; }
ok()   { _fk_line "OK    $*"; }
warn() { _fk_line "WARN  $*" >&2; }
die()  { _fk_line "FAIL  $*" >&2; exit 1; }

init_log() {
  local stage="$1"
  if ! mkdir -p "$FEDORA_KDE_LOG_DIR" "$FEDORA_KDE_STATE_DIR" 2>/dev/null; then
    FEDORA_KDE_LOG_DIR="${TMPDIR:-/tmp}/fedora-kde"
    FEDORA_KDE_STATE_DIR="$FEDORA_KDE_LOG_DIR/state"
    mkdir -p "$FEDORA_KDE_STATE_DIR"
    export FEDORA_KDE_LOG_DIR FEDORA_KDE_STATE_DIR
  fi
  if [[ -z "$FEDORA_KDE_ACTIVE_LOG" ]]; then
    FEDORA_KDE_ACTIVE_LOG="$FEDORA_KDE_LOG_DIR/${stage}-$(date +%Y%m%d-%H%M%S).log"
    export FEDORA_KDE_ACTIVE_LOG
  fi
  ln -sfn "$FEDORA_KDE_ACTIVE_LOG" "$FEDORA_KDE_LOG_DIR/last.log" 2>/dev/null || true
  log "=== FedoraKDE stage: $stage (dry-run=$FEDORA_KDE_DRY_RUN) ==="
}

redact() {
  sed -E 's/([Pp]ass(phrase|word)|LUKS_PASSPHRASE|USER_HASH|MOK_PASSWORD)=[^[:space:]]+/\1=[redacted]/g'
}

# ---------------------------------------------------------------- guards
require_root() {
  [[ ${EUID} -eq 0 ]] || die "this stage must run as root"
}

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "required command not found: $c"
  done
}

have() { command -v "$1" >/dev/null 2>&1; }

confirm_or_die() {
  local prompt="$1" token="${2:-ACCEPT}" answer=""
  if [[ "${FEDORA_KDE_ASSUME_YES}" == 1 ]]; then
    ok "auto-confirmed: $prompt"
    return 0
  fi
  printf '\n%s\n' "$prompt" >&2
  printf 'Type exactly "%s" to continue: ' "$token" >&2
  read -r answer || true
  [[ "$answer" == "$token" ]] || die "confirmation failed; aborted"
}

# ---------------------------------------------------------------- state
state_mark()  { mkdir -p "$FEDORA_KDE_STATE_DIR"; : >"$FEDORA_KDE_STATE_DIR/$1"; }
state_check() { [[ -f "$FEDORA_KDE_STATE_DIR/$1" ]]; }
state_clear() { rm -f "$FEDORA_KDE_STATE_DIR/$1"; }
state_set()   { mkdir -p "$FEDORA_KDE_STATE_DIR"; printf '%s\n' "$2" >"$FEDORA_KDE_STATE_DIR/$1"; }
state_get()   { [[ -f "$FEDORA_KDE_STATE_DIR/$1" ]] && cat "$FEDORA_KDE_STATE_DIR/$1" || true; }
resume_point() { state_mark "resume-$1"; ok "resume point recorded: $1"; }

retry() {
  local tries="$1" delay="$2" i
  shift 2
  for ((i = 1; i <= tries; i++)); do
    if "$@"; then return 0; fi
    warn "attempt $i/$tries failed: $*"
    sleep "$delay"
  done
  return 1
}

# ---------------------------------------------------------------- fedora
dnf_install() {
  dnf -y install --setopt=install_weak_deps=False "$@"
}

grub_cfg_path() {
  if [[ -d /boot/grub2 ]]; then
    printf '%s\n' /boot/grub2/grub.cfg
  else
    printf '%s\n' /boot/grub/grub.cfg
  fi
}

grub_append_params() {
  local file=/etc/default/grub
  [[ -f "$file" ]] || die "$file not found"
  python3 - "$@" <<'PY'
import re
import sys

path = "/etc/default/grub"
params = sys.argv[1:]
text = open(path, encoding="utf-8").read()
match = re.search(r'^GRUB_CMDLINE_LINUX="(.*)"$', text, re.M)
current = match.group(1).split() if match else []
for param in params:
    if param not in current:
        current.append(param)
line = 'GRUB_CMDLINE_LINUX="%s"' % " ".join(current)
if match:
    text = text[: match.start()] + line + text[match.end() :]
else:
    text = text.rstrip("\n") + "\n" + line + "\n"
open(path, "w", encoding="utf-8").write(text)
PY
}

grub_regenerate() {
  local cfg
  cfg="$(grub_cfg_path)"
  grub2-mkconfig -o "$cfg" 2>&1 | tail -n 5
}

append_line_once() {
  local file="$1" line="$2"
  touch "$file"
  grep -qxF "$line" "$file" || printf '%s\n' "$line" >>"$file"
}

target_user() { printf '%s\n' "$FEDORA_KDE_USER"; }

as_user() {
  local user
  user="$(target_user)"
  if [[ ${EUID} -eq 0 && "$(id -un)" != "$user" ]]; then
    sudo -u "$user" -H -- "$@"
  else
    "$@"
  fi
}

user_home() {
  local user
  user="$(target_user)"
  getent passwd "$user" | cut -d: -f6
}

# ---------------------------------------------------------------- devices
_device_bytes() { blockdev --getsize64 "$1" 2>/dev/null || echo 0; }

_byid_links() {
  find /dev/disk/by-id -maxdepth 1 -lname "*$(basename -- "$1")" -printf '%f\n' 2>/dev/null || true
}

_is_mounted() {
  local dev="$1" mp
  if [[ "${FEDORA_KDE_SELFTEST}" == 1 && "${FEDORA_KDE_TEST_MOUNTED:-}" == "$dev" ]]; then
    return 0
  fi
  if findmnt -S "$dev" -n >/dev/null 2>&1; then
    return 0
  fi
  while read -r mp; do
    [[ -n "$mp" ]] && return 0
  done < <(lsblk -nro MOUNTPOINTS "$dev" 2>/dev/null)
  return 1
}

guard_usb_device() {
  local dev="$1" links bytes
  if [[ "$FEDORA_KDE_SELFTEST" == 1 && "$dev" == /dev/fakeusb* ]]; then
    links=""
    bytes=$((16 * 1024 * 1024 * 1024))
  else
    [[ -b "$dev" ]] || die "not a block device: $dev"
    links="$(_byid_links "$dev")"
  if grep -qiE 'WD_Blue_SN570|214118459703' <<<"$links"; then
    die "refusing: $dev is the WD SN570 backup disk (by-id: $(tr '\n' ' ' <<<"$links"))"
  fi
  if [[ "$(basename -- "$dev")" == nvme* ]] || grep -q '^nvme-' <<<"$links"; then
    die "refusing: $dev is an NVMe device; USB targets only"
  fi
    bytes="$(_device_bytes "$dev")"
  fi
  if (( bytes < 8589934592 )); then
    die "refusing: $dev is smaller than 8 GiB (${bytes} bytes)"
  fi
  if _is_mounted "$dev"; then
    if [[ "$FEDORA_KDE_FORCE_UNMOUNT" == 1 ]]; then
      warn "unmounting filesystems on $dev (--force-unmount)"
      while read -r mp; do
        [[ -n "$mp" ]] && umount "$mp"
      done < <(lsblk -nro MOUNTPOINTS "$dev" 2>/dev/null)
    else
      die "refusing: $dev has mounted filesystems (use --force-unmount)"
    fi
  fi
  ok "USB device accepted: $dev ($((bytes / 1024 / 1024 / 1024)) GiB)"
}

guard_target_disk() {
  local dev="$1" model links
  dev="$(readlink -f "$dev")"
  [[ -b "$dev" ]] || die "target is not a block device: $dev"
  model="$(cat "/sys/block/$(basename -- "$dev")/device/model" 2>/dev/null | xargs || true)"
  links="$(_byid_links "$dev")"
  if grep -qiE 'WD_Blue_SN570|214118459703' <<<"$links $model"; then
    die "refusing: target $dev is the WD SN570 backup disk"
  fi
  if [[ "$model" != "$FEDORA_KDE_TARGET_MODEL" ]]; then
    die "refusing: $dev model '$model' != expected '$FEDORA_KDE_TARGET_MODEL'"
  fi
  ok "install target accepted: $dev ($model)"
}
