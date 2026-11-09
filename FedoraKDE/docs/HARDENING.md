# HARDENING

## Baseline (applied by `provision`, asserted by `verify`)

| Control | Implementation |
|---|---|
| Mandatory access control | SELinux **enforcing** (`getenforce`) |
| Firewall | `firewalld` enabled + `plasma-firewall` |
| Kernel hardening | `/etc/sysctl.d/99-nocowboy-hardening.conf`: `kptr_restrict=2`, `dmesg_restrict=1`, `unprivileged_bpf_disabled=1`, `kexec_load_disabled=1`, `yama.ptrace_scope=1`, `fs.protected_{hardlinks,symlinks,fifos,regular}` |
| Memory | zram zstd up to 16 GiB, `vm.swappiness=133` |
| Updates | automatic **security-only** updates (`dnf-automatic` / `dnf5-plugin-automatic`) |
| Firmware | `fwupd` + `fwupd-refresh.timer`, LVFS BIOS updates available |
| Remote access | `sshd` not enabled |
| Privilege | only `wheel` can `sudo` (Fedora default) |
| Disk | LUKS2 argon2id + TPM2 PCR 7 (see `SECURE-BOOT-TPM2.md`) |
| Boot | Secure Boot + MOK-signed NVIDIA module |

## Opt-in (`--with-optional`)

`usbguard`, `fapolicyd`, `AIDE`, `auditd`, key-only `sshd`, `fail2ban`.
These can break Steam, USB devices and some installers, so they are never
enabled by default.

## Rollback

```bash
# kernel hardening
sudo rm /etc/sysctl.d/99-nocowboy-hardening.conf && sudo sysctl --system
# firewall
sudo systemctl disable --now firewalld
# zram
sudo rm /etc/systemd/zram-generator.conf && sudo systemctl daemon-reload
# automatic updates
sudo systemctl disable --now dnf5-automatic.timer   # or dnf-automatic.timer
# opt-in extras
sudo systemctl disable --now usbguard fapolicyd auditd fail2ban
```

## Not done on purpose

- No `fapolicyd` by default (breaks game launchers).
- No `usbguard` by default (a wrong rule set locks out input devices).
- No SSH by default.
- No third-party DNS or VPN forced by the installer.
