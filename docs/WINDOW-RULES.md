# KDE Window Rules - Autostart Monitor Placement

Configuration for placing applications on specific monitors at startup.

---

## Window Button Consistency

**Problem:** Some apps show duplicate titlebars - both KDE system titlebar AND the app's own colored titlebar.

### Quick Fix - Remove Duplicate Titlebars

Run the script to remove system titlebars from Electron/GTK apps:

```bash
~/garuda-restore/scripts/force-system-titlebars.sh
```

This configures KWin to **not decorate** apps that already have their own titlebars (CSD):
- VS Code, Chrome, Brave, Discord, Slack
- Only the app's colored titlebar will show
- No more duplicate titlebars in the top-left corner

---

## Monitor Layout

| Output | Position | Resolution | Description |
|--------|----------|------------|-------------|
| eDP-2 | 0,0 | 1707x960 (scaled) | Built-in laptop display |
| HDMI-A-1 | 1707,0 | 2048x1152 (scaled) | Middle external monitor |
| DP-1 | 3755,0 | 2048x1152 (scaled) | Right external monitor |

## Window Rules

File: `~/.config/kwinrulesrc`

| Application | Monitor | State | wmclass |
|-------------|---------|-------|---------|
| Telegram | eDP-2 (laptop) | Maximized | telegram |
| VSCode | HDMI-A-1 (middle) | Maximized | code |
| Chrome | HDMI-A-1 (middle) | Maximized | chrome |
| Chromium | DP-1 (right) | Maximized | chromium |
| Brave | DP-1 (right) | Maximized | brave |

## Rule Settings

- **screenrule=1**: Apply Initially (only on window open, allows moving after)
- **screenrule=2**: Force (always enforced, cannot move)
- **wmclassmatch=2**: Substring match (matches if wmclass contains the value)

## Autostart Entries

Location: `~/.config/autostart/`

- `google-chrome.desktop` - Chrome browser

## Commands

```bash
# Reload KWin rules without logout
qdbus org.kde.KWin /KWin org.kde.KWin.reconfigure

# Get window info for active window
qdbus org.kde.KWin /KWin queryWindowInfo

# List all windows (requires kdotool)
kdotool search --class ""

# Get specific window info
qdbus org.kde.KWin /KWin org.kde.KWin.getWindowInfo "{uuid}"

# Check monitor layout
kscreen-doctor -o
```

## Finding Window Class

To find an application's window class:

1. Open the application
2. Run: `kdotool getactivewindow` (click on the window first)
3. Then: `qdbus org.kde.KWin /KWin queryWindowInfo`
4. Look for `resourceClass` in the output

## Backup

The kwinrulesrc file should be included in system backup:
```bash
cp ~/.config/kwinrulesrc /path/to/backup/
```
