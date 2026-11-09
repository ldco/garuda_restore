#!/usr/bin/env bash
# Stage: sleep-policy - suspend is DISABLED by default on this hardware.
# 14 documented attempts failed (hard freeze / thermal cascade); see
# docs/SLEEP-POLICY.md and the original docs/SLEEP-WAKE-ISSUES.md.
set -Eeuo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

HOOK=/etc/systemd/system-sleep/99-kwin-fix
TARGETS=(sleep.target suspend.target hibernate.target hybrid-sleep.target)

usage() {
  cat <<'EOF'
sleep-policy <disable|enable|rollback|status>

  disable   mask suspend targets, ignore the lid switch (default)
  enable    unmask, install the userspace KWin-restart resume hook
  rollback  same as enable (undo the disable policy)
  status    print the current policy
EOF
}

guard_grub() {
  if grep -qE 'nvidia_drm\.fbdev=1|mem_sleep_default=(deep|s2idle)' /etc/default/grub; then
    die "refusing: a deprecated sleep/fbdev parameter is present in /etc/default/grub"
  fi
}

apply_disable() {
  systemctl mask "${TARGETS[@]}"
  local f=/etc/systemd/logind.conf.d/90-nocowboy-sleep.conf
  mkdir -p "$(dirname "$f")"
  cat >"$f" <<'TXT'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
TXT
  if have kwriteconfig6; then
    as_user kwriteconfig6 --file powerdevilrc --group AC --group Display --key TurnOffDisplayIdleTimeoutSec 300 || true
    as_user kwriteconfig6 --file powerdevilrc --group Battery --group Display --key TurnOffDisplayIdleTimeoutSec 120 || true
  fi
  ok "suspend masked; screen turns off after inactivity; power off overnight"
}

install_hook() {
  cat >"$HOOK" <<'TXT'
#!/usr/bin/env bash
# Resume hook: reset backlight, reprobe DRM, restart KWin (bounded).
set -Eeuo pipefail
[[ "${1:-}" == post ]] || exit 0
LOG=/var/log/kwin-sleep.log
exec >>"$LOG" 2>&1
echo "=== resume $(date -Is) ==="
for b in /sys/class/backlight/*/brightness; do
    [ -w "$b" ] && cat "$b" >"$b" 2>/dev/null || true
done
udevadm trigger --subsystem-match=drm --action=change 2>/dev/null || true
user="$(loginctl list-sessions --no-legend 2>/dev/null | awk 'NF>=3{print $3; exit}')"
[ -n "${user:-}" ] || { echo "no active session"; exit 0; }
uid="$(id -u "$user")"
runuser -u "$user" -- env XDG_RUNTIME_DIR="/run/user/$uid" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
    timeout 5 qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
nvidia-smi --query-gpu=pstate,power.draw --format=csv,noheader 2>/dev/null || true
exit 0
TXT
  chmod 755 "$HOOK"
  ok "resume hook installed: $HOOK"
}

apply_enable() {
  systemctl unmask "${TARGETS[@]}"
  rm -f /etc/systemd/logind.conf.d/90-nocowboy-sleep.conf
  install_hook
  warn "suspend re-enabled. Test ONE cycle and watch temperatures:"
  warn "  watch -n5 'sensors | grep -E \"Package|fan\"'"
  warn "Then: sleep-policy status"
}

show_status() {
  local t
  for t in "${TARGETS[@]}"; do
    printf '%-22s %s\n' "$t" "$(systemctl is-enabled "$t" 2>/dev/null || echo unknown)"
  done
  printf '%-22s %s\n' 'mem_sleep' "$(cat /sys/power/mem_sleep 2>/dev/null || echo n/a)"
  printf '%-22s %s\n' 'resume hook' "$([[ -x "$HOOK" ]] && echo present || echo absent)"
}

main() {
  local mode="${1:-}"
  shift || true
  case "$mode" in
    disable|enable|rollback|status) ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  init_log "sleep-$mode"
  require_root
  guard_grub
  case "$mode" in
    disable) apply_disable ;;
    enable) apply_enable ;;
    rollback) apply_enable ;;
    status) show_status ;;
  esac
}

main "$@"
