#!/usr/bin/env bash
# Stage: usb - build the Fedora 45 KDE installer USB.
#
#   live      : dd the KDE live ISO, then add a FAT partition labelled OEMDRV
#               holding ks.cfg.  Boot it, click "Install to Hard Drive".
#   netinstall: download the Everything netinst ISO; Anaconda starts by itself.
set -Eeuo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"
export FEDORA_KDE_ROOT="${FEDORA_KDE_ROOT:-$(cd -- "$HERE/.." && pwd)}"

DEV=""
OEMDRV_DEV=""
MODE="live"
ISO=""
ISO_SHA=""
LUKS_ENV="${FEDORA_KDE_LUKS_ENV:-}"
PASS_ENV="${FEDORA_KDE_PASS_ENV:-}"
STORE_LUKS=1
AUTO_PROVISION=0
RENDER_ONLY=0
RENDER_DIR=""
TMP_SEC=""

cleanup() {
  if [[ -n "$TMP_SEC" && -d "$TMP_SEC" ]]; then
    rm -rf "$TMP_SEC"
  fi
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
usb [options]

  --device /dev/sdX            USB device to write (required)
  --yes                        skip the typed device confirmation
  --mode live|netinstall       installer media (default: live)
  --oemdrv-device /dev/sdY     put ks.cfg on a separate FAT stick instead
  --iso PATH                   ISO to write (live mode)
  --iso-sha256 HEX             expected ISO sha256 (offline fallback)
  --luks-passphrase-env VAR    read the LUKS passphrase from VAR (else prompt)
  --user-password-env VAR      read the user password from VAR (else prompt)
  --prompt-luks-at-install     do NOT store the LUKS passphrase in ks.cfg
  --auto-provision             enable first-boot auto provisioning
  --render-only --render-dir D render ks.cfg + bundle only (tests)
  --force-unmount              unmount the target if needed
  --dry-run                    validate everything, write nothing
EOF
}

parse_args() {
  while (( $# )); do
    case "$1" in
      --device) DEV="${2:?--device needs a value}"; shift ;;
      --yes) FEDORA_KDE_ASSUME_YES=1; export FEDORA_KDE_ASSUME_YES ;;
      --mode) MODE="${2:?--mode needs a value}"; shift ;;
      --oemdrv-device) OEMDRV_DEV="${2:?--oemdrv-device needs a value}"; shift ;;
      --iso) ISO="${2:?--iso needs a value}"; shift ;;
      --iso-sha256) ISO_SHA="${2:?--iso-sha256 needs a value}"; shift ;;
      --luks-passphrase-env) LUKS_ENV="${2:?needs a value}"; shift ;;
      --user-password-env) PASS_ENV="${2:?needs a value}"; shift ;;
      --prompt-luks-at-install) STORE_LUKS=0 ;;
      --auto-provision) AUTO_PROVISION=1 ;;
      --render-only) RENDER_ONLY=1 ;;
      --render-dir) RENDER_DIR="${2:?--render-dir needs a value}"; shift ;;
      --force-unmount) FEDORA_KDE_FORCE_UNMOUNT=1; export FEDORA_KDE_FORCE_UNMOUNT ;;
      --dry-run) FEDORA_KDE_DRY_RUN=1; export FEDORA_KDE_DRY_RUN ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown argument: $1" ;;
    esac
    shift
  done
  case "$MODE" in live|netinstall) ;; *) die "--mode must be live or netinstall" ;; esac
}

# ---------------------------------------------------------------- secrets
read_secret() {
  local envvar="$1" prompt="$2" value=""
  if [[ -n "$envvar" && -n "${!envvar:-}" ]]; then
    printf '%s' "${!envvar}"
    return 0
  fi
  [[ -t 0 ]] || die "$prompt: no TTY and no env var"
  printf '%s: ' "$prompt" >&2
  read -rs value
  printf '\n' >&2
  printf '%s' "$value"
}

validate_luks_passphrase() {
  local pw="$1"
  (( ${#pw} >= 12 )) || die "LUKS passphrase must be at least 12 characters"
  if [[ "$pw" =~ [[:space:]\"\\#@] ]]; then
    die "LUKS passphrase must not contain whitespace, quotes, backslash, '#' or '@'"
  fi
}

hash_password() {
  local pw="$1" hash
  hash="$(printf '%s' "$pw" | openssl passwd -6 -stdin)"
  [[ "$hash" == \$6\$* ]] || die "could not hash the user password"
  printf '%s' "$hash"
}

sshkey_line() {
  local home_dir f key=""
  home_dir="$(user_home)"
  for f in "$home_dir/.ssh/id_ed25519.pub" "$home_dir/.ssh/id_rsa.pub"; do
    [[ -f "$f" ]] && { key="$(<"$f")"; break; }
  done
  if [[ -n "$key" ]]; then
    printf 'sshkey --username=ldco "%s"' "$key"
  fi
}

# ---------------------------------------------------------------- iso
find_live_iso() {
  [[ -n "$ISO" ]] && return 0
  ISO="$(find /run/media/*/*/LinuxDCO "$HOME/Downloads" -maxdepth 2 \
    -iname '*Fedora-KDE-Desktop-Live-45*.iso' -printf '%T@ %p\n' 2>/dev/null \
    | sort -n | tail -1 | cut -d' ' -f2-)"
  [[ -n "$ISO" ]] || die "live ISO not found; pass --iso"
}

iso_dest_dir() {
  local d
  d="$(dirname -- "${ISO:-$HOME/Downloads/fedora.iso}")"
  [[ -d "$d" ]] || d="$HOME/Downloads"
  printf '%s' "$d"
}

download_netinstall() {
  local dest url sum_url file checksum
  dest="$(iso_dest_dir)"
  file="$dest/Fedora-Everything-netinst-x86_64-45-1.4.iso"
  url="https://download.fedoraproject.org/pub/fedora/linux/releases/45/Everything/x86_64/iso/Fedora-Everything-netinst-x86_64-45-1.4.iso"
  sum_url="${url%/*}/Fedora-Everything-netinst-x86_64-45-1.4-x86_64-CHECKSUM"
  if [[ ! -f "$file" ]]; then
    require_cmd curl
    log "downloading netinstall ISO (about 700 MB) ..."
    curl -fL --progress-bar -o "$file" "$url" || die "netinstall download failed"
  fi
  checksum="$(curl -fsSL --max-time 30 "$sum_url" 2>/dev/null \
    | awk 'toupper($1)=="SHA256"{print $NF; exit}' || true)"
  if [[ -n "$checksum" ]]; then
    if ! printf '%s  %s\n' "$checksum" "$file" | sha256sum -c - >/dev/null; then
      die "netinstall ISO checksum mismatch"
    fi
    ok "netinstall ISO checksum ok"
  else
    warn "netinstall CHECKSUM unavailable; continuing without verification"
  fi
  ISO="$file"
}

verify_iso_hash() {
  local iso="$1" want="$2"
  [[ -n "$want" ]] || return 0
  printf '%s  %s\n' "$want" "$iso" | sha256sum -c - >/dev/null \
    || die "ISO sha256 mismatch"
  ok "ISO sha256 matches --iso-sha256"
}

# ---------------------------------------------------------------- render
render_ks() {
  local mode="$1" out="$2" tmpl common post packages sshline luks_opt
  tmpl="$FEDORA_KDE_ROOT/kickstart/fedora-kde-${mode}.ks.in"
  common="$FEDORA_KDE_ROOT/kickstart/common.ks.in"
  post="$FEDORA_KDE_ROOT/kickstart/post.ks.in"
  packages="$(sed -e 's/^[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$FEDORA_KDE_ROOT/packages/fedora-native.txt")"
  sshline="$(sshkey_line)"
  if [[ "$STORE_LUKS" == 1 ]]; then
    luks_opt="--passphrase=${LUKS_PASSPHRASE}"
  else
    luks_opt=""
  fi
  LUKS_OPT="$luks_opt" USER_HASH="$USER_HASH" SSHKEY_LINE="$sshline" PACKAGES="$packages" \
    python3 - "$tmpl" "$common" "$post" "$out" <<'PY'
import os
import sys

template = open(sys.argv[1], encoding="utf-8").read()
common = open(sys.argv[2], encoding="utf-8").read()
post = open(sys.argv[3], encoding="utf-8").read()
template = template.replace("@INCLUDE_COMMON@", common)
template = template.replace("@INCLUDE_POST@", post)
for key in ("LUKS_OPT", "USER_HASH", "SSHKEY_LINE", "PACKAGES"):
    template = template.replace("@%s@" % key, os.environ.get(key, ""))
open(sys.argv[4], "w", encoding="utf-8").write(template)
PY
  if grep -oE '@[A-Z_]+@' "$out" >/dev/null 2>&1; then
    die "unresolved template token in $out: $(grep -oE '@[A-Z_]+@' "$out" | sort -u | tr '\n' ' ')"
  fi
  ok "kickstart rendered: $out"
}

make_bundle() {
  local out="$1"
  tar -czf "$out" -C "$(dirname -- "$FEDORA_KDE_ROOT")" "$(basename -- "$FEDORA_KDE_ROOT")"
  ok "provisioning bundle: $out ($(du -h "$out" | cut -f1))"
}

# ---------------------------------------------------------------- media
write_iso() {
  local iso="$1" dev="$2"
  require_cmd dd
  log "writing ISO to $dev (this destroys the device)"
  dd if="$iso" of="$dev" bs=8M conv=fsync status=progress
  sync
  ok "ISO written"
}

add_oemdrv_partition() {
  local dev="$1" idx part
  require_cmd sgdisk partprobe mkfs.vfat mount umount udevadm
  log "relocating backup GPT and adding OEMDRV partition"
  sgdisk -e "$dev" >/dev/null
  idx="$(( $(sgdisk -p "$dev" | awk '/^[[:space:]]+[0-9]+/ {n=$1} END{print n+0}') + 1 ))"
  sgdisk -n "${idx}:0:+128M" -t "${idx}:0700" -c "${idx}:OEMDRV" "$dev" >/dev/null
  partprobe "$dev"
  udevadm settle || sleep 2
  part="${dev}${idx}"
  [[ -b "$part" ]] || die "new partition node not found: $part"
  mkfs.vfat -F32 -n OEMDRV "$part" >/dev/null
  printf '%s' "$part"
}

copy_payload() {
  local part="$1" ks="$2" bundle="$3" mnt
  require_cmd mount umount sha256sum
  mnt="$(mktemp -d)"
  mount "$part" "$mnt"
  cp "$ks" "$mnt/ks.cfg"
  cp "$bundle" "$mnt/FedoraKDE.tar.gz"
  if [[ "$AUTO_PROVISION" == 1 ]]; then
    : >"$mnt/auto-provision"
  fi
  sync
  umount "$mnt"
  rmdir "$mnt"

  # verify by re-mounting
  mnt="$(mktemp -d)"
  mount "$part" "$mnt"
  if [[ "$(sha256sum "$mnt/ks.cfg" | awk '{print $1}')" != "$(sha256sum "$ks" | awk '{print $1}')" ]]; then
    umount "$mnt"; rmdir "$mnt"
    die "payload verification failed: ks.cfg differs"
  fi
  umount "$mnt"
  rmdir "$mnt"
  ok "payload verified on $part"
}

print_next_steps() {
  local mode="$1"
  cat <<EOF

============================================================
 USB ready. Next steps:
   1. reboot and open the firmware boot menu (F12 on ASUS TUF)
   2. boot the USB
$(if [[ "$mode" == live ]]; then cat <<'L'
   3. on the live desktop click "Install to Hard Drive"
      (Anaconda reads ks.cfg from the OEMDRV partition)
L
else cat <<'N'
   3. wait - Anaconda starts by itself and installs unattended
      (wired network is required for the netinstall ISO)
N
fi)
   4. after the first Fedora boot:
        sudo /root/FedoraKDE/install.sh provision --yes
        reboot, enroll the MOK key in the blue screen
        sudo /root/FedoraKDE/install.sh tpm2-enroll --yes
        sudo /root/FedoraKDE/install.sh verify
   5. erase/format the OEMDRV partition after the install (it holds
      the user password hash and, unless --prompt-luks-at-install
      was used, the LUKS passphrase).
============================================================
EOF
}

main() {
  parse_args "$@"
  init_log usb

  if [[ "$RENDER_ONLY" == 1 ]]; then
    [[ -n "$RENDER_DIR" ]] || die "--render-only needs --render-dir"
    mkdir -p "$RENDER_DIR"
    LUKS_PASSPHRASE="dummy-luks-passphrase"
    USER_HASH="$(hash_password "dummy-user-password")"
    render_ks "$MODE" "$RENDER_DIR/ks.cfg"
    make_bundle "$RENDER_DIR/FedoraKDE.tar.gz"
    exit 0
  fi

  [[ -n "$DEV" || -n "$OEMDRV_DEV" ]] || die "need --device (or --oemdrv-device)"

  if [[ "$MODE" == netinstall ]]; then
    download_netinstall
  else
    find_live_iso
  fi
  verify_iso_hash "$ISO" "$ISO_SHA"

  # secrets (prompted, never on argv)
  if [[ "$STORE_LUKS" == 1 ]]; then
    LUKS_PASSPHRASE="$(read_secret "$LUKS_ENV" "LUKS passphrase")"
    validate_luks_passphrase "$LUKS_PASSPHRASE"
  else
    LUKS_PASSPHRASE=""
  fi
  local user_password
  user_password="$(read_secret "$PASS_ENV" "Password for user ldco")"
  (( ${#user_password} >= 8 )) || die "user password must be at least 8 characters"
  USER_HASH="$(hash_password "$user_password")"
  unset user_password

  TMP_SEC="$(mktemp -d)"
  chmod 700 "$TMP_SEC"
  render_ks "$MODE" "$TMP_SEC/ks.cfg"
  make_bundle "$TMP_SEC/FedoraKDE.tar.gz"

  if [[ "$FEDORA_KDE_DRY_RUN" == 1 ]]; then
    if [[ -n "$DEV" ]]; then guard_usb_device "$DEV"; fi
    if [[ -n "$OEMDRV_DEV" ]]; then guard_usb_device "$OEMDRV_DEV"; fi
    log "dry-run: would write $ISO and payload to ${DEV:-$OEMDRV_DEV}"
    print_next_steps "$MODE"
    exit 0
  fi

  require_root

  if [[ -n "$DEV" ]]; then
    guard_usb_device "$DEV"
    confirm_or_die "About to DESTROY $DEV (write $ISO, add OEMDRV partition)." "$DEV"
    write_iso "$ISO" "$DEV"
    local part
    part="$(add_oemdrv_partition "$DEV")"
    copy_payload "$part" "$TMP_SEC/ks.cfg" "$TMP_SEC/FedoraKDE.tar.gz"
  fi

  if [[ -n "$OEMDRV_DEV" ]]; then
    guard_usb_device "$OEMDRV_DEV"
    confirm_or_die "About to FORMAT $OEMDRV_DEV as OEMDRV (holds ks.cfg)." "$OEMDRV_DEV"
    require_cmd mkfs.vfat
    mkfs.vfat -F32 -n OEMDRV "$OEMDRV_DEV" >/dev/null
    copy_payload "$OEMDRV_DEV" "$TMP_SEC/ks.cfg" "$TMP_SEC/FedoraKDE.tar.gz"
  fi

  print_next_steps "$MODE"
}

main "$@"
