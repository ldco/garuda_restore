#!/usr/bin/env bash
# =============================================================================
# thermal-guard.sh - keep the FX507ZR out of thermal throttle under AI load
# =============================================================================
# Why: 2026-11-10 measurements on this machine
#   - two harness instances + parallel `bun test` workers took ~5.4 of 20
#     threads; the CPU package hit 98 C and the EC fans 6300 rpm
#   - package_throttle_total_time_ms grew 5.4 s per 75 s during that burst
#   - the dGPU idles at 33-52 W because both external ports are wired to it
#
# Three layers, cheapest first:
#   quota  (unprivileged) - CPUQuota on harness.slice so one workload cannot
#                           take the whole CPU; desktop preempts (CPUWeight)
#   cap    (root)         - ASUS PPT PL1 in watts + a boot unit; PL2 untouched
#                           so single-thread bursts stay fast
#   revert (root)         - remove the boot unit and restore EPP
#
# Usage:
#   thermal-guard.sh status              # read-only, no root
#   thermal-guard.sh quota on|off        # unprivileged slice cap (persistent)
#   sudo thermal-guard.sh cap [--pl1 W]  # root: sustained package limit
#   sudo thermal-guard.sh revert         # root: remove the boot unit
# =============================================================================
set -Eeuo pipefail

# Note: asus-wmi warns that this sysfs path is deprecated in favour of
# /sys/class/firmware_attributes (asus-armoury). The new class does not exist on
# kernel 7.2.11 here, so the WMI path is the working one; revisit after a kernel
# upgrade that provides firmware_attributes.
WMI=/sys/devices/platform/asus-nb-wmi
SLICE_DROPIN_DIR="$HOME/.config/systemd/user/harness.slice.d"
SLICE_DROPIN="$SLICE_DROPIN_DIR/zz-cpu.conf"
UNIT=/etc/systemd/system/asus-thermal-cap.service
DEFAULT_PL1=45
THROTTLE_DIR=/sys/devices/system/cpu/cpu0/thermal_throttle

die() { printf 'thermal-guard: %s\n' "$*" >&2; exit 1; }
need_root() { [ "$(id -u)" -eq 0 ] || die "this action needs root"; }

status() {
    printf '%-28s %s\n' "kernel:" "$(uname -r)"
    printf '%-28s %s C\n' "package temp:" "$(($(cat /sys/class/hwmon/hwmon8/temp1_input 2>/dev/null || echo 0) / 1000))"
    local f
    for f in /sys/class/hwmon/hwmon*/fan*_input; do
        [ -e "$f" ] && printf '%-28s %s rpm\n' "$(basename "$f"):" "$(cat "$f")"
    done
    nvidia-smi --query-gpu=power.draw,utilization.gpu,pstate,temperature.gpu \
        --format=csv,noheader 2>/dev/null | sed 's/^/gpu: /' || true
    printf '%-28s %s\n' "load:" "$(cut -d' ' -f1-3 /proc/loadavg)"
    printf '%-28s %s\n' "PL1 / PL2 (cached):" "$(cat "$WMI/ppt_pl1_spl" 2>/dev/null || echo n/a) / $(cat "$WMI/ppt_pl2_sppt" 2>/dev/null || echo n/a)"
    local unit_state
    unit_state=$(systemctl is-enabled asus-thermal-cap.service 2>/dev/null) || unit_state=absent
    printf '%-28s %s\n' "PL1 cap unit:" "$unit_state"
    [ "$unit_state" = absent ] && printf '%-28s %s\n' "note:" "PL1 is runtime-only right now; a reboot restores the firmware default"
    printf '%-28s %s\n' "EPP:" "$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null || echo n/a)"
    printf '%-28s %s\n' "governor:" "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo n/a)"
    printf '%-28s %s\n' "throttle count:" "$(cat "$THROTTLE_DIR/package_throttle_count" 2>/dev/null || echo n/a)"
    printf '%-28s %s ms\n' "throttle total:" "$(cat "$THROTTLE_DIR/package_throttle_total_time_ms" 2>/dev/null || echo n/a)"
    printf '%-28s %s\n' "harness.slice quota:" "$(systemctl --user show harness.slice -p CPUQuotaPerSecUSec --value 2>/dev/null || echo n/a)"
    printf '%-28s %s\n' "harness.slice memory:" "$(systemctl --user show harness.slice -p MemoryMax -p MemorySwapMax --value 2>/dev/null | tr '\n' ' ' || echo n/a)"
}

quota_on() {
    mkdir -p "$SLICE_DROPIN_DIR"
    cat > "$SLICE_DROPIN" <<'CONF'
[Slice]
# Thermal guard: cap the AI/test workload at 4 of 20 threads and let the
# desktop preempt it. Without this, parallel `bun test` workers + two harness
# instances took ~5.4 threads and the CPU package hit 98 C (2026-11-10).
CPUQuota=400%
CPUWeight=50
CONF
    systemctl --user daemon-reload
    # live: do NOT restart the slice, the running harness would die
    systemctl --user set-property harness.slice CPUQuota=400% CPUWeight=50
    printf 'quota on: %s\n' "$(systemctl --user show harness.slice -p CPUQuotaPerSecUSec --value)"
}

quota_off() {
    rm -f "$SLICE_DROPIN"
    systemctl --user daemon-reload
    systemctl --user set-property harness.slice CPUQuota=infinity 2>/dev/null || true
    printf 'quota off: %s\n' "$(systemctl --user show harness.slice -p CPUQuotaPerSecUSec --value)"
}

cap() {
    need_root
    local pl1=$DEFAULT_PL1
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --pl1) pl1=${2:-}; shift 2 ;;
            *) die "unknown argument: $1" ;;
        esac
    done
    case "$pl1" in ''|*[!0-9]*) die "--pl1 must be an integer in watts (5-250)" ;; esac
    [ "$pl1" -ge 5 ] && [ "$pl1" -le 250 ] || die "--pl1 must be 5-250 (kernel ABI range)"
    [ -w "$WMI/ppt_pl1_spl" ] || die "missing $WMI/ppt_pl1_spl"

    printf '%s\n' "$pl1" > "$WMI/ppt_pl1_spl"
    printf 'PL1 set to %s W\n' "$(cat "$WMI/ppt_pl1_spl")"

    cat > "$UNIT" <<UNITEOF
[Unit]
Description=ASUS thermal cap: sustained CPU package limit ${pl1} W
After=asusd.service multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'echo ${pl1} > ${WMI}/ppt_pl1_spl'

[Install]
WantedBy=multi-user.target
UNITEOF
    systemctl daemon-reload
    systemctl enable --now asus-thermal-cap.service
    printf 'installed %s (PL1=%s W, PL2 untouched)\n' "$UNIT" "$pl1"
    printf 'gate: throttle ms/min must drop AND a timed build must not regress >10%%\n'
    printf 'revoke: sudo %s revert  (PL1 returns to firmware default at reboot)\n' "$0"
}

revert() {
    need_root
    systemctl disable --now asus-thermal-cap.service 2>/dev/null || true
    rm -f "$UNIT"
    systemctl daemon-reload
    local c
    for c in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
        printf 'performance\n' > "$c" 2>/dev/null || true
    done
    printf 'removed the boot unit; EPP=performance\n'
    printf 'PL1 is STILL %s W at runtime - the kernel cannot read the firmware default back,\n' "$(cat "$WMI/ppt_pl1_spl" 2>/dev/null || echo '?')"
    printf 'so the only way to restore it is a reboot.\n'
}

case "${1:-status}" in
    status) status ;;
    quota) shift; case "${1:-}" in on) quota_on ;; off) quota_off ;; *) die "usage: quota on|off" ;; esac ;;
    cap) shift; cap "$@" ;;
    revert) revert ;;
    -h|--help) sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) die "usage: $0 {status|quota on|quota off|cap [--pl1 W]|revert}" ;;
esac
