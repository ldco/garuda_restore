#!/bin/bash
# ============================================================================
# Setup Daily Drive Sync - Installs systemd timer for daily rsync backup
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/daily-drive-sync.sh"
SERVICE_DIR="$HOME/.config/systemd/user"

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║           Daily Drive Sync Setup                                     ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Source: /run/media/ldco/3734114f-7123-41f5-8f63-7f43c94879eb"
echo "Dest:   /run/media/ldco/LDCO_BCP_2TB"
echo ""

# Make script executable
chmod +x "$SYNC_SCRIPT"

# Ask for sync time
echo "What time should the sync run daily?"
read -p "Enter time in HH:MM format (default: 01:00): " SYNC_TIME
SYNC_TIME="${SYNC_TIME:-01:00}"

echo ""
echo "Configuration:"
echo "  Run daily at: $SYNC_TIME"
echo ""

mkdir -p "$SERVICE_DIR"

# Create service file
cat > "$SERVICE_DIR/drive-sync.service" << EOF
[Unit]
Description=Daily Drive Sync to Backup
Wants=graphical-session.target
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=$SYNC_SCRIPT
StandardOutput=journal
StandardError=journal
# Allow long-running sync
TimeoutStartSec=infinity

[Install]
WantedBy=default.target
EOF

# Create timer file
cat > "$SERVICE_DIR/drive-sync.timer" << EOF
[Unit]
Description=Daily Drive Sync Timer

[Timer]
OnCalendar=*-*-* $SYNC_TIME:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Reload systemd and enable timer
systemctl --user daemon-reload
systemctl --user enable drive-sync.timer
systemctl --user start drive-sync.timer

echo ""
echo "✓ Systemd timer installed and started!"
echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║                    Drive Sync Setup Complete!                         ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Commands:"
echo "  View timer status:   systemctl --user status drive-sync.timer"
echo "  View service logs:   journalctl --user -u drive-sync.service -f"
echo "  Run sync now:        systemctl --user start drive-sync.service"
echo "  Disable timer:       systemctl --user disable drive-sync.timer"
echo "  Stop timer:          systemctl --user stop drive-sync.timer"
echo ""
echo "To test the sync now, run:"
echo "  $SYNC_SCRIPT"
echo ""

