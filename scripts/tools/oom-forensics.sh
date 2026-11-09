#!/usr/bin/env bash
# =============================================================================
# oom-forensics.sh - read-only report: who is killing memory hogs on this box
# =============================================================================
# Companion to oom-guard.sh / harness-run.sh (docs/OOM-WEZTERM.md).
# Answers "what killed my terminal this time?" without changing anything.
# Usage: ./scripts/tools/oom-forensics.sh
# =============================================================================
set -Eeuo pipefail

section() { printf '\n=== %s ===\n' "$*"; }

section "oomd state (oomctl)"
oomctl 2>&1 || true

section "last oomd decisions (this boot)"
journalctl -b -u systemd-oomd --no-pager -n 400 2>/dev/null \
    | grep -E 'Marked .* for killing|killed some process' \
    | tail -40 || true

section "kernel OOM / cgroup OOM (this boot)"
journalctl -b -k --no-pager 2>/dev/null \
    | grep -iE 'out of memory|oom-kill|killed process|Memory cgroup' \
    | tail -40 || true

section "memory pressure"
cat /proc/pressure/memory 2>/dev/null || true

section "system memory"
free -h 2>/dev/null || true
printf '\n'
cat /proc/meminfo 2>/dev/null | grep -E 'MemTotal|MemAvailable|SwapTotal|SwapFree' || true

section "guarded units"
printf '%-62s %-16s %s\n' UNIT OOMPREF MEMORY
for unit in harness.slice \
            plasma-kwin_wayland.service \
            plasma-plasmashell.service \
            plasma-kded6.service; do
    pref="$(systemctl --user show "$unit" -p ManagedOOMPreference --value 2>/dev/null || true)"
    mem="$(systemctl --user show "$unit" -p MemoryCurrent --value 2>/dev/null || true)"
    [ -n "$pref" ] || pref="(absent)"
    [ -n "$mem" ] || mem="-"
    printf '%-62s %-16s %s\n' "$unit" "$pref" "$mem"
done
while IFS= read -r unit; do
    [ -n "$unit" ] || continue
    pref="$(systemctl --user show "$unit" -p ManagedOOMPreference --value 2>/dev/null || true)"
    mem="$(systemctl --user show "$unit" -p MemoryCurrent --value 2>/dev/null || true)"
    printf '%-62s %-16s %s\n' "$unit" "${pref:-?}" "${mem:-?}"
done < <(systemctl --user list-units --type=service --no-legend --plain --no-pager \
             'app-org.wezfurlong.wezterm@*' 2>/dev/null | awk 'NF {print $1}')

section "top 15 by RSS"
ps -eo pid,rss,comm --sort=-rss 2>/dev/null | head -16 || true

exit 0
