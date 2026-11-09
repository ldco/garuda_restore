#!/usr/bin/env bash
# Stage: asus - asusctl / ROG Control Center, power profile and battery limit.
set -Eeuo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

usage() { echo "asus [--dry-run]"; }

parse_args() {
  while (( $# )); do
    case "$1" in
      --dry-run) FEDORA_KDE_DRY_RUN=1; export FEDORA_KDE_DRY_RUN ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown argument: $1" ;;
    esac
    shift
  done
}

wait_asusd() {
  if ! systemctl is-active --quiet asusd; then
    log "asusd not started by udev yet; enabling it explicitly"
    systemctl enable --now asusd.service || warn "asusd did not start"
  fi
  local _
  for _ in $(seq 1 15); do
    systemctl is-active --quiet asusd && { ok "asusd active"; return 0; }
    sleep 2
  done
  warn "asusd is not active; ASUS profile changes may fail"
  return 0
}

set_battery_limit() {
  local want=80 got
  if asusctl battery --help 2>&1 | grep -q -- '-c'; then
    asusctl battery -c "$want" >/dev/null 2>&1
  elif asusctl battery --help 2>&1 | grep -qi 'limit'; then
    asusctl battery --limit "$want" >/dev/null 2>&1
  elif asusctl -c "$want" >/dev/null 2>&1; then
    :
  else
    warn "ALT: this asusctl build exposes no battery charge limit; skipping"
    return 0
  fi
  got="$(cat /sys/class/power_supply/BAT1/charge_control_end_threshold 2>/dev/null || echo '?')"
  if [[ "$got" == "$want" ]]; then
    ok "battery charge limit = ${got}%"
  else
    warn "battery charge limit is '${got}' (requested ${want}%)"
  fi
}

main() {
  parse_args "$@"
  init_log asus
  [[ "$FEDORA_KDE_DRY_RUN" == 1 ]] && { log "dry-run: would install asusctl and set Balanced/Quiet"; exit 0; }
  require_root

  dnf_install asusctl rog-control-center
  wait_asusd

  if ! asusctl profile -P Balanced >/dev/null 2>&1; then
    warn "could not set the Balanced profile"
  fi
  asusctl profile -a Balanced >/dev/null 2>&1 || warn "could not set the AC profile"
  asusctl profile -b Quiet >/dev/null 2>&1 || warn "could not set the battery profile"
  ok "ASUS profiles: Balanced (AC), Quiet (battery)"

  set_battery_limit

  if systemctl is-active --quiet power-profiles-daemon; then
    ok "power-profiles-daemon active"
  else
    warn "power-profiles-daemon is not active; asusctl profile switching needs it"
  fi
}

main "$@"
