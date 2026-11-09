#!/usr/bin/env bash
# Stage: verify - read-only acceptance test. Exit 1 if any check FAILs.
set -Eeuo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"
export FEDORA_KDE_ROOT="${FEDORA_KDE_ROOT:-$(cd -- "$HERE/.." && pwd)}"

EXPECT_TPM2=0
PASS=0
FAIL=0
SKIP=0

usage() {
  cat <<'EOF'
verify [--expect-tpm2]

Checks the Fedora 45 install, driver stack, desktop, hardening,
snapshots, sleep policy and the package report. Read-only.
EOF
}

parse_args() {
  while (( $# )); do
    case "$1" in
      --expect-tpm2) EXPECT_TPM2=1 ;;
      --dry-run) : ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown argument: $1" ;;
    esac
    shift
  done
}

pass()   { PASS=$((PASS + 1)); printf 'PASS  %-3s %s\n' "$1" "$2"; }
failit() { FAIL=$((FAIL + 1)); printf 'FAIL  %-3s %s\n' "$1" "$2"; }
skipit() { SKIP=$((SKIP + 1)); printf 'SKIP  %-3s %s\n' "$1" "$2"; }

num() { local c; c="$(grep -cE '^[[:space:]]*plugin=org\.kde\.panel[[:space:]]*$' "$1" 2>/dev/null || true)"; printf '%s' "${c:-0}"; }

plasma_version() {
  local v=""
  v="$(timeout 8 plasmashell --version 2>/dev/null | head -1 || true)"
  if [[ -z "$v" ]]; then
    v="$(rpm -q --qf '%{VERSION}' plasma-workspace 2>/dev/null || true)"
  fi
  printf '%s' "$v"
}

check_01() {
  if rpm -q fedora-release 2>/dev/null | grep -q 'release 45' && [[ -f /etc/fedora-kde/installed ]]; then
    pass 01 "Fedora release 45 and /etc/fedora-kde/installed"
  else
    failit 01 "Fedora release 45 marker missing"
  fi
}

check_02() {
  local fs src
  fs="$(findmnt -no FSTYPE /)"
  src="$(findmnt -no SOURCE /)"
  if [[ "$fs" == btrfs && "$src" == /dev/mapper/luks-* ]]; then
    pass 02 "/ on LUKS btrfs ($src)"
  else
    failit 02 "/ is $fs on $src (expected LUKS btrfs)"
  fi
}

check_03() {
  local want missing=""
  for want in @ @home @log @cache @srv @root @var-tmp; do
    btrfs subvolume list / 2>/dev/null | grep -qE "path ${want}\$" || missing="$missing $want"
  done
  if [[ -z "$missing" ]]; then
    pass 03 "btrfs subvolumes present"
  else
    failit 03 "missing subvolumes:$missing"
  fi
}

check_04() {
  local fs blocks
  fs="$(findmnt -no FSTYPE /boot)"
  blocks="$(df -k /boot/efi | awk 'NR==2{print $2}')"
  if [[ "$fs" == ext4 ]] && (( blocks >= 921600 )); then
    pass 04 "/boot ext4, ESP ${blocks}K"
  else
    failit 04 "/boot=$fs, ESP=${blocks}K (need ext4, >=921600K)"
  fi
}

check_05() {
  local alg sw
  alg="$(cat /sys/block/zram0/comp_algorithm 2>/dev/null || true)"
  sw="$(sysctl -n vm.swappiness 2>/dev/null || true)"
  if swapon --show=NAME --noheadings 2>/dev/null | grep -qx '/dev/zram0' \
     && [[ "$alg" == *zstd* ]] && [[ "$sw" == 133 ]]; then
    pass 05 "zram0 zstd, swappiness 133"
  else
    failit 05 "zram/swappiness wrong (zram alg='${alg}', swappiness=${sw})"
  fi
}

check_06() {
  local enf state
  enf="$(getenforce 2>/dev/null || echo Disabled)"
  state="$(systemctl is-active firewalld 2>/dev/null || true)"
  if [[ "$enf" == Enforcing ]] && [[ "$state" == active ]] \
     && [[ "$(firewall-cmd --state 2>/dev/null || true)" == running ]]; then
    pass 06 "SELinux enforcing, firewalld running"
  else
    failit 06 "SELinux=$enf, firewalld=$state"
  fi
}

check_07() {
  local gpu ver
  gpu="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || true)"
  ver="$(modinfo -F version nvidia 2>/dev/null || true)"
  if [[ "$gpu" == *"RTX 3070"* ]] && [[ -n "$ver" ]] && lsmod | grep -q '^nvidia '; then
    pass 07 "NVIDIA $gpu, driver $ver"
  else
    failit 07 "NVIDIA stack incomplete (gpu='${gpu}', driver='${ver}')"
  fi
}

check_08() {
  local out=""
  if ! systemctl is-active --quiet switcheroo-control; then
    failit 08 "switcheroo-control is not active"
    return
  fi
  if ! have glxinfo || [[ -z "${DISPLAY:-}" && ! -S /tmp/.X11-unix/X0 ]]; then
    skipit 08 "switcheroo active; PRIME glxinfo needs a graphical session"
    return
  fi
  out="$(__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia glxinfo -B 2>/dev/null | head -5 || true)"
  if [[ "$out" == *NVIDIA* ]]; then
    pass 08 "PRIME render offload reports NVIDIA"
  else
    failit 08 "PRIME offload did not report NVIDIA"
  fi
}

check_09() {
  local profile=""
  if ! systemctl is-active --quiet asusd; then
    failit 09 "asusd is not active"
    return
  fi
  profile="$(asusctl profile -p 2>/dev/null || true)"
  if [[ "$profile" == *Balanced* ]]; then
    pass 09 "asusd active, profile Balanced"
  else
    failit 09 "asusd active but profile is '${profile}'"
  fi
}

check_10() {
  local ver scheme home panels
  home="$(user_home)"
  ver="$(plasma_version)"
  scheme="$(kreadconfig6 --file "$home/.config/kdeglobals" --group KDE --key ColorScheme 2>/dev/null || true)"
  panels="$(num "$home/.config/plasma-org.kde.plasma.desktop-appletsrc")"
  if [[ "$ver" == 6.8* ]] && [[ "$scheme" == BreezeDark ]] \
     && fc-match 'Fira Sans' 2>/dev/null | grep -qi fira; then
    pass 10 "Plasma $ver, BreezeDark, Fira Sans resolves"
  else
    failit 10 "desktop state wrong (plasma='${ver}', scheme='${scheme}')"
  fi
  if [[ "$panels" == 4 ]]; then
    pass 10b "4 panels in the applet config"
  else
    failit 10b "$panels panels (expected 4)"
  fi
}

check_11() {
  local unit missing="" lines
  for unit in snapper-timeline.timer snapper-cleanup.timer grub-btrfsd; do
    [[ "$(systemctl is-enabled "$unit" 2>/dev/null || true)" == enabled ]] || missing="$missing $unit"
  done
  lines="$(snapper -c root list 2>/dev/null | wc -l)"
  if [[ -z "$missing" ]] && (( lines > 2 )); then
    pass 11 "snapper timers + grub-btrfsd enabled, $lines snapshot rows"
  else
    failit 11 "snapshots incomplete (missing:${missing:-none}, rows=$lines)"
  fi
}

check_12() {
  local unit="" u conf=/etc/dnf/automatic.conf
  for u in dnf-automatic.timer dnf5-automatic.timer; do
    if [[ "$(systemctl is-enabled "$u" 2>/dev/null || true)" == enabled ]]; then unit="$u"; break; fi
  done
  if [[ -n "$unit" ]] && grep -qE '^upgrade_type[[:space:]]*=[[:space:]]*security' "$conf"; then
    pass 12 "automatic security updates ($unit)"
  else
    failit 12 "automatic updates not configured (unit='${unit:-none}')"
  fi
}

check_13() {
  local suspend
  suspend="$(systemctl is-enabled suspend.target 2>/dev/null || true)"
  if [[ "$suspend" == masked ]] \
     && grep -q 'nvidia_drm.modeset=1' /proc/cmdline \
     && ! grep -q 'nvidia_drm.fbdev=1' /proc/cmdline \
     && ! grep -q 'mem_sleep_default=deep' /proc/cmdline \
     && ! grep -rqs 'NVreg_EnableGpuFirmware=0' /etc/modprobe.d/; then
    pass 13 "suspend masked, safe kernel parameters"
  else
    failit 13 "sleep policy/parameters wrong (suspend='${suspend}')"
  fi
}

check_14() {
  if [[ "$(systemctl is-enabled fwupd-refresh.timer 2>/dev/null || true)" == enabled ]] \
     && fwupdmgr get-devices >/dev/null 2>&1; then
    pass 14 "fwupd enabled and responding"
  else
    failit 14 "fwupd not ready"
  fi
}

check_15() {
  if (( ! EXPECT_TPM2 )); then
    skipit 15 "TPM2 not requested (--expect-tpm2)"
    return
  fi
  local src mapper dev dump slots
  src="$(findmnt -no SOURCE /)"
  mapper="$(basename "$src")"
  dev="$(cryptsetup status "$mapper" 2>/dev/null | awk '/device:/{print $2; exit}')"
  dump="$(cryptsetup luksDump "$dev" 2>/dev/null || true)"
  slots="$(printf '%s\n' "$dump" | sed -n '/^Keyslots:/,/^Tokens:/p' | grep -cE '^[[:space:]]+[0-9]+: luks2' || true)"
  if [[ "$dump" == *systemd-tpm2* ]] && (( slots >= 2 )); then
    pass 15 "TPM2 token + passphrase slot on $dev"
  else
    failit 15 "TPM2 token/slots missing on ${dev:-?} (slots=$slots)"
  fi
}

check_16() {
  local report fails manual
  report="$(find "$FEDORA_KDE_ROOT/packages" -maxdepth 1 -name 'report-*.tsv' -printf '%T@ %p\n' 2>/dev/null \
    | sort -n | tail -1 | cut -d' ' -f2-)"
  if [[ -z "$report" || ! -f "$report" ]]; then
    failit 16 "no packages/report-*.tsv found"
    return
  fi
  fails="$(awk -F'\t' '$4=="FAIL"' "$report" | wc -l)"
  manual="$(awk -F'\t' '$4=="MANUAL"{print $1" -> "$2}' "$report" || true)"
  if (( fails == 0 )); then
    pass 16 "package report clean ($report)"
  else
    failit 16 "$fails FAIL rows in $report"
  fi
  if [[ -n "$manual" ]]; then
    printf '\nMANUAL packages to install by hand:\n%s\n' "$manual"
  fi
}

main() {
  parse_args "$@"
  init_log verify
  printf '%-6s %s\n' 'RESULT' 'CHECK'
  check_01; check_02; check_03; check_04; check_05; check_06; check_07; check_08
  check_09; check_10; check_11; check_12; check_13; check_14; check_15; check_16
  printf '\nsummary: %d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
  (( FAIL == 0 )) || exit 1
}

main "$@"
