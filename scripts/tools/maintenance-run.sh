#!/bin/bash
# =============================================================================
# maintenance-run.sh - post-update maintenance, once, after the next boot
# =============================================================================
# update-now.sh drops /var/lib/garuda-restore/post-update.pending before the
# reboot; update-maintenance.service runs this script at boot when that flag
# exists and then removes it. Everything is logged and reported.
#
#   cache      paccache -rk<KEEP_PACKAGES>, paccache -ruk0   (only if nothing pending)
#   journal    vacuum to JOURNAL_MAX
#   trim       fstrim -av   (no discard= mount option on this machine)
#   orphans    listed; removed only with REMOVE_ORPHANS=1
#   health     garuda-health report (json saved); --fix only with HEALTH_FIX=1
#   AUR        NOT updated here by design (paru -Sua is manual)
#
# Config: /etc/garuda-restore/update.conf (MAINTENANCE, KEEP_PACKAGES, JOURNAL_MAX,
#         FSTRIM, REMOVE_ORPHANS, HEALTH_FIX)
# Usage:  maintenance-run.sh [--dry-run] [--now]
#         --now  run the total maintenance immediately, without the
#                post-update flag (manual cleanup; output also on the terminal)
# =============================================================================
set -u

DRY_RUN=0
NOW=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --now)     NOW=1 ;;
        -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'unknown argument: %s\n' "$arg" >&2; exit 2 ;;
    esac
done

LOG="${NOCOWBOY_LOG:-/var/log/garuda/update-maintenance.log}"
STATE="${NOCOWBOY_STATE:-/var/lib/garuda-restore}"
FLAG="$STATE/post-update.pending"
CONF=/etc/garuda-restore/update.conf

MAINTENANCE=1
KEEP_PACKAGES=2
JOURNAL_MAX=500M
FSTRIM=1
REMOVE_ORPHANS=0
HEALTH_FIX=0
[ -r "$CONF" ] && . "$CONF"

run() {
    if [ "$DRY_RUN" -eq 1 ]; then printf '[dry-run] %s\n' "$*"; else "$@"; fi
}

if [ "$DRY_RUN" -eq 0 ]; then
    [ "$(id -u)" -eq 0 ] || { echo "maintenance-run: needs root (or --dry-run)" >&2; exit 1; }
    mkdir -p "$STATE" "$(dirname "$LOG")"
    if [ "$NOW" -eq 1 ]; then
        exec > >(tee -a "$LOG") 2>&1
    else
        exec >>"$LOG" 2>&1
    fi
fi

if [ ! -e "$FLAG" ] && [ "$NOW" -eq 0 ]; then
    [ "$DRY_RUN" -eq 1 ] && echo "no $FLAG - maintenance is not due (use --now to force)"
    exit 0
fi
if [ "$NOW" -eq 1 ]; then
    echo "=== $(date -Is) manual maintenance run (no post-update flag needed) ==="
fi

echo "=== $(date -Is) post-update maintenance (kernel $(uname -r)) ==="
if [ "$MAINTENANCE" != 1 ]; then
    echo "MAINTENANCE=0 - skipping"
    run rm -f "$FLAG"
    exit 0
fi

rc=0
pending=$(pacman -Qu 2>/dev/null | wc -l)
echo "repo updates still pending: $pending"

# --- cache ------------------------------------------------------------------
if [ "$pending" -eq 0 ]; then
    before=$(du -sh /var/cache/pacman/pkg 2>/dev/null | cut -f1)
    run paccache -rk"$KEEP_PACKAGES" || rc=1
    run paccache -ruk0 || rc=1
    after=$(du -sh /var/cache/pacman/pkg 2>/dev/null | cut -f1)
    echo "cache: ${before:-?} -> ${after:-?} (keeping $KEEP_PACKAGES versions)"
else
    before="n/a"; after="n/a"
    echo "cache: not pruned while $pending updates are pending"
fi

# --- journal ----------------------------------------------------------------
run journalctl --vacuum-size="$JOURNAL_MAX" || true

# --- trim -------------------------------------------------------------------
if [ "$FSTRIM" = 1 ]; then
    run fstrim -av || echo "fstrim: skipped or unsupported"
fi

# --- orphans ----------------------------------------------------------------
orphans=$(pacman -Qtdq 2>/dev/null || true)
if [ -n "${orphans:-}" ]; then
    echo "orphan packages (review; REMOVE_ORPHANS=1 removes them):"
    printf '%s\n' "$orphans" | sed 's/^/  /'
    [ "$REMOVE_ORPHANS" = 1 ] && { run pacman -Rns --noconfirm $orphans || rc=1; }
else
    echo "orphan packages: none"
fi

# --- health -----------------------------------------------------------------
if command -v garuda-health >/dev/null 2>&1; then
    if [ "$HEALTH_FIX" = 1 ]; then
        run garuda-health --fix --forcetty || true
    else
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "[dry-run] garuda-health --json > $STATE/health.json"
        else
            garuda-health --json > "$STATE/health.json" 2>/dev/null || true
        fi
    fi
    echo "health: report written to $STATE/health.json"
fi

echo "AUR packages are not updated by this pipeline (manual: paru -Sua)"

# --- status -----------------------------------------------------------------
printf 'time=%s kernel=%s rc=%s pending=%s cache_before=%s cache_after=%s\n' \
    "$(date -Is)" "$(uname -r)" "$rc" "$pending" "${before:-n/a}" "${after:-n/a}" \
    > "$STATE/maintenance.status" 2>/dev/null || true
run rm -f "$FLAG"
echo "=== done rc=$rc ==="
exit "$rc"
