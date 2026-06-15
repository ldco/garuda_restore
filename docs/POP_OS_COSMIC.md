# Pop!_OS COSMIC Bootstrap

Use `scripts/popos-cosmic-bootstrap.sh` on a fresh Pop!_OS COSMIC install to recreate this workstation with the closest practical UX match.

## Run

```bash
cd ~/garuda-restore
./scripts/popos-cosmic-bootstrap.sh --backup-dir ~/garuda-backup-YYYY-MM-DD_HH-MM
```

Optional:

```bash
./scripts/popos-cosmic-bootstrap.sh --backup-dir ~/garuda-backup-YYYY-MM-DD_HH-MM --with-ai-models
./scripts/popos-cosmic-bootstrap.sh --dry-run
```

## What It Restores

- Apt packages for development, media, fonts, shells, Docker, Tailscale, VS Code, Brave, Flatpak, and COSMIC session components when present in Pop repositories.
- Flatpak desktop apps from Flathub.
- Portable UX defaults: dark GTK, left-side window buttons for GTK-aware apps, Wayland/portal environment settings, Noto and JetBrains Mono fonts.
- Fonts, wallpapers, icons, themes, ICC profiles, SSH/GPG, NetworkManager profiles, WireGuard, dotfiles, browser profiles, VS Code extensions, Docker client config, and AI tool config.
- Hardware-safe settings: NVIDIA DRM modeset config, NVMe scheduler rule, swappiness/VM tuning, power profiles, firewall.

See [`POP_OS_APP_PARITY.md`](POP_OS_APP_PARITY.md) for the current Garuda app inventory mapped to Pop!_OS equivalents, manual vendor installs, and skipped KDE/Garuda-only packages.

## Intentional Differences From Garuda/KDE

The Garuda restore script copies KDE/Plasma/KWin config wholesale. This script does not do that on COSMIC because those files are desktop-specific and can cause broken or stale behavior outside KDE.

Skipped KDE-only surfaces include:

- Plasma panels, widgets, KWin effects, KWin rules, KWin output config, PowerDevil settings, SDDM tweaks.
- KDE-only sleep/wake hooks unless you install and apply them manually after validating the same symptom exists on Pop!_OS.

This gives maximum similar daily UX without pretending COSMIC can consume KDE state directly.
