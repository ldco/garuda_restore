#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh - portable workstation profile (Layer 1) + hardware adaptation (Layer 2)
# =============================================================================
# This is the profile, not a distro: it applies the portable resilience layer to
# any Arch/Garuda machine and only the hardware-specific parts when the machine
# is recognised. Nothing here installs packages, upgrades the system or reboots.
#
#   ./bootstrap.sh detect            # read-only: what this machine is
#   ./bootstrap.sh layer1            # portable runtime (unprivileged parts)
#   sudo ./bootstrap.sh layer1       # + root-only parts (LTS install, /usr/local staging)
#   ./bootstrap.sh layer2            # hardware layer, only if a match is detected
#   sudo ./bootstrap.sh layer2       # + root-only parts (PL1 cap, battery unit)
#   ./bootstrap.sh all               # detect -> layer1 -> layer2
#   ./bootstrap.sh status            # what is applied right now
#   ./bootstrap.sh uninstall         # remove the portable layer (root parts printed)
#
# Flags: --dry-run (print only). Layers are idempotent; re-running is safe.
# =============================================================================
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS="$ROOT_DIR/scripts/tools"
DRY_RUN=0
MODE=""

say()  { printf '==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

run() {
    if [ "$DRY_RUN" -eq 1 ]; then printf '[dry-run] %s\n' "$*"; else "$@"; fi
}
have() { command -v "$1" >/dev/null 2>&1; }
is_root() { [ "$(id -u)" -eq 0 ]; }

# --- detection --------------------------------------------------------------
D_VENDOR=""; D_PRODUCT=""; D_ASUS=0; D_NVIDIA=""; D_INTEL=""; D_DRACUT=0
D_OOMD=""; D_ZRAM=""; D_SNAP=""; D_SYSTEMD=""; D_BATT=""

detect() {
    D_VENDOR=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo unknown)
    D_PRODUCT=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown)
    [ -d /sys/devices/platform/asus-nb-wmi ] && D_ASUS=1
    local c
    for c in /sys/class/drm/card*/device/vendor; do
        [ -r "$c" ] || continue
        local card
        card=$(basename "$(dirname "$(dirname "$c")")")
        case "$(cat "$c")" in
            0x10de) D_NVIDIA="$card" ;;
            0x8086) D_INTEL="$card" ;;
        esac
    done
    have dracut && D_DRACUT=1
    D_OOMD=$(systemctl is-enabled systemd-oomd 2>/dev/null || echo absent)
    have zramctl && D_ZRAM=$(zramctl --noheadings 2>/dev/null | head -1 | awk '{print $1" "$(NF)}')
    D_SNAP=$(pacman -Qq snapper snap-pac grub-btrfs 2>/dev/null | tr '\n' ' ')
    D_SYSTEMD=$(systemctl --version 2>/dev/null | head -1 | awk '{print $2}')
    D_BATT=$(asusctl battery info 2>/dev/null | sed -n 's/.*limit: *//p' | head -1)
}

print_facts() {
    info "vendor/model : $D_VENDOR / $D_PRODUCT"
    info "ASUS WMI     : $([ "$D_ASUS" -eq 1 ] && echo yes || echo no)"
    info "GPUs         : nvidia=${D_NVIDIA:-none} intel=${D_INTEL:-none}"
    info "initramfs    : $([ "$D_DRACUT" -eq 1 ] && echo dracut || echo mkinitcpio)"
    info "systemd-oomd : $D_OOMD"
    info "zram         : ${D_ZRAM:-none}"
    info "snapshots    : ${D_SNAP:-none}"
    info "systemd      : ${D_SYSTEMD:-unknown}"
    info "battery limit: ${D_BATT:-n/a}"
}

detect_cmd() { detect; say "facts"; print_facts; }

# --- layer 1: portable ------------------------------------------------------
layer1() {
    detect
    say "Layer 1 - portable runtime"
    print_facts

    [ -x "$TOOLS/oom-guard.sh" ] || die "missing $TOOLS/oom-guard.sh"
    say "OOM containment (harness.slice, per-scope cap, guard timer, launcher)"
    if [ "$DRY_RUN" -eq 1 ]; then
        "$TOOLS/oom-guard.sh" --dry-run
    else
        "$TOOLS/oom-guard.sh"
    fi

    say "CPU quota on harness.slice"
    run "$TOOLS/thermal-guard.sh" quota on

    say "update tooling"
    if is_root; then
        run install -Dm755 "$TOOLS/update-engine.sh" /usr/local/lib/garuda-restore/update-engine.sh
        run install -Dm755 "$TOOLS/update-now.sh" /usr/local/lib/garuda-restore/update-now.sh
        run install -Dm644 "$ROOT_DIR/systemd/garuda-update-now.service" /usr/local/lib/garuda-restore/garuda-update-now.service
    else
        info "root-only: sudo install -Dm755 $TOOLS/update-engine.sh /usr/local/lib/garuda-restore/"
        info "root-only: sudo install -Dm755 $TOOLS/update-now.sh /usr/local/lib/garuda-restore/"
        info "root-only: sudo install -Dm644 $ROOT_DIR/systemd/garuda-update-now.service /usr/local/lib/garuda-restore/"
    fi

    say "kernel fallback (linux-lts)"
    if pacman -Qq linux-lts >/dev/null 2>&1; then
        info "linux-lts already installed"
    elif is_root; then
        run "$TOOLS/lts-fallback-install.sh"
    else
        info "root-only: sudo $TOOLS/lts-fallback-install.sh"
    fi

    say "Layer 1 done"
}

# --- layer 2: hardware ------------------------------------------------------
layer2() {
    detect
    say "Layer 2 - hardware adaptation"
    print_facts

    if [ "$D_ASUS" -ne 1 ]; then
        warn "no ASUS WMI interface: skipping the ASUS-specific layer (nothing to apply)"
        return 0
    fi

    say "power profile policy (Performance on AC, Quiet on battery; Balanced is unsafe on this EC)"
    local prof
    prof=$(asusctl profile get 2>/dev/null | sed -n 's/Active profile: *//p' | head -1)
    case "${prof:-unknown}" in
        Performance|Quiet) info "active profile: $prof (ok)" ;;
        *) warn "active profile is '$prof' - expected Performance (AC) / Quiet (battery)" ;;
    esac

    say "thermal cap (PL1, sustained)"
    if is_root; then
        run "$TOOLS/thermal-guard.sh" cap --pl1 45
    else
        info "root-only: sudo $TOOLS/thermal-guard.sh cap --pl1 45"
    fi

    say "battery charge limit unit"
    if is_root; then
        run install -m644 "$ROOT_DIR/systemd/battery-charge-limit.service" /etc/systemd/system/
        run systemctl enable --now battery-charge-limit.service
    else
        info "root-only: sudo install -m644 $ROOT_DIR/systemd/battery-charge-limit.service /etc/systemd/system/"
        info "root-only: sudo systemctl enable --now battery-charge-limit.service"
    fi

    say "display topology (why the dGPU never idles)"
    local s
    for s in /sys/class/drm/card*-*/status; do
        [ -r "$s" ] || continue
        info "$(basename "$(dirname "$s")") $(cat "$s")"
    done

    say "Layer 2 done"
}

# --- uninstall --------------------------------------------------------------
uninstall() {
    detect
    say "removing the profile (portable layer first, then hardware)"
    say "OOM containment"
    if [ "$DRY_RUN" -eq 1 ]; then
        "$TOOLS/oom-guard.sh" --uninstall --dry-run 2>/dev/null || info "[dry-run] $TOOLS/oom-guard.sh --uninstall"
    else
        "$TOOLS/oom-guard.sh" --uninstall
    fi

    say "CPU quota"
    run "$TOOLS/thermal-guard.sh" quota off

    if [ "$D_ASUS" -eq 1 ]; then
        say "thermal cap"
        if is_root; then
            run "$TOOLS/thermal-guard.sh" revert
        else
            info "root-only: sudo $TOOLS/thermal-guard.sh revert"
        fi
        say "battery unit"
        if is_root; then
            run systemctl disable --now battery-charge-limit.service
            run rm -f /etc/systemd/system/battery-charge-limit.service
            run systemctl daemon-reload
        else
            info "root-only: sudo systemctl disable --now battery-charge-limit.service"
            info "root-only: sudo rm -f /etc/systemd/system/battery-charge-limit.service"
        fi
    fi
    say "uninstall done (linux-lts and /usr/local staging are left in place)"
}

# --- status -----------------------------------------------------------------
status() {
    detect
    say "profile status"
    printf '  %-26s %s\n' "repo commit:" "$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo n/a)"
    printf '  %-26s %s\n' "oom-guard.timer:" "$(systemctl --user is-active oom-guard.timer 2>/dev/null || echo unknown)"
    printf '  %-26s %s\n' "harness.slice memory:" "$(systemctl --user show harness.slice -p MemoryMax -p MemorySwapMax --value 2>/dev/null | tr '\n' ' ')"
    printf '  %-26s %s\n' "harness.slice CPU:" "$(systemctl --user show harness.slice -p CPUQuotaPerSecUSec --value 2>/dev/null)"
    printf '  %-26s %s\n' "harness launcher:" "$(readlink -f "$HOME/.local/bin/harness" 2>/dev/null || echo absent)"
    local cap_state sleep_state
    cap_state=$(systemctl is-enabled asus-thermal-cap.service 2>/dev/null) || true
    [ -n "$cap_state" ] || cap_state=absent
    sleep_state=$(systemctl is-enabled sleep.target 2>/dev/null) || true
    [ -n "$sleep_state" ] || sleep_state=unknown
    printf '  %-26s %s\n' "thermal cap unit:" "$cap_state"
    printf '  %-26s %s\n' "PL1 / PL2 (cached):" "$(cat /sys/devices/platform/asus-nb-wmi/ppt_pl1_spl 2>/dev/null || echo n/a) / $(cat /sys/devices/platform/asus-nb-wmi/ppt_pl2_sppt 2>/dev/null || echo n/a)"
    printf '  %-26s %s\n' "sleep masked:" "$sleep_state"
    printf '  %-26s %s\n' "linux-lts:" "$(pacman -Q linux-lts 2>/dev/null | awk '{print $2}' || echo absent)"
    printf '  %-26s %s\n' "battery limit:" "${D_BATT:-n/a}"
    printf '  %-26s %s\n' "graphical session:" "$([ -n "${XDG_CURRENT_DESKTOP:-}" ] && echo yes || echo no)"
}

# --- main -------------------------------------------------------------------
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        detect|layer1|layer2|all|status|uninstall) MODE="$arg" ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown argument: $arg" ;;
    esac
done

case "${MODE:-status}" in
    detect)  detect_cmd ;;
    layer1)  layer1 ;;
    layer2)  layer2 ;;
    all)     detect_cmd; layer1; layer2 ;;
    status)  status ;;
    uninstall) uninstall ;;
esac
