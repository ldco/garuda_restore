# Pop!_OS App Parity Notes

This is the current Garuda package inventory translated into Pop!_OS/COSMIC terms. It is not a 1:1 package-name restore because Arch/AUR, Garuda, KDE, and Chaotic-AUR packages do not map directly to apt.

## Covered By `popos-cosmic-bootstrap.sh`

Core and development:

- Git, build tools, curl/wget, rsync, jq, ripgrep, fd, fzf, tmux, zsh, neovim, shellcheck, pipx, Python venv/pip, Docker, Tailscale, OpenSSH, firewalld, Flatpak.
- Node via nvm, Rust via rustup, Go/PHP/Ruby/Elixir/Erlang when the backup says they were installed.

Desktop and creative apps:

- Brave, Chromium, Firefox, Android Studio, Bitwarden, Blender, Discord, FileZilla, GIMP, Inkscape, Krita, Kdenlive, LibreOffice, OBS, qBittorrent, Signal, Slack, Steam, Telegram, Thunderbird, VLC, Zoom.
- Apt equivalents for Ardour, Audacity, darktable, digiKam, Foliate, FontForge, Ghostwriter, GSmartControl, HandBrake, KDE Connect, Okular, RawTherapee, Remmina, Raspberry Pi Imager, Scribus, Simple Scan, SoundConverter, Tor Browser Launcher, VeraCrypt, VirtualBox, Yakuake, and archive/filesystem utilities.

UX and data:

- Fonts, wallpapers, GTK dark theme preference, left-side GTK window buttons, browser/app configs, SSH/GPG, NetworkManager profiles, WireGuard, VS Code extensions, Docker client config, AI assistant config.

## Needs Manual Vendor Install Or Login

These cannot be guaranteed from standard Pop repositories or Flathub:

- DaVinci Resolve: download and install from Blackmagic Design.
- Cursor: download `.deb`/AppImage from Cursor.
- Hiddify Next, v2rayA, Xray, KelVPN, YPN, Prizrak Box, Exodus, Wire Desktop, Happ Desktop: vendor-specific packaging varies.
- OnlyOffice/WPS Office: can be installed by vendor `.deb`, Snap, or Flatpak depending on preferred source.
- Ollama: install from Ollama's official Linux installer if needed.
- Sublime Text: install from Sublime's apt repo or vendor `.deb`.

## Skipped By Design

These are Garuda/Arch/KDE-specific and should not be installed on Pop!_OS COSMIC:

- Garuda packages: `garuda-*`, `chaotic-*`, `paru`, `pacman*`, `rate-mirrors`, `reflector-simple`.
- KDE desktop shell stack: `plasma-*`, `kwin`, `powerdevil`, `sddm`, KDE window-button widgets, KWin effects.
- Arch kernel/package plumbing: `linux-zen`, `dracut`, `grub-garuda`, `snapper-support`, `os-prober-btrfs`.

## Remaining Risk

Package availability depends on the Pop!_OS base Ubuntu codename and enabled repositories. The script filters apt packages at runtime with `apt-cache show`, so unavailable package names are skipped and logged instead of failing the whole bootstrap.
