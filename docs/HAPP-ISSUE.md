# Happ Logout/Login Issue

## Symptom
After logout/login, Happ cannot be launched (not from autostart, not from menu, not even from terminal). Requires reboot to fix.

## Root Cause
`happd.service` is a **system** service (runs as root, starts at boot). Its child process `sing-box` (VPN tunnel) survives logout because system services don't restart on session changes.

On next login:
- A new Happ GUI tries to connect to the OLD sing-box (stale D-Bus session, stale DISPLAY, stale XDG_RUNTIME_DIR)
- Connection fails or window doesn't appear
- If autostart runs Happ before the session is fully ready, it can corrupt the sing-box state, making even terminal launch fail

## Why Reboot Fixes It
Reboot restarts `happd.service` → fresh sing-box → Happ works.

## Why Terminal Launch Sometimes Works
When autostart is disabled, no Happ process corrupts the sing-box state. Terminal launch after session is fully ready sometimes succeeds.

## Potential Solutions
1. **Polkit rule** (~/10-happd-restart.rules): allows passwordless `systemctl restart happd.service`. Autostart restarts happd + sing-box on login, then launches Happ. (Currently not working — systemctl restart hangs even with polkit)
2. **Move happd to user service**: would die on logout automatically, but happd needs root for TUN interface creation
3. **Happ upstream fix**: Happ should detect stale sing-box and restart it
4. **Logout hook**: Run `systemctl restart happd.service` on logout (requires polkit)

## Workaround
Disable autostart. After reboot or login, launch Happ from terminal: `happ`
