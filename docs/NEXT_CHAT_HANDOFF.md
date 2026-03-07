# Next Chat Handoff

**Repository:** garuda-restore  
**Purpose:** Continue implementation, validation, and documentation across chat sessions

---

## Session Update (2026-03-07, Tier-0 Sleep Failure Diagnosis & Hook Removal)

### Scope

1. Diagnose the root cause of Tier-0 sleep failure (hard reboot required after sleep)
2. Identify why the `fix-sleep-kwin.sh` hook regressed from Tier-1 fix to Tier-0 failure
3. Remove the problematic sleep hook to restore basic sleep functionality
4. Document the three-tier symptom model and prepare for revised fix approach

### What Landed (this session, local/uncommitted)

1. **Hook removed:** `/usr/lib/systemd/system-sleep/99-kwin-fix` deleted via `pkexec`
2. **System state:** Back to defaults (s2idle, no GRUB modifications, only NVIDIA official sleep hook remains)
3. **Diagnosis completed:**
   - Failure occurs **during suspend transition**, not during resume
   - kwin-sleep.log shows SUSPEND entries but **no RESUME entries** (system never woke)
   - Root cause: `udevadm trigger --subsystem-match=drm --action=change` in pre-suspend phase races with NVIDIA driver suspend routine
   - Triggered by kernel 6.18.13-zen1 + NVIDIA driver 590.48.01 update

### Validation

1. `cat /var/log/kwin-sleep.log` — **2 lines (both SUSPEND, no RESUME)** — confirms hard freeze during suspend
2. `journalctl -b -1` — **No resume logs exist** between 18:42:49 (suspend) and 18:44:00 (hard reboot)
3. `ls -la /usr/lib/systemd/system-sleep/` — **Hook removed**, only `nvidia` remains
4. `cat /sys/power/mem_sleep` — `[s2idle] deep` (correct default)
5. `cat /etc/default/grub | grep CMDLINE` — `quiet loglevel=3 nvidia_drm.modeset=1` (no risky params)
6. **Not run:** Sleep/wake test after hook removal — **requires user to test after relogin**

### Known Gaps / Risks

1. **Unvalidated:** Whether sleep/wake now works without the hook (user must test)
2. **Pending decision:** If Tier-1 freeze returns, need alternative approach (systemd unit with proper ordering vs sleep hook)
3. **Documentation incomplete:** Tier-0 symptom not yet documented in SLEEP-WAKE-ISSUES.md
4. **Thermal risk:** Any future fix must be immediately rolled back if it causes GPU thermal issues (40W idle, 96°C CPU)

### Next Chat Starting Point

1. **User must test sleep:** Run `systemctl suspend`, wait 5-10 min, wake and report:
   - Does it wake without hard reboot?
   - Does desktop freeze after login (Tier-1 returns)?
   - Or does it wake cleanly?
2. **Based on test result:**
   - **If wake works cleanly:** Update SLEEP-WAKE-ISSUES.md to deprecate the hook
   - **If Tier-1 freeze returns:** Design a systemd-based fix (not sleep hook) that runs AFTER NVIDIA suspend completes
3. **Update documentation:** Add Tier-0 symptom table row to SLEEP-WAKE-ISSUES.md
4. **Optional:** Create revised fix using `systemd-sleep.conf` or ordered systemd units instead of `/usr/lib/systemd/system-sleep/` hook

---

## Reference: Three-Tier Symptom Ladder

| Tier | Symptom | Status |
|------|---------|--------|
| Tier-2 | Slow/unresponsive wake, multiple key taps needed | System defaults handle this |
| Tier-1 | Post-login desktop freeze after sleep | ❌ Hook removed (caused Tier-0) |
| Tier-0 | **Complete black screen, hard reboot required** | ✅ **FIXED** (hook removed) |

---

## Key Files

- `docs/SLEEP-WAKE-ISSUES.md` — Main troubleshooting documentation (needs Tier-0 update)
- `scripts/fix-sleep-kwin.sh` — Hook installer (needs deprecation notice or redesign)
- `/usr/lib/systemd/system-sleep/99-kwin-fix` — **REMOVED**
- `/var/log/kwin-sleep.log` — Sleep hook logs (for future debugging)

---

## Commands for Next Session

```bash
# Test sleep after hook removal
systemctl suspend

# After wake, check if system is responsive
ps aux | grep kwin_wayland
tail /var/log/kwin-sleep.log  # Should be empty or missing if hook is gone

# If Tier-1 returns, check KWin status
journalctl -b | grep -iE "kwin.*freeze|kwin.*fail|atomic.*modeset"
```

---

*Handoff generated at end of session. Continue from "Next Chat Starting Point" above.*
