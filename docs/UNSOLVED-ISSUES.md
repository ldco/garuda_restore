# Unsolved System Issues

> Last updated: 2026-06-14

---

## 1. Happ — Fails After Logout/Login

### Symptom
- After **reboot**, Happ works (autostart, menu, terminal — all OK)
- After **logout/login**, Happ **cannot** be launched from anywhere — not autostart, not menu, not terminal
- Only way to recover: **reboot**
- Happ is essential for work (VPN-based app, `happ-desktop-bin` AUR package)

### Root Cause
`happd.service` is a **system** service (runs as root at `/etc/systemd/system/happd.service`). It spawns `sing-box` (VPN tunnel) as a child process.

System services survive logout. After login, the new Happ GUI tries to connect to the **old** `sing-box` from the previous session. The old tunnel has stale D-Bus credentials, stale `XDG_RUNTIME_DIR`, and stale display state. Connection fails silently — Happ exits with code 0 but no window appears.

### What We Tried
1. Polkit rule to allow passwordless `systemctl restart happd.service` on login — `systemctl restart` still hangs even with polkit
2. Killing stale `sing-box` on login — user can't kill root-owned processes
3. Adding `QT_QPA_PLATFORM=wayland` — needed for GUI launch, doesn't fix stale tunnel
4. Delaying autostart with `sleep` — doesn't help, tunnel state is the issue
5. Disabling autostart entirely — prevents state corruption on login, but terminal launch still fails

### Potential Fix Paths
- **Happ upstream**: app should detect stale `sing-box` and restart it
- **happd.service redesign**: should be a user service (dies on logout) but needs root for TUN interface
- **systemd session hook**: `BindsTo=graphical-session.target` with `StopWhenUnneeded=yes` on happd — requires modifying system service
- **Logout script**: `systemctl restart happd.service` on KDE logout (blocked by polkit/sudo)

### Workaround
Reboot after each logout. Launch Happ from terminal: `happ`.

---

## 2. DaVinci Resolve — Missing From Application Menu & Favorites

### Symptom
- **Was visible** in Dashboard (full-screen launcher) but not in Application Menu or Favorites
- After attempting fixes, **disappeared from Dashboard too**
- Icon never appears in KDE Application Launcher (Kickoff)
- `Alt+Space` → search does not find it
- DaVinci works fine when launched from terminal: `/opt/resolve/bin/resolve`

### Root Cause (likely)
Multiple contributing factors found:

1. **`Hidden=true` override**: A file `~/.local/share/applications/com.blackmagicdesign.resolve.desktop` had `Hidden=true` — this was what KDE Dashboard used but Kickoff ignored. Deleted during troubleshooting.

2. **Two conflicting menu XML files**:
   - `/etc/xdg/menus/DaVinciResolve.menu` — filters for `com.blackmagicdesign.resolve.desktop` (Blackmagic naming)
   - `/etc/xdg/menus/applications-merged/DaVinciResolve.menu` — filters for `DaVinciResolve.desktop` (AUR package naming)
   - The merged version (used by Kickoff) was the correct one, but the desktop file name mismatch caused confusion

3. **Duplicate desktop files**: Both `/usr/share/applications/DaVinciResolve.desktop` (system, no Categories) and `~/.local/share/applications/DaVinciResolve.desktop` (user, has Categories) exist — KDE may be confused by same-name duplicates

4. **System desktop file missing `Categories=`**: Without categories, KDE Kickoff doesn't place the app in the menu hierarchy

### Current State
- User desktop file exists: `~/.local/share/applications/DaVinciResolve.desktop`
- Contains correct `Categories=AudioVideo;Video;`
- Contains correct `Icon=/opt/resolve/graphics/DV_Resolve.png`
- System file at `/usr/share/applications/DaVinciResolve.desktop` still exists (no Categories)
- KDE cache rebuilt multiple times — app still doesn't appear

### Potential Fix Paths
- Remove system desktop file (`sudo mv /usr/share/applications/DaVinciResolve.desktop /usr/share/applications/DaVinciResolve.desktop.bak`) — test if single file works
- Reinstall `davinci-resolve` package — may restore original desktop integration
- Create entry manually via KDE Menu Editor (right-click launcher → Edit Applications)
- Check if `/opt/resolve/` path requires special XDG_DATA_DIRS

### Workaround
Launch from terminal: `/opt/resolve/bin/resolve`

---

## 3. Sleep/Suspend — GPU Artifacts on Wake

### Symptom
Screen artifacts (visual corruption) after system resumes from sleep.

### Root Cause
System uses `s2idle` (modern standby / S0ix) by default. NVIDIA GPU with open kernel module 610.x does not properly preserve VRAM across S0ix suspend/resume cycles.

### Fix (not applied yet)
Switch to S3 (deep) sleep mode:
```bash
# Temporary:
sudo sh -c 'echo deep > /sys/power/mem_sleep'

# Permanent:
sudo sed -i 's/quiet/quiet mem_sleep_default=deep/' /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg
```
