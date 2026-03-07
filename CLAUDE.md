# garuda-restore

Complete backup and restore scripts for Garuda KDE Linux systems.

## Stack
- Platform: Garuda Linux (Arch-based) with KDE Plasma
- Language: Bash shell scripts
- Tools: rsync, tar, pacman, paru, systemd

## Entry Points
- Backup: `scripts/backup.sh`
- Restore: `scripts/restore.sh` (one-click, 23 steps)
- Health Check: `scripts/tools/system-health-check.sh` (check command)
- System Update: `scripts/tools/system-update.sh` (update command)
- Hardware Detection: `scripts/tools/detect-hardware.sh`
- Apply Optimizations: `scripts/tools/apply-optimizations.sh`
- Rollback Optimizations: `scripts/tools/rollback-optimizations.sh`
- Fix DDC/CI: `scripts/fix-ddc-config.sh`
- Fix SDDM Input: `scripts/fix-sddm-input.sh`
- Titlebar Scripts: `scripts/force-system-titlebars.sh`, `scripts/restore-system-titlebars.sh`
- Daily Backup: `scripts/daily-backup.sh` (systemd-triggered)
- Drive Sync: `scripts/tools/daily-drive-sync.sh` (requires config.local)

## Critical Rules
- Always use `set -e` at the start of scripts
- Use `sudo -v` to refresh credentials before sudo operations
- Fix ownership after sudo operations: `sudo chown -R $(id -u):$(id -g)`
- Always handle missing files gracefully: `|| true` or `2>/dev/null`
- Git: Ask before commit/push

## Script Patterns

### Header Format
```bash
echo "========================================"
echo "║   Section Title                       ║"
echo "========================================"
```

### Progress Indicators
```bash
echo "[1/14] Backing up package lists..."
echo "   ✓ Package lists saved"
```

### Directory Existence Check
```bash
[ -d "$HOME/.ssh" ] && cp -r "$HOME/.ssh" "$BACKUP_DIR/security/"
[ -f "$HOME/.bashrc" ] && cp "$HOME/.bashrc" "$BACKUP_DIR/dotfiles/"
```

### Sudo Operations
```bash
sudo -v 2>/dev/null || true
if sudo test -d "/etc/NetworkManager/system-connections"; then
    sudo cp -r "/etc/NetworkManager/system-connections" "$BACKUP_DIR/networks/"
    sudo chown -R $(id -u):$(id -g) "$BACKUP_DIR/networks/"
fi
```

## Directory Structure
```
scripts/           # All executable scripts
scripts/tools/     # Tool scripts (health check, update, detect, etc.)
docs/              # Documentation
pacman-hooks/      # Package tracking hooks
systemd/           # Systemd service/unit files
```

## Commands
```bash
# Run backup
./scripts/backup.sh

# One-click restore
./scripts/restore.sh

# Health check
check           # Quick (10 areas)
check --deep    # Deep (18 areas)

# System update
update

# Setup automated backups
./scripts/setup-daily-backup.sh
```

## Context
Read: docs/NEXT_CHAT_HANDOFF.md for session continuity
