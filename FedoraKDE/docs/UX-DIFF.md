# UX-DIFF — Garuda KDE 6.8.1 → Fedora KDE 6.8.2

Plasma 6.8.1 and 6.8.2 are config-compatible, so `~/.config` is transplanted
almost verbatim. The deliberate differences are listed here. The runtime
restore also writes `UX-DIFF-runtime.md` next to the logs every time an applet is
removed.

## Identical after provisioning

- 4 panels, applet order, panel geometry, Kickoff, icon tasks, system tray
- `BreezeDark` colour scheme, `Fira Sans` 12 / `FiraCode Nerd Font Mono` 12
- KWin effects (blur off, rounded corners off, coverswitch/flipswitch/fade on)
- `kwinoutputconfig.json`: `allowDdcCi=false`, VRR `Never`, scale 1.5/1.25
- KDE shortcuts, Dolphin/Konsole/Kate/Okular configurations
- wallpaper set (`~/Pictures/wallpapers` from the backup)
- zsh configuration, aliases, oh-my-zsh and plugins
- browser/app profiles where the app id matches

## Substituted

| Garuda | Fedora | Why |
|---|---|---|
| Dr460nized global theme | **Sweet** + BreezeDark, or Dr460nized assets extracted from the Garuda ISO squashfs | the Dr460nized package is Arch-only; Sweet is the upstream theme it is built on |
| Dr460nized SDDM theme | Breeze (or Sweet) SDDM theme | SDDM theme files are Arch-packaged |
| `linux-zen` | Fedora kernel 7.2 | Fedora ships its own kernel |
| AppArmor | **SELinux enforcing** | Fedora's security model |
| Garuda welcome/system-maintenance apps | Discover + `btrfs-assistant` | distro-specific tooling |
| Paru/Octopi | `dnf`/Discover | package manager |

## Dropped (unless a Fedora package exists)

| Item | Fallback |
|---|---|
| `plasma6-applets-window-title` | removed from the panel (runtime report) |
| `plasma6-applets-panel-colorizer` | removed from the panel (runtime report) |
| `plasma-applet-window-buttons` | removed from the panel (runtime report) |
| `kwin-effect-rounded-corners`, better-blur | not installed (effects were disabled anyway) |
| Garuda wallpapers, icons `BeautyLine` | user wallpapers + Sweet/Breeze icons |

The sanitizer comments out an applet block only when its provider RPM is absent;
it installs the three applets from Terra/COPR first if they are available.

## Known cosmetic differences

- SDDM greeter: Breeze/Sweet instead of Dr460nized.
- Plymouth boot splash: Fedora default instead of Garuda.
- Window buttons for GTK apps: `gsettings` sets the KDE layout
  (`close,minimize,maximize:`), same as before.
