#!/usr/bin/env bash
# Stage: security - hardening baseline (always) and opt-in extras.
set -Eeuo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

usage() {
  cat <<'EOF'
security <baseline|optional> [--dry-run]

  baseline   SELinux enforcing, firewalld, sysctl, zram, dnf-automatic
             (security only), fwupd, no sshd.
  optional   usbguard, fapolicyd, AIDE, auditd, key-only sshd, fail2ban.
EOF
}

baseline_selinux() {
  local mode
  mode="$(getenforce 2>/dev/null || echo Disabled)"
  if [[ "$mode" == Enforcing ]]; then
    ok "SELinux enforcing"
    return 0
  fi
  warn "SELinux is '${mode}'; forcing enforcing"
  sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config 2>/dev/null || true
  setenforce 1 2>/dev/null || true
  mode="$(getenforce 2>/dev/null || echo Disabled)"
  [[ "$mode" == Enforcing ]] || die "could not switch SELinux to Enforcing"
  ok "SELinux enforcing"
}

baseline_firewall() {
  dnf_install firewalld plasma-firewall
  systemctl enable --now firewalld
  systemctl is-active --quiet firewalld || die "firewalld did not start"
  firewall-cmd --state | grep -qx running || die "firewall-cmd is not running"
  ok "firewalld running"
}

baseline_sysctl() {
  local f=/etc/sysctl.d/99-nocowboy-hardening.conf
  cat >"$f" <<'TXT'
# FedoraKDE baseline hardening
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.unprivileged_bpf_disabled = 1
kernel.kexec_load_disabled = 1
kernel.yama.ptrace_scope = 1
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2
vm.swappiness = 133
TXT
  sysctl --system >/dev/null
  ok "sysctl hardening applied"
}

baseline_zram() {
  if ! rpm -q zram-generator >/dev/null 2>&1; then
    dnf_install zram-generator
  fi
  cat >/etc/systemd/zram-generator.conf <<'TXT'
[zram0]
zram-size = min(ram, 16384)
compression-algorithm = zstd
TXT
  systemctl daemon-reload
  # Re-create zram0 only when it holds no pages.
  if [[ "$(swapon --show=NAME,USED --noheadings 2>/dev/null | awk '$1=="/dev/zram0"{print $2}')" =~ ^0[BK]?$ ]]; then
    swapoff /dev/zram0 2>/dev/null || true
    systemctl restart systemd-zram-setup@zram0.service 2>/dev/null || true
  else
    warn "zram0 holds swapped pages; the new size applies on the next boot"
  fi
  ok "zram configured (zstd, up to 16 GiB)"
}

baseline_auto_updates() {
  if ! dnf_install dnf5-plugin-automatic; then
    warn "ALT: dnf5-plugin-automatic missing; trying dnf-automatic"
    dnf_install dnf-automatic || die "no automatic-update package available"
  fi
  cat >/etc/dnf/automatic.conf <<'TXT'
[commands]
upgrade_type = security
download_updates = yes
apply_updates = yes

[emitters]
emit_via = stdio

[base]
debuglevel = 1
TXT
  local unit="" u
  for u in dnf-automatic.timer dnf5-automatic.timer; do
    if systemctl list-unit-files --no-legend "$u" 2>/dev/null | grep -q .; then
      unit="$u"
      break
    fi
  done
  [[ -n "$unit" ]] || die "cannot find an automatic-update timer"
  systemctl enable --now "$unit"
  ok "automatic security updates enabled ($unit)"
}

baseline_fwupd() {
  dnf_install fwupd
  systemctl enable --now fwupd-refresh.timer 2>/dev/null || warn "fwupd-refresh.timer missing"
  fwupdmgr refresh --force >/dev/null 2>&1 || warn "fwupdmgr refresh failed (offline?)"
  ok "fwupd ready"
}

baseline_no_sshd() {
  if systemctl is-enabled sshd >/dev/null 2>&1; then
    systemctl disable --now sshd
    warn "sshd was enabled; disabled it (no remote login by default)"
  fi
  ok "sshd not enabled"
}

baseline() {
  baseline_selinux
  baseline_firewall
  baseline_sysctl
  baseline_zram
  baseline_auto_updates
  baseline_fwupd
  baseline_no_sshd
  state_set hardening-baseline 1
  ok "hardening baseline applied"
}

optional() {
  log "installing opt-in hardening (may interfere with Steam/USB devices)"
  dnf_install usbguard fapolicyd aide audit fail2ban || warn "some optional packages missing"
  systemctl enable --now auditd 2>/dev/null || warn "auditd not enabled"
  systemctl enable --now usbguard 2>/dev/null || warn "usbguard not enabled (check /etc/usbguard/rules.conf first)"
  systemctl enable --now fapolicyd 2>/dev/null || warn "fapolicyd not enabled"
  systemctl enable --now fail2ban 2>/dev/null || warn "fail2ban not enabled"
  if [[ -f /etc/ssh/sshd_config ]]; then
    sed -i -E 's/^#?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i -E 's/^#?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
  fi
  aide --init >/dev/null 2>&1 || warn "aide --init failed"
  state_set hardening-optional 1
  ok "opt-in hardening applied (rollback documented in docs/HARDENING.md)"
}

main() {
  local mode="${1:-}"
  shift || true
  case "$mode" in
    baseline|optional) ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  while (( $# )); do
    case "$1" in
      --dry-run) FEDORA_KDE_DRY_RUN=1; export FEDORA_KDE_DRY_RUN ;;
      *) die "unknown argument: $1" ;;
    esac
    shift
  done
  init_log "security-$mode"
  [[ "$FEDORA_KDE_DRY_RUN" == 1 ]] && { log "dry-run: would apply $mode"; exit 0; }
  require_root
  "$mode"
}

main "$@"
