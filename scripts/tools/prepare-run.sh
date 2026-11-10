#!/bin/bash
# =============================================================================
# prepare-run.sh - staged, off-peak upgrade preparation (system unit, root)
# =============================================================================
# Downloads and stages the upgrade; NEVER installs, upgrades or reboots.
#   1. reads the Arch news feed and reports new items since the last run
#   2. runs update-engine.sh prepare (mirrors, DB refresh, snapshot, download)
#   3. records status in /var/lib/garuda-restore/prepare.status
# Installed by install-update-timer.sh to /usr/local/lib/garuda-restore/.
# =============================================================================
set -u

LOG=/var/log/garuda/update-prepare.log
STATE=/var/lib/garuda-restore
ENGINE=/usr/local/lib/garuda-restore/update-engine.sh
UPDATE_NOW=/usr/local/lib/garuda-restore/update-now.sh
CONF=/etc/garuda-restore/update.conf

# AUTO_APPLY=1 -> stage AND install in the same run (the machine reboots when
# the transaction succeeds). AUTO_APPLY=0 -> stage only; apply by hand later.
AUTO_APPLY=1
[ -r "$CONF" ] && . "$CONF"

mkdir -p "$STATE" /var/log/garuda
exec >>"$LOG" 2>&1
echo "=== $(date -Is) prepare run ==="

[ -x "$ENGINE" ] || { echo "FATAL: missing $ENGINE"; exit 1; }

# --- upstream advisories ----------------------------------------------------
news=0
feed=$(curl -fsS --max-time 20 https://archlinux.org/feeds/news/ 2>/dev/null || true)
if [ -n "${feed:-}" ]; then
    news=$(printf '%s' "$feed" | grep -c '<item>' || true)
    prev=$(cat "$STATE/news.count" 2>/dev/null || echo 0)
    case "$prev" in ''|*[!0-9]*) prev=0 ;; esac
    if [ "$news" -gt "$prev" ]; then
        echo "ADVISORY: $((news - prev)) new Arch news item(s) since the last run"
        printf '%s' "$feed" | grep -o '<item><title>[^<]*' | head -3 | sed 's|<item><title>|  news: |'
    fi
    printf '%s\n' "$news" > "$STATE/news.count"
else
    echo "advisory: could not fetch the Arch news feed (network?)"
fi

# --- download only ----------------------------------------------------------
"$ENGINE" prepare
rc=$?

pending=$(pacman -Qu 2>/dev/null | wc -l)
cache=$(du -sh /var/cache/pacman/pkg 2>/dev/null | cut -f1)
snap=$(snapper -c root list 2>/dev/null | tail -1 | awk '{print $1}')
printf 'time=%s phase=prepare rc=%s pending=%s cache=%s snapshot=%s news=%s auto_apply=%s\n' \
    "$(date -Is)" "$rc" "$pending" "$cache" "${snap:-n/a}" "$news" "$AUTO_APPLY" > "$STATE/prepare.status"

# --- stage succeeded: apply in the same run --------------------------------
if [ "$rc" -eq 0 ] && [ "$AUTO_APPLY" = "1" ] && [ "$pending" -gt 0 ] && [ -x "$UPDATE_NOW" ]; then
    echo "=== auto-apply: handing over to update-now.sh (GUI stops, install runs on tty1) ==="
    "$UPDATE_NOW"
    arc=$?
    printf 'time=%s phase=handover rc=%s pending=%s cache=%s snapshot=%s news=%s auto_apply=%s\n' \
        "$(date -Is)" "$arc" "$pending" "$cache" "${snap:-n/a}" "$news" "$AUTO_APPLY" > "$STATE/prepare.status"
    echo "=== auto-apply handover rc=$arc ==="
    echo "=== install result: /var/log/garuda/update-now-run.log (journalctl -u garuda-update-now) ==="
    exit "$arc"
fi

if [ "$AUTO_APPLY" = "1" ] && [ "$pending" -eq 0 ]; then
    echo "=== nothing to apply (0 pending) ==="
fi
echo "=== rc=$rc pending=$pending cache=$cache snapshot=${snap:-n/a} ==="
exit "$rc"
