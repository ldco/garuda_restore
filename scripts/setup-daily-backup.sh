#!/bin/bash
# ============================================================================
# Setup Daily Backup - Installs systemd timer for daily backups
# ============================================================================
# This script sets up automatic daily backups with KDE notifications.
# You can choose between systemd timer (recommended) or cron.
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SCRIPT="$SCRIPT_DIR/daily-backup.sh"
SERVICE_DIR="$HOME/.config/systemd/user"

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║           Garuda KDE - Daily Backup Setup                            ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

# Make scripts executable
chmod +x "$SCRIPT_DIR/daily-backup.sh"
chmod +x "$SCRIPT_DIR/backup-settings.sh"

# Ask for backup destination
echo "Where do you want to store daily backups?"
echo "Default: $HOME/Backups"
read -p "Enter path (or press Enter for default): " BACKUP_DEST
BACKUP_DEST="${BACKUP_DEST:-$HOME/Backups}"
mkdir -p "$BACKUP_DEST"

# Ask for retention period
echo ""
echo "How many days to keep old backups?"
read -p "Enter days (default: 7): " KEEP_DAYS
KEEP_DAYS="${KEEP_DAYS:-7}"

# Ask for backup time
echo ""
echo "What time should the backup run daily?"
read -p "Enter time in HH:MM format (default: 14:00): " BACKUP_TIME
BACKUP_TIME="${BACKUP_TIME:-14:00}"

echo ""
echo "Configuration:"
echo "  Backup destination: $BACKUP_DEST"
echo "  Keep backups for:   $KEEP_DAYS days"
echo "  Run daily at:       $BACKUP_TIME"
echo ""

# Choose method
echo "Choose backup method:"
echo "  1) Systemd timer (recommended - better for KDE notifications)"
echo "  2) Cron job"
read -p "Enter choice [1/2]: " METHOD

if [ "$METHOD" = "2" ]; then
    # =========================================================================
    # CRON METHOD
    # =========================================================================
    echo ""
    echo "Setting up cron job..."
    
    # Parse time
    HOUR=$(echo "$BACKUP_TIME" | cut -d: -f1)
    MINUTE=$(echo "$BACKUP_TIME" | cut -d: -f2)
    
    # Create cron entry
    CRON_CMD="$MINUTE $HOUR * * * DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$(id -u)/bus BACKUP_DEST=$BACKUP_DEST KEEP_DAYS=$KEEP_DAYS $BACKUP_SCRIPT"
    
    # Add to crontab (avoiding duplicates)
    (crontab -l 2>/dev/null | grep -v "daily-backup.sh"; echo "$CRON_CMD") | crontab -
    
    echo "✓ Cron job installed!"
    echo ""
    echo "To view: crontab -l"
    echo "To remove: crontab -e (and delete the line)"
    
else
    # =========================================================================
    # SYSTEMD TIMER METHOD (recommended)
    # =========================================================================
    echo ""
    echo "Setting up systemd user timer..."
    
    mkdir -p "$SERVICE_DIR"
    
    # Create service file
    cat > "$SERVICE_DIR/garuda-backup.service" << EOF
[Unit]
Description=Garuda KDE Daily Backup
Wants=graphical-session.target
After=graphical-session.target

[Service]
Type=oneshot
Environment="BACKUP_DEST=$BACKUP_DEST"
Environment="KEEP_DAYS=$KEEP_DAYS"
ExecStart=$BACKUP_SCRIPT
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

    # Create timer file
    cat > "$SERVICE_DIR/garuda-backup.timer" << EOF
[Unit]
Description=Daily Garuda Backup Timer

[Timer]
OnCalendar=*-*-* $BACKUP_TIME:00
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
EOF

    # Reload systemd and enable timer
    systemctl --user daemon-reload
    systemctl --user enable garuda-backup.timer
    systemctl --user start garuda-backup.timer
    
    echo "✓ Systemd timer installed and started!"
    echo ""
    echo "Commands:"
    echo "  View timer status:   systemctl --user status garuda-backup.timer"
    echo "  View service logs:   journalctl --user -u garuda-backup.service"
    echo "  Run backup now:      systemctl --user start garuda-backup.service"
    echo "  Disable timer:       systemctl --user disable garuda-backup.timer"
    echo "  Stop timer:          systemctl --user stop garuda-backup.timer"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║                    Daily Backup Setup Complete!                       ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Backups will be saved to: $BACKUP_DEST"
echo "Old backups will be deleted after $KEEP_DAYS days"
echo ""
echo "To test the backup now, run:"
echo "  $BACKUP_SCRIPT"
echo ""

