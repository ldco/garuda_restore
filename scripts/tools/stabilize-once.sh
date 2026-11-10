#!/usr/bin/env bash
# =============================================================================
# stabilize-once.sh - finish the workstation setup and clean up, once
# =============================================================================
# One idempotent pass over everything that is still manual after a system
# upgrade. Re-running it is safe: every step skips what is already done.
#
#   1. weekly update stack   install and enable the Friday staging timer, the
#                            install reminders and the post-update maintenance
#                            unit (the installer's unit paths were broken, so
#                            none of them had ever been installed)
#   2. paru configuration    merge /etc/paru.conf.pacnew and enable
#                            MinimumReleaseAge = 3d: AUR packages modified in
#                            the last three days are refused, so a fresh AUR
#                            push cannot land in the middle of a work week
#   3. system maintenance    cache prune (keep KEEP_PACKAGES versions), journal
#                            vacuum, fstrim, orphan list, garuda-health report
#   4. cache leftovers       remove pacman's stale download-* temp dirs left
#                            behind by aborted downloads
#   5. verification          timers, guards, pending updates, disk - then what
#                            is deliberately left manual
#
# Usage: sudo ./scripts/tools/stabilize-once.sh
#        ./scripts/tools/stabilize-once.sh --dry-run    # plan only, no root
#
# Rollback: units -> `systemctl disable --now <unit>`; config files are backed
# up next to themselves as *.bak-<timestamp>. Nothing here touches the kernel.
# =============================================================================
set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST=/usr/local/lib/garuda-restore
UNITD=/etc/systemd/system
FLAG=/var/lib/garuda-restore/post-update.pending
PARU_CONF=/etc/paru.conf
PARU_PACNEW=/etc/paru.conf.pacnew
LOG=/var/log/garuda/stabilize-once.log
DRY_RUN=0
FAILED=0

say()  { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '    warning: %s\n' "$*" >&2; }

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'unknown argument: %s\n' "$arg" >&2; exit 2 ;;
    esac
done

# `pacman -Qu` exits 1 on an empty queue; never let that abort a caller.
pending_updates() {
    local n
    n="$(pacman -Qu 2>/dev/null | wc -l || true)"
    printf '%s' "$((n + 0))"
}

# Run a mutating command (or print it in --dry-run).
run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '[dry-run] %s\n' "$*"
    else
        "$@"
    fi
}

step_failed() { warn "$*"; FAILED=$((FAILED + 1)); }

# `du` exits non-zero when it cannot read a root-only subdirectory, so never use
# it bare inside $( ) - that appended a stray "n/a" to the report.
cache_size() {
    local v
    v="$(du -sh /var/cache/pacman/pkg 2>/dev/null | cut -f1 || true)"
    printf '%s' "${v:-n/a}"
}

if [ "$DRY_RUN" -eq 0 ]; then
    [ "$(id -u)" -eq 0 ] || { printf 'run this with sudo (or use --dry-run)\n' >&2; exit 1; }
    mkdir -p "$(dirname "$LOG")"
    if [ -f "$LOG" ] && [ "$(stat -c %s "$LOG" 2>/dev/null || echo 0)" -gt 2000000 ]; then
        mv -f "$LOG" "$LOG.1"
    fi
    exec >>"$LOG" 2>&1
    exec 3>&1                      # keep the terminal: the log is the record
fi

echo_out() { printf '%s\n' "$*" >&3; }

note() { # terminal + log
    if [ "$DRY_RUN" -eq 1 ]; then printf '%s\n' "$*"; else printf '%s\n' "$*" >&3; fi
}

# --- preflight --------------------------------------------------------------
say "preflight"
if [ -e /var/lib/pacman/db.lck ]; then
    note "FATAL: pacman is locked (/var/lib/pacman/db.lck) - finish or clear the transaction first"
    exit 1
fi
pending="$(pending_updates)"
note "    repo updates pending: $pending"
if [ "$pending" -gt 0 ]; then
    note "FATAL: $pending updates are pending - install them first (update-now.sh),"
    note "       otherwise the cache cannot be pruned and the maintenance is a no-op"
    exit 1
fi
note "    kernel: $(uname -r)"

# --- 1. weekly update stack -------------------------------------------------
say "1/5 weekly update stack (Friday 21:55 staging + reminders + maintenance)"
if [ "$DRY_RUN" -eq 1 ]; then
    "$SELF_DIR/install-update-timer.sh" --dry-run
else
    if "$SELF_DIR/install-update-timer.sh"; then
        note "    installer ok (details in this log)"
    else
        step_failed "install-update-timer.sh failed - see the log above"
    fi
    for u in update-prepare.timer update-prompt.timer update-maintenance.service; do
        note "    $(printf '%-28s' "$u") $(systemctl is-enabled "$u" 2>&1 || true)"
    done

    # Rollback plumbing: without the daemon a fresh snapshot only reaches the
    # GRUB menu at the next grub-mkconfig.
    if systemctl is-enabled grub-btrfsd.service >/dev/null 2>&1; then
        note "    grub-btrfsd                  $(systemctl is-active grub-btrfsd.service 2>&1 || true)"
    else
        note "    enabling grub-btrfsd (fresh snapshots appear in the GRUB menu)"
        run systemctl enable --now grub-btrfsd.service || step_failed "grub-btrfsd.service"
    fi
fi

# --- 2. paru configuration --------------------------------------------------
say "2/5 paru configuration"
if [ -e "$PARU_PACNEW" ]; then
    note "    merging $PARU_PACNEW into $PARU_CONF (diff kept in the log)"
    diff -u "$PARU_CONF" "$PARU_PACNEW" || true
    run cp -a "$PARU_CONF" "$PARU_CONF.bak-$(date +%Y%m%d-%H%M%S)"
    run install -m644 "$PARU_PACNEW" "$PARU_CONF"
    run rm -f "$PARU_PACNEW"
else
    note "    no unmerged $PARU_PACNEW"
fi

if grep -qE '^[[:space:]]*MinimumReleaseAge[[:space:]]*=' "$PARU_CONF" 2>/dev/null; then
    note "    $(grep -E '^[[:space:]]*MinimumReleaseAge' "$PARU_CONF" | head -1)"
else
    if grep -qE '^[[:space:]]*#[[:space:]]*MinimumReleaseAge[[:space:]]*=' "$PARU_CONF" 2>/dev/null; then
        run sed -i -E 's|^[[:space:]]*#[[:space:]]*MinimumReleaseAge[[:space:]]*=[[:space:]]*3d|MinimumReleaseAge = 3d|' "$PARU_CONF"
    else
        run sed -i '/^\[options\]/a MinimumReleaseAge = 3d' "$PARU_CONF"
    fi
    note "    MinimumReleaseAge = 3d enabled (AUR only; repo packages are unaffected)"
fi

# --- 3. system maintenance --------------------------------------------------
say "3/5 system maintenance (cache, journal, trim, orphans, health)"
cache_before="$(cache_size)"
if [ ! -e "$FLAG" ]; then
    note "    no post-update flag - setting one so the maintenance runs exactly once now"
    run mkdir -p "$(dirname "$FLAG")"
    run sh -c "date -Is > '$FLAG'"
fi
if [ "$DRY_RUN" -eq 1 ]; then
    info "[dry-run] systemctl start update-maintenance.service"
    info "[dry-run] maintenance-run.sh --dry-run (requested once)"
    info "cache: ${cache_before:-?} -> (dry-run)"
else
    if systemctl start update-maintenance.service 2>/dev/null; then
        note "    update-maintenance.service ran (log: /var/log/garuda/update-maintenance.log)"
    else
        note "    unit not available - running maintenance-run.sh directly"
        if [ -x "$DEST/maintenance-run.sh" ]; then
            "$DEST/maintenance-run.sh" || step_failed "maintenance-run.sh failed"
        else
            step_failed "missing $DEST/maintenance-run.sh"
        fi
    fi
    cache_after="$(cache_size)"
    note "    cache: ${cache_before:-?} -> ${cache_after:-?}"
fi

# --- 4. cache leftovers -----------------------------------------------------
say "4/5 cache leftovers"
shopt -s nullglob
leftovers=(/var/cache/pacman/pkg/download-*)
shopt -u nullglob
if [ "${#leftovers[@]}" -eq 0 ]; then
    note "    none"
else
    left_size="$(du -shc "${leftovers[@]}" 2>/dev/null | tail -1 | cut -f1 || true)"
    note "    removing ${#leftovers[@]} stale pacman download dir(s), ${left_size:-?}"
    for d in "${leftovers[@]}"; do
        run rm -rf "$d"
    done
fi

# --- 5. verification --------------------------------------------------------
say "5/5 verification"
note "    updates pending     : $(pending_updates)"
note "    cache               : $(cache_size)"
note "    disk free (/)       : $(df -h / | awk 'NR==2 {print $4}')"
note "    journal             : $(journalctl --disk-usage 2>/dev/null | sed 's/^Archived and active journals take up //' || echo n/a)"
for u in update-prepare.timer update-prompt.timer update-maintenance.service; do
    [ "$DRY_RUN" -eq 1 ] && continue
    note "    $(printf '%-28s' "$u") $(systemctl is-enabled "$u" 2>&1 || true) / $(systemctl is-active "$u" 2>&1 || true)"
done
note "    sleep targets       : $(systemctl is-enabled sleep.target 2>&1 || true) (deliberate: see docs/SLEEP-WAKE-ISSUES.md)"
note "    thermal PL1 (W)     : $(cat /sys/devices/platform/asus-nb-wmi/ppt_pl1_spl 2>/dev/null || echo n/a)"
note "    thermal cap unit    : $(systemctl is-active asus-thermal-cap.service 2>&1 || true)"
note "    battery limit unit  : $(systemctl is-active battery-charge-limit.service 2>&1 || true)"
note "    linux-lts installed : $(pacman -Q linux-lts 2>/dev/null || echo 'no')"
note "    snapshot cleanup    : $(systemctl is-active snapper-cleanup.timer 2>&1 || true) (snapper-cleanup.timer)"
note "    grub-btrfsd         : $(systemctl is-active grub-btrfsd.service 2>&1 || true)"
note "    snapshot entries    : $(grep -c 'menuentry' /boot/grub/grub-btrfs.cfg 2>/dev/null || echo n/a) in the GRUB menu"

if [ "$DRY_RUN" -eq 0 ]; then
    note "    scheduled:"
    systemctl list-timers 'update-*' --no-pager 2>/dev/null | sed 's/^/      /' | head -4 || true
fi

if [ -n "${SUDO_USER:-}" ] && [ "$DRY_RUN" -eq 0 ]; then
    uid="$(id -u "$SUDO_USER" 2>/dev/null || true)"
    if [ -n "$uid" ] && [ -d "/run/user/$uid" ]; then
        quota="$(runuser -u "$SUDO_USER" -- env XDG_RUNTIME_DIR="/run/user/$uid" \
                 systemctl --user show harness.slice -p CPUQuotaPerSecUSec --value 2>/dev/null || true)"
        note "    harness.slice quota : ${quota:-n/a} (CPUWeight $(runuser -u "$SUDO_USER" -- env XDG_RUNTIME_DIR="/run/user/$uid" systemctl --user show harness.slice -p CPUWeight --value 2>/dev/null || echo n/a))"
        aur="$(runuser -u "$SUDO_USER" -- env XDG_RUNTIME_DIR="/run/user/$uid" \
               timeout 25 paru -Qua 2>/dev/null | wc -l || true)"
        note "    AUR updates pending : ${aur:-?}"
    fi
fi

say "done"
note ""
note "Left manual on purpose:"
note "  - AUR updates:   paru -Sua                (never automated; MinimumReleaseAge now delays fresh AUR changes by 3 days)"
note "  - LTS boot test: reboot -> GRUB -> Advanced options -> linux-lts; then"
note "                   sudo $SELF_DIR/lts-fallback-install.sh --make-default"
note "  - sleep:         masked since 2026-11-10; re-test on the current stack before deciding"
note ""
note "Log: $LOG"
[ "$FAILED" -eq 0 ] || { note "FAILED steps: $FAILED - see the log"; exit 1; }
exit 0
