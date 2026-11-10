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
printf 'time=%s rc=%s pending=%s cache=%s snapshot=%s news=%s\n' \
    "$(date -Is)" "$rc" "$pending" "$cache" "${snap:-n/a}" "$news" > "$STATE/prepare.status"
echo "=== rc=$rc pending=$pending cache=$cache snapshot=${snap:-n/a} ==="
exit "$rc"
