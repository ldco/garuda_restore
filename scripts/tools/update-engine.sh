#!/usr/bin/env bash
# =============================================================================
# update-engine.sh - clean, resumable Garuda/Arch system update
# =============================================================================
# Why this exists
#   On 2026-10-23 a `pacman -Su` of 677 packages was started from a live Plasma
#   session, died mid-transaction and froze the machine (see
#   docs/INCIDENT-2026-10-23-update-crash.md). Recurring update failures before
#   that had two other causes: a broken first Arch mirror (HTTP 403) and flaky
#   chaotic-aur mirrors that abort the WHOLE transaction on one failed download.
#
#   This script fixes the process instead of retrying blindly:
#
#     prepare  mirrors -> local DB fix -> snapshot -> download everything
#              (safe while the desktop is running; touches no packages)
#     install  install from the local cache (REFUSES if a GUI session is active)
#     clean    prune the package cache after a successful update + reboot
#     status   show pending updates, cache, disk, session state
#
# Usage
#   sudo ./scripts/tools/update-engine.sh prepare
#   sudo systemctl isolate multi-user.target      # kill the GUI first
#   sudo ./scripts/tools/update-engine.sh install --aur
#   sudo reboot
#   sudo ./scripts/tools/update-engine.sh clean
#
# =============================================================================
set -Eeuo pipefail

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG_DIR="/var/log/garuda"
LOG="$LOG_DIR/system-update-$STAMP.log"
BACKUP_DIR="/var/backups/garuda-restore/system-update-$STAMP"
PACMAN_LOG="/var/log/pacman.log"

MODE="status"
FORCE=0
WITH_AUR=0
WITH_JOURNAL=0
SKIP_MIRRORS=0
ENTRY_COUNTRY="${ENTRY_COUNTRY:-RU}"

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die()  { log "FATAL: $*"; exit 1; }
run()  { log "+ $*"; "$@"; }

trap 'rc=$?; log "ERROR: command failed (exit $rc) at line $LINENO"' ERR

usage() {
    cat <<'USAGE'
update-engine.sh - clean, resumable Garuda system update

Modes:
  prepare          mirrors + local DB fix + snapshot + download everything
                   (safe while the desktop is running; installs no packages)
                   --skip-mirrors: keep the current mirrorlists
  install          install from the local cache; refuses if a GUI session is
                   active. Options: --aur (also update AUR), --force
  clean            prune the package cache after a successful update + reboot
  status           show pending updates, cache, disk and session state

Typical run:
  sudo ./scripts/tools/update-engine.sh prepare
  # save work, Ctrl+Alt+F3, log in
  sudo systemctl isolate multi-user.target
  sudo ./scripts/tools/update-engine.sh install --aur
  sudo reboot
  sudo ./scripts/tools/update-engine.sh clean

Every root mode writes a full log to /var/log/garuda/system-update-*.log
USAGE
}

need_root() {
    [ "$EUID" -eq 0 ] || die "must run as root: sudo $SELF $MODE"
}

setup_logging() {
    mkdir -p "$LOG_DIR"
    touch "$LOG"
    exec > >(tee -a "$LOG") 2>&1
    log "=== system-update $MODE ($STAMP) ==="
    log "log: $LOG"
}

preflight() {
    if [ -e /var/lib/pacman/db.lck ]; then
        die "pacman is locked (/var/lib/pacman/db.lck). Another pacman is running or a previous run was killed."
    fi

    if grep -qE 'subvol=@/\.snapshots/[0-9]+/snapshot' /proc/cmdline; then
        die "booted into a btrfs snapshot. Restore it first (snapper-tools / btrfs-assistant), changes would be lost."
    fi

    local avail
    avail="$(df --output=avail -BG / | tail -1 | tr -dc '0-9')"
    [ -n "$avail" ] || die "cannot determine free space on /"
    if [ "$avail" -lt 8 ]; then
        die "need at least 8 GiB free on /, have ${avail} GiB"
    fi
    log "free space on /: ${avail} GiB"
}

active_graphical_session() {
    local sid type active
    while read -r sid _; do
        [ -n "$sid" ] || continue
        type="$(loginctl show-session "$sid" -p Type --value 2>/dev/null || true)"
        active="$(loginctl show-session "$sid" -p Active --value 2>/dev/null || true)"
        case "$type" in
            wayland|x11) [ "$active" = "yes" ] && return 0 ;;
        esac
    done < <(loginctl list-sessions --no-legend 2>/dev/null || true)
    return 1
}

# A compositor running on another VT is still a live compositor: switching to
# tty3 does not stop Plasma and does not make replacing Qt/Mesa safe. Only
# `systemctl isolate multi-user.target` (or a real reboot) removes it.
graphical_session_running() {
    active_graphical_session && return 0
    if pgrep -x kwin_wayland >/dev/null 2>&1; then return 0; fi
    if pgrep -x kwin_x11 >/dev/null 2>&1; then return 0; fi
    if pgrep -x Xorg >/dev/null 2>&1; then return 0; fi
    if pgrep -x plasmashell >/dev/null 2>&1; then return 0; fi
    return 1
}

backup_configs() {
    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"
    local f
    for f in /etc/pacman.conf /etc/pacman.d/mirrorlist /etc/pacman.d/chaotic-mirrorlist; do
        [ -e "$f" ] && install -m644 "$f" "$BACKUP_DIR/$(basename "$f")"
    done
    log "config backup: $BACKUP_DIR"
}

fix_pacman_conf() {
    local f=/etc/pacman.conf tmp n
    tmp="$(mktemp)"

    # Exactly one DisableDownloadTimeout. The 2026-10-23 troubleshooting left two.
    awk 'BEGIN { seen = 0 }
         /^[[:space:]]*DisableDownloadTimeout[[:space:]]*$/ {
             if (seen) next
             seen = 1
         }
         { print }' "$f" >"$tmp"

    if ! grep -qE '^[[:space:]]*DisableDownloadTimeout[[:space:]]*$' "$tmp"; then
        sed -i '/^\[options\]$/a DisableDownloadTimeout' "$tmp"
    fi

    if ! cmp -s "$f" "$tmp"; then
        install -m644 "$tmp" "$f"
        log "pacman.conf: normalised DisableDownloadTimeout"
    fi
    rm -f "$tmp"

    n="$(grep -cE '^[[:space:]]*DisableDownloadTimeout[[:space:]]*$' "$f" || true)"
    [ "$n" -eq 1 ] || die "pacman.conf still has $n DisableDownloadTimeout entries"
}

refresh_mirrors() {
    local tmp n

    tmp="$(mktemp)"
    if rate-mirrors --allow-root --save="$tmp" --protocol https \
            --entry-country "$ENTRY_COUNTRY" arch --max-delay=21600 >/dev/null 2>&1; then
        n="$(grep -c '^Server' "$tmp" || true)"
        if [ "$n" -ge 10 ]; then
            install -m644 "$tmp" /etc/pacman.d/mirrorlist
            log "arch mirrorlist: $n servers (rate-mirrors)"
        else
            log "WARN: arch mirrorlist has only $n servers - keeping the existing one"
        fi
    else
        log "WARN: rate-mirrors arch failed - keeping the existing mirrorlist"
    fi
    rm -f "$tmp"

    tmp="$(mktemp)"
    if rate-mirrors --allow-root --save="$tmp" chaotic-aur >/dev/null 2>&1; then
        n="$(grep -c '^Server' "$tmp" || true)"
        if [ "$n" -ge 4 ]; then
            install -m644 "$tmp" /etc/pacman.d/chaotic-mirrorlist
            log "chaotic-aur mirrorlist: $n servers (rate-mirrors)"
        else
            log "WARN: chaotic-aur mirrorlist has only $n servers - keeping the existing one"
        fi
    else
        log "WARN: rate-mirrors chaotic-aur failed - keeping the existing mirrorlist"
    fi
    rm -f "$tmp"
}

fix_local_deps() {
    local out
    if pacman -Dk >/tmp/system-update-dk.$$ 2>&1; then
        rm -f /tmp/system-update-dk.$$
        log "local pacman DB: consistent"
        return
    fi

    out="$(cat /tmp/system-update-dk.$$; rm -f /tmp/system-update-dk.$$)"
    log "local pacman DB problems:"
    printf '%s\n' "$out"

    # balena-etcher 2.1.6-1 (chaotic-aur) requires nodejs-lts-jod, which
    # conflicts with the installed nodejs and cannot be satisfied without
    # downgrading the runtime required by npm/yarn/zed/cursor. Etcher bundles
    # its own Electron runtime, so drop this one package instead of breaking
    # the Node toolchain. (Reinstall later from the upstream AppImage if needed.)
    if grep -q "missing 'nodejs-lts-jod' dependency for 'balena-etcher'" <<<"$out"; then
        if pacman -Qq nodejs >/dev/null 2>&1; then
            log "removing balena-etcher: its nodejs-lts-jod dependency conflicts with nodejs"
            run pacman -Rns --noconfirm balena-etcher
        else
            log "installing missing dependency nodejs-lts-jod (extra)"
            run pacman -S --needed --noconfirm nodejs-lts-jod
        fi
    fi

    pacman -Dk >/dev/null 2>&1 || die "unresolved local DB problems - fix manually before updating (see above)"
    log "local pacman DB: consistent"
}

make_snapshot() {
    run snapper --config root create \
        --description "before-update-$STAMP" \
        --userdata "important=yes"
}

download_all() {
    local attempts=10 i
    for ((i = 1; i <= attempts; i++)); do
        log "download attempt $i/$attempts"
        if pacman -Syu --downloadonly --noconfirm; then
            log "all packages are in the cache"
            return 0
        fi
        log "attempt $i failed (mirror hiccup or partial download); retrying in 5s"
        sleep 5
        if ((i % 3 == 0)); then
            log "refreshing package databases before retry"
            pacman -Syy --noconfirm || true
        fi
    done
    return 1
}

prepare() {
    need_root
    setup_logging
    preflight

    backup_configs
    fix_pacman_conf
    if [ "$SKIP_MIRRORS" -eq 0 ]; then
        refresh_mirrors
    fi

    log "refreshing package databases"
    run pacman -Syy --noconfirm

    fix_local_deps
    make_snapshot

    if ! download_all; then
        die "could not download every package after 10 attempts. See $LOG. Do not start the install."
    fi

    local pending
    pending="$(pacman -Qu | wc -l)"
    log "pending repo updates: $pending"
    log "cache size: $(du -sh /var/cache/pacman/pkg | cut -f1)"

    cat <<'NEXT'

Next step (must NOT be done from a running desktop):
  1. Save your work and log out of Plasma.
  2. Switch to a text console: Ctrl+Alt+F3
  3. sudo systemctl isolate multi-user.target
  4. sudo ./scripts/tools/update-engine.sh install --aur
  5. sudo reboot
NEXT
}

install_update() {
    need_root
    setup_logging
    preflight

    if graphical_session_running && [ "$FORCE" -eq 0 ]; then
        die "a graphical session is still running (even on another VT). Run 'sudo systemctl isolate multi-user.target' first, then re-run install."
    fi

    log "verifying that every package is cached"
    if ! pacman -Su --downloadonly --noconfirm; then
        die "packages are missing from the cache and could not be downloaded. Run --prepare again (network needed)."
    fi

    local before after rc=0
    before="$(grep -c 'transaction completed' "$PACMAN_LOG" || true)"

    local cmd=(garuda-update --skip-mirrorlist --noconfirm)
    if [ "$WITH_AUR" -eq 1 ]; then
        cmd+=(--aur)
    fi
    run "${cmd[@]}" || rc=$?

    after="$(grep -c 'transaction completed' "$PACMAN_LOG" || true)"

    if [ "$rc" -ne 0 ]; then
        die "garuda-update exited with $rc. See /var/log/garuda/garuda-update and $LOG"
    fi
    if [ "$after" -le "$before" ]; then
        die "no 'transaction completed' was written to $PACMAN_LOG - the upgrade did not finish. Do NOT reboot blindly."
    fi

    log "transaction completed (pacman.log records: $before -> $after)"
    log "repo updates remaining: $(pacman -Qu | wc -l)"
    log "kernel installed: $(pacman -Q linux-zen 2>/dev/null || echo n/a)"
    cat <<'NEXT'

Update installed. Now:
  sudo reboot
After one clean boot, prune the cache with:
  sudo ./scripts/tools/update-engine.sh clean
NEXT
}

clean_cache() {
    need_root
    setup_logging
    preflight

    local pending
    pending="$(pacman -Qu | wc -l)"
    if [ "$pending" -ne 0 ]; then
        die "$pending repo updates are still pending - finish the update before cleaning"
    fi

    run paccache -rk2
    run paccache -ruk0
    if [ "$WITH_JOURNAL" -eq 1 ]; then
        journalctl --vacuum-size=500M
    fi

    log "cache size after cleanup: $(du -sh /var/cache/pacman/pkg | cut -f1)"
    log "orphan packages (review, then remove with 'pacman -Rns'):"
    pacman -Qtdq || log "  none"
    log "backup subvolumes (delete only after one clean boot):"
    btrfs subvolume list / 2>/dev/null | grep -E '@_backup' || log "  none"
}

show_status() {
    printf 'repo updates pending : %s\n' "$(pacman -Qu 2>/dev/null | wc -l)"
    local aur='?'
    if [ "$EUID" -ne 0 ] && command -v paru >/dev/null; then
        aur="$(timeout 20 paru -Qua 2>/dev/null | wc -l)" || aur='?'
    fi
    printf 'AUR updates pending  : %s\n' "$aur"
    printf 'cache                : %s\n' "$(du -sh /var/cache/pacman/pkg 2>/dev/null | cut -f1 || true)"
    printf 'root usage           : %s\n' "$(df -h / | awk 'NR==2 {print $4 " free of " $2}')"
    printf 'graphical session    : %s\n' "$(graphical_session_running && echo yes || echo no)"
    printf 'last transaction     : %s\n' "$(grep 'transaction completed' "$PACMAN_LOG" 2>/dev/null | tail -1 || echo 'none')"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        prepare|install|clean|status) MODE="$1" ;;
        --force)   FORCE=1 ;;
        --aur)     WITH_AUR=1 ;;
        --journal) WITH_JOURNAL=1 ;;
        --skip-mirrors) SKIP_MIRRORS=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1 (try --help)" ;;
    esac
    shift
done

case "$MODE" in
    prepare) prepare ;;
    install) install_update ;;
    clean)   clean_cache ;;
    status)  show_status ;;
esac
