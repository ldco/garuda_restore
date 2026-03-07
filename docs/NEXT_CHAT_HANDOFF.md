# Next Chat Handoff

**Repository:** garuda-restore
**Date:** 2026-03-07
**Session:** Tech Plan Execution — Repo Safety Fixes & Hardening Complete

---

## Session Summary

### What Was Accomplished

This session executed the **Tech Plan — Repo Safety Fixes, Dead File Removal & Hardware-Agnostic Restore Kit**:

1. **Dead File Removal**
   - Removed 7 files from `docs/` (GEOGRAF, COMIC, HERO files - unrelated to system management)
   - Files deleted: `GEOGRAF-CHARACTERS-FULL.md`, `GEOGRAF-CHARACTER-AGE-MAP.md`, `GEOGRAF-CHARACTERS-CANON.yaml`, `COMIC-AI-WORKFLOW.md`, `HERO-PROMPTS.md`, `HERO-PROMPTS-TOM1.md`, `HEROES-TOM1.yaml`

2. **Broken Reference Fixes**
   - `README.md`: Updated scripts section, removed frozen config references, fixed documentation links
   - `CLAUDE.md`: Updated entry points to match actual script names
   - `.claude/config.json`: Updated entryPoints map (version 2.0.0)

3. **Script Hardening (Backup-First + Merge)**
   - `force-system-titlebars.sh`: 
     - Creates timestamped backup before any write
     - Merges rules into existing kwinrulesrc (doesn't overwrite)
     - Prints explicit rollback command
   - `restore-system-titlebars.sh`:
     - Creates timestamped backup before any write
     - Removes only our specific rules (preserves others)
     - Safer KWin restart (doesn't quit first, checks process alive)

4. **Script Hardening (Safety Fixes)**
   - `fix-sddm-input.sh`:
     - Removed `modprobe -r evdev` (unsafe on live system)
     - Uses `udevadm trigger --subsystem-match=input --action=add` instead
     - Safe device re-probe without kernel module unload

5. **Parametrization**
   - `daily-drive-sync.sh`:
     - Machine-specific values moved to `daily-drive-sync.conf.local`
     - Created `daily-drive-sync.conf.example` with documented placeholders
     - Script validates config at startup, exits with setup instructions if missing
   - `.gitignore`: Added `scripts/tools/*.conf.local`

6. **Pacman Hook Fix**
   - `track-installs.hook`:
     - Replaced hardcoded `runuser -u ldco` with `${SUDO_USER:-%h}`
     - Uses `%h` expansion for home directory (username-agnostic)

---

## Current State

### Git Status
- Branch: master
- Last commit: `docs: create comprehensive next chat handoff document` (c803c27)
- **Uncommitted changes:** All hardening changes ready to commit

### Files Modified
| File | Change |
|------|--------|
| `scripts/force-system-titlebars.sh` | Backup-first + merge logic |
| `scripts/restore-system-titlebars.sh` | Backup-first + safer KWin restart |
| `scripts/fix-sddm-input.sh` | Removed evdev unload, uses udevadm |
| `scripts/tools/daily-drive-sync.sh` | Sources config.local file |
| `scripts/tools/daily-drive-sync.conf.example` | NEW - example config |
| `pacman-hooks/track-installs.hook` | Username-agnostic |
| `README.md` | Fixed broken references |
| `CLAUDE.md` | Updated entry points |
| `.claude/config.json` | Updated entryPoints (v2.0.0) |
| `.gitignore` | Added *.conf.local |
| `docs/` | Removed 7 dead files |

---

## Remaining Tasks (from Tech Plan)

### High Priority (Requires Sudo)

1. **System Cleanup**
   ```bash
   # Remove orphans
   sudo pacman -Rns $(pacman -Qdtq)

   # Clean package cache (keep 2 versions)
   sudo paccache -rk2

   # Vacuum journal
   sudo journalctl --vacuum-size=100M

   # Verify clean state
   check --deep
   ```

2. **Firewall Enablement**
   ```bash
   # Enable firewalld
   sudo systemctl enable --now firewalld

   # Allow SSH (if needed)
   sudo firewall-cmd --add-service=ssh --permanent
   sudo firewall-cmd --reload
   ```

### Medium Priority

3. **asusctl Service**
   - Currently not responding (service issue)
   - May need restart or reinstallation

4. **AMD False Positive in Detection**
   - Detection script finds AMD Host bridge, not GPU
   - Low impact (doesn't apply wrong optimizations)
   - Could refine regex pattern

### Low Priority

5. **Testing on Other Hardware**
   - Test on pure AMD system
   - Test on Intel-only system
   - Test on VM (no GPU)
   - Test on desktop (no laptop tools)

---

## Key Files Reference

### Scripts (Hardened)
| File | Purpose | Safety Features |
|------|---------|-----------------|
| `scripts/force-system-titlebars.sh` | Remove duplicate titlebars | Backup-first, merge rules |
| `scripts/restore-system-titlebars.sh` | Restore system titlebars | Backup-first, safer KWin restart |
| `scripts/fix-sddm-input.sh` | Fix SDDM input after sleep | No kernel module unload |
| `scripts/tools/daily-drive-sync.sh` | Drive backup sync | Config validation, safety checks |
| `scripts/tools/detect-hardware.sh` | Hardware detection | Read-only |
| `scripts/tools/apply-optimizations.sh` | Apply optimizations | Conditional, dry-run mode |
| `scripts/tools/rollback-optimizations.sh` | Rollback optimizations | Category-specific, dry-run |

### Configuration
| File | Purpose |
|------|---------|
| `scripts/tools/daily-drive-sync.conf.example` | Example config (committed) |
| `scripts/tools/daily-drive-sync.conf.local` | Machine-specific config (.gitignore'd) |
| `pacman-hooks/track-installs.hook` | Package tracking (username-agnostic) |

### Documentation
| File | Purpose |
|------|---------|
| `docs/SETTINGS-DOCUMENTATION.md` | Every setting documented |
| `docs/HARDWARE-AGNOSTIC-ARCHITECTURE.md` | Design documentation |
| `docs/EPIC-IMPLEMENTATION-STATUS.md` | Progress tracking |
| `docs/QUICK-REFERENCE.md` | Daily commands |
| `docs/NEXT_CHAT_HANDOFF.md` | This file |

---

## Commands Reference

### Commit Pending Changes
```bash
cd ~/garuda-restore
git add -A
git status  # Review changes
git commit -m "feat: harden scripts with backup-first and safety fixes

- force/restore-system-titlebars.sh: backup-first + merge logic
- fix-sddm-input.sh: removed evdev unload, uses udevadm trigger
- daily-drive-sync.sh: parametrized via config.local
- track-installs.hook: username-agnostic (${SUDO_USER:-%h})
- README.md, CLAUDE.md, .claude/config.json: fixed broken references
- docs/: removed 7 dead files (GEOGRAF, COMIC, HERO)
- .gitignore: added *.conf.local

Co-authored-by: Qwen-Coder <qwen-coder@alibabacloud.com>"
```

### Test Hardened Scripts
```bash
# Test force-system-titlebars.sh (creates backup)
./scripts/force-system-titlebars.sh

# Test restore-system-titlebars.sh (creates backup)
./scripts/restore-system-titlebars.sh

# Test fix-sddm-input.sh (requires sudo)
sudo ./scripts/fix-sddm-input.sh

# Test daily-drive-sync.sh (requires config.local)
./scripts/tools/daily-drive-sync.sh
```

---

## Safety Guarantees (After Hardening)

| Script | Before | After |
|--------|--------|-------|
| `force-system-titlebars.sh` | Overwrote kwinrulesrc | Backup-first, merges rules |
| `restore-system-titlebars.sh` | Overwrote kwinrulesrc, quit KWin | Backup-first, removes only our rules, safer restart |
| `fix-sddm-input.sh` | `modprobe -r evdev` (unsafe) | `udevadm trigger` (safe) |
| `daily-drive-sync.sh` | Hardcoded UUIDs/paths | Config file with validation |
| `track-installs.hook` | Hardcoded username | Username-agnostic |

---

## Testing Checklist

### Script Hardening Validation
- [ ] Run `force-system-titlebars.sh` - verify backup created
- [ ] Check backup file exists: `~/.config/kwinrulesrc.backup.*`
- [ ] Run `restore-system-titlebars.sh` - verify backup created
- [ ] Verify KWin survives restart (doesn't crash)
- [ ] Run `fix-sddm-input.sh` with sudo - verify no errors
- [ ] Test sleep/wake after fix - verify input works
- [ ] Create `daily-drive-sync.conf.local` - verify script runs
- [ ] Remove config file - verify script exits with instructions

### System Cleanup (Requires Sudo)
- [ ] Run `check --deep` - verify issues identified
- [ ] Run `update` with sudo - verify orphans/cache cleaned
- [ ] Enable firewall - verify SSH access preserved

---

## Known Issues / Risks

| Issue | Impact | Mitigation |
|-------|--------|------------|
| Sudo required for cleanup | Cannot auto-clean without password | User must run with sudo |
| Firewall inactive | Security risk | Prompt user during apply-optimizations |
| asusctl service not responding | Power profiles may not work | Restart service or reinstall |
| AMD false positive in detection | Low (no wrong optimizations) | Refine regex if needed |
| daily-drive-sync.conf.local missing | Script won't run | Exits with setup instructions |

---

## Next Session Starting Point

1. **Immediate:** Commit all pending changes
   ```bash
   cd ~/garuda-restore
   git add -A
   git commit -m "..."
   ```

2. **Short-term:** Run system cleanup with sudo
   ```bash
   ./scripts/tools/system-update.sh
   # Enter password when prompted
   ```

3. **Validation:** Test hardened scripts
   ```bash
   ./scripts/force-system-titlebars.sh
   ./scripts/restore-system-titlebars.sh
   check --deep
   ```

---

## Architecture Notes

### Backup-First Pattern
All destructive scripts now follow this pattern:
```bash
TIMESTAMP=$(date +%Y%m%d%H%M%S)
if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$TIMESTAMP"
    echo "✓ Backed up existing config"
fi
# Then merge or write new config
```

### Merge-Instead-Of-Overwrite Pattern
For files that may contain user data (kwinrulesrc, settings.json):
```bash
# Read existing content
# Remove only our specific entries (by UUID or key)
# Append new entries
# Update count/metadata
```

### Safe Device Re-probe Pattern
Instead of unloading kernel modules:
```bash
udevadm trigger --subsystem-match=input --action=add
```

---

*Handoff generated at end of session. Continue from "Next Session Starting Point" above.*
