#!/usr/bin/env bash
# Stage: nvidia - RPM Fusion akmod driver, MOK signing, hybrid-GPU config.
# Exit 3 means: a reboot is required (MOK enrollment pending).
set -Eeuo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

AUTO=0
DER=/etc/pki/akmods/certs/public_key.der
CA_TEMPLATE=/etc/pki/akmods/cacert.config.in

usage() {
  cat <<'EOF'
nvidia [options]

  --auto     non-interactive; pipeline the MOK password and write it to
             /etc/fedora-kde/mok-password (0600) for the blue MOK screen
  --yes      accept without prompting
  --dry-run  print the plan
EOF
}

parse_args() {
  while (( $# )); do
    case "$1" in
      --auto) AUTO=1; FEDORA_KDE_ASSUME_YES=1; export FEDORA_KDE_ASSUME_YES ;;
      --yes) FEDORA_KDE_ASSUME_YES=1; export FEDORA_KDE_ASSUME_YES ;;
      --dry-run) FEDORA_KDE_DRY_RUN=1; export FEDORA_KDE_DRY_RUN ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown argument: $1" ;;
    esac
    shift
  done
}

install_driver() {
  dnf_install akmod-nvidia xorg-x11-drv-nvidia-cuda
  if ! dnf_install nvidia-prime-rtd3pm; then
    warn "ALT: nvidia-prime-rtd3pm not available; trying xorg-x11-drv-nvidia-power"
    dnf_install xorg-x11-drv-nvidia-power || warn "ALT: RTD3 power package missing; dGPU may idle hot"
  fi
}

ensure_ca_certificate() {
  if [[ -f "$DER" ]] && openssl x509 -in "$DER" -inform DER -text -noout 2>/dev/null | grep -q 'CA:TRUE'; then
    ok "akmods signing certificate already carries CA:TRUE"
    return 0
  fi
  if [[ -f "$CA_TEMPLATE" ]] && ! grep -q 'CA:TRUE' "$CA_TEMPLATE"; then
    log "patching $CA_TEMPLATE with a CA extension"
    cat >>"$CA_TEMPLATE" <<'TXT'

[v3_ca]
basicConstraints = critical,CA:TRUE
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
TXT
  fi
  require_cmd kmodgenca
  kmodgenca -a -f
  openssl x509 -in "$DER" -inform DER -text -noout 2>/dev/null | grep -q 'CA:TRUE' \
    || die "generated akmods certificate still lacks CA:TRUE; refusing to enroll it"
  ok "akmods signing certificate regenerated with CA:TRUE"
}

build_module() {
  local built=0
  require_cmd akmods
  akmods --force
  for _ in $(seq 1 60); do
    if modinfo -k "$(uname -r)" -F version nvidia >/dev/null 2>&1; then
      built=1
      break
    fi
    sleep 5
  done
  (( built )) || die "akmod-nvidia did not finish building within 300s; see /var/cache/akmods"
  ok "nvidia module $(modinfo -k "$(uname -r)" -F version nvidia) built for $(uname -r)"
}

mok_enrolled() {
  [[ -f "$DER" ]] || return 1
  if have mokutil && mokutil --test-key "$DER" 2>/dev/null | grep -qi 'is already enrolled'; then
    return 0
  fi
  return 1
}

enroll_mok() {
  require_cmd mokutil
  if mok_enrolled; then
    ok "MOK key already enrolled"
    return 0
  fi
  if [[ "$AUTO" == 1 ]]; then
    local pw
    pw="$(openssl rand -base64 12 | tr -d '/+=' | cut -c1-16)"
    if printf '%s\n%s\n' "$pw" "$pw" | mokutil --import "$DER" >/dev/null 2>&1; then
      install -m 600 /dev/null /etc/fedora-kde/mok-password
      printf '%s\n' "$pw" >/etc/fedora-kde/mok-password
      warn "MOK enrollment queued; password stored in /etc/fedora-kde/mok-password"
      warn "reboot and enroll the key in the blue MOK screen"
      return 3
    fi
    warn "non-interactive MOK import failed; run manually:"
    warn "  sudo mokutil --import $DER"
    return 3
  fi
  log "importing the MOK key; mokutil will ask for a one-time password"
  if ! mokutil --import "$DER"; then
    die "mokutil --import failed"
  fi
  warn "reboot and enroll the key in the blue MOK screen, then re-run provisioning"
  return 3
}

configure_environment() {
  append_line_once /etc/environment 'KWIN_DRM_NO_DIRECT_SCANOUT=1'
  local home
  home="$(user_home)"
  install -d -o "$(target_user)" -g "$(target_user)" "$home/.config/environment.d"
  local f="$home/.config/environment.d/kwin-fixes.conf"
  touch "$f"
  append_line_once "$f" '# Disable DDC/CI brightness control: it crashes powerdevil on hybrid GPUs.'
  append_line_once "$f" 'POWERDEVIL_NO_DDCUTIL=1'
  chown "$(target_user):$(target_user)" "$f"
  ok "hybrid-GPU environment written"
}

configure_grub() {
  grub_append_params nvidia_drm.modeset=1 rd.driver.blacklist=nouveau modprobe.blacklist=nouveau
  if have grubby; then
    grubby --update-kernel=ALL --args="nvidia_drm.modeset=1 rd.driver.blacklist=nouveau modprobe.blacklist=nouveau"
    grubby --update-kernel=ALL --remove-args="nvidia_drm.fbdev=1 mem_sleep_default=deep NVreg_EnableGpuFirmware=0" || true
  fi
  grub_regenerate
  rm -f /etc/modprobe.d/nvidia-gsp-fix.conf
  ok "GRUB updated (nvidia_drm.modeset=1, nouveau blacklisted)"
}

main() {
  parse_args "$@"
  init_log nvidia
  [[ "$FEDORA_KDE_DRY_RUN" == 1 ]] && { log "dry-run: driver + MOK plan printed"; usage; exit 0; }
  require_root
  require_cmd openssl

  install_driver
  ensure_ca_certificate
  build_module
  configure_environment
  configure_grub
  if have systemctl && systemctl list-unit-files nvidia-powerd.service >/dev/null 2>&1; then
    systemctl enable --now nvidia-powerd.service 2>/dev/null || warn "nvidia-powerd not started"
  fi
  enroll_mok || exit $?
  ok "nvidia stage complete"
}

main "$@"
