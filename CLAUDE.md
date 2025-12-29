# garuda-restore

Complete backup and restore scripts for Garuda KDE Linux systems.

## Stack
- Platform: Garuda Linux (Arch-based) with KDE Plasma
- Language: Bash shell scripts
- Tools: rsync, tar, pacman, paru, systemd

## Entry Points
- Backup: `scripts/backup-settings.sh`
- Restore: `scripts/restore.sh` (one-click wrapper)
- Full Restore: `scripts/restore-settings.sh`
- Daily Backup: `scripts/daily-backup.sh`
- Setup Timer: `scripts/setup-daily-backup.sh`

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
docs/              # Documentation (SYSTEM-DETECTION, SYSTEM-ANALYSIS)
fixes/             # System fixes with rollback
packages/          # Package lists for restore
```

## Commands
```bash
# Run backup
./scripts/backup-settings.sh

# One-click restore
./scripts/restore.sh

# Setup automated backups
./scripts/setup-daily-backup.sh
```

## Context
Read: .claude-data/context.md
Config: .claude/config.json
