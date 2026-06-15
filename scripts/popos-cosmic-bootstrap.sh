#!/usr/bin/env bash
# ============================================================================
# Pop!_OS COSMIC - Portable System Bootstrap
# ============================================================================
# Run this on a fresh Pop!_OS COSMIC installation to recreate the current
# Garuda/KDE workstation as closely as COSMIC reasonably allows.
#
# Usage:
#   ./scripts/popos-cosmic-bootstrap.sh
#   ./scripts/popos-cosmic-bootstrap.sh --backup-dir ~/garuda-backup-YYYY-MM-DD_HH-MM
#   ./scripts/popos-cosmic-bootstrap.sh --with-ai-models
#   ./scripts/popos-cosmic-bootstrap.sh --dry-run
# ============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKUP_DIR=""
WITH_AI_MODELS=false
DRY_RUN=false
ASSUME_YES=false
SHOW_MANUAL_LINKS=false

LOG_FILE="$HOME/.local/share/popos-cosmic-bootstrap/bootstrap.log"

APT_CORE_PACKAGES=(
  apt-transport-https
  bash-completion
  bat
  btop
  build-essential
  ca-certificates
  curl
  dconf-cli
  direnv
  fd-find
  file
  firewalld
  flatpak
  fonts-firacode
  fonts-jetbrains-mono
  fonts-noto
  fonts-noto-color-emoji
  fzf
  gcc
  gimp
  git
  git-lfs
  gnupg
  gparted
  htop
  imagemagick
  inkscape
  jq
  krita
  libglib2.0-bin
  lsb-release
  make
  neovim
  net-tools
  openssh-client
  openssh-server
  p7zip-full
  pciutils
  pipx
  python3
  python3-pip
  python3-venv
  ripgrep
  rsync
  shellcheck
  software-properties-common
  tmux
  tree
  ufw
  unzip
  vim
  wget
  xclip
  xdg-desktop-portal
  xdg-user-dirs
  xdg-utils
  zip
  zsh
)

APT_DESKTOP_PACKAGES=(
  ansible
  ardour
  audacity
  birdfont
  chromium-browser
  converseen
  darktable
  digikam
  elixir
  erlang
  exfatprogs
  fastfetch
  filezilla
  foliate
  fontforge
  ghostwriter
  grsync
  gsmartcontrol
  handbrake
  inxi
  k3b
  kate
  kcalc
  kdeconnect
  kdenlive
  kolourpaint
  kompare
  lazygit
  libdvd-pkg
  libreoffice
  lhasa
  luminance-hdr
  lvm2
  meld
  micro
  mpv
  mypaint
  nfs-common
  nmap
  nnn
  nvme-cli
  okular
  opus-tools
  pavucontrol
  powertop
  printer-driver-all
  qbittorrent
  rawtherapee
  remmina
  rpi-imager
  samba
  sane-airscan
  scribus
  simple-scan
  soundconverter
  sox
  steam-installer
  sshfs
  sshpass
  system-config-printer
  torbrowser-launcher
  traceroute
  unace
  unar
  unrar
  usbutils
  veracrypt
  virtualbox
  vlc
  whois
  xsel
  yakuake
  zoxide
)

COSMIC_PACKAGES=(
  cosmic-session
  cosmic-store
  cosmic-term
  cosmic-files
  cosmic-edit
  cosmic-settings
  xdg-desktop-portal-cosmic
)

FLATPAK_APPS=(
  app.drey.Apostrophe
  com.bitwarden.desktop
  com.brave.Browser
  com.discordapp.Discord
  com.github.tchx84.Flatseal
  com.google.AndroidStudio
  com.mattjakeman.ExtensionManager
  com.obsproject.Studio
  com.slack.Slack
  com.valvesoftware.Steam
  io.balena.etcher
  org.blender.Blender
  org.chromium.Chromium
  org.filezillaproject.Filezilla
  org.gimp.GIMP
  org.inkscape.Inkscape
  org.kde.kdenlive
  org.kde.krita
  org.libreoffice.LibreOffice
  org.mozilla.Thunderbird
  org.mozilla.firefox
  org.qbittorrent.qBittorrent
  org.signal.Signal
  org.telegram.desktop
  org.videolan.VLC
  us.zoom.Zoom
)

CONFIG_ALLOWLIST=(
  "BraveSoftware"
  "Code"
  "Code - Insiders"
  "Codium"
  "GIMP"
  "Google"
  "Mullvad VPN"
  "Qwen Code"
  "Slack"
  "VSCodium"
  "blender"
  "chromium"
  "code-flags.conf"
  "discord"
  "fontconfig"
  "git"
  "go"
  "gtk-3.0"
  "gtk-4.0"
  "inkscape"
  "krita"
  "mimeapps.list"
  "nvim"
  "obs-studio"
  "qwen-code"
  "tailscale"
  "tmux"
  "user-dirs.dirs"
  "user-dirs.locale"
)

LOCAL_SHARE_ALLOWLIST=(
  "TelegramDesktop"
  "applications"
  "color"
  "fonts"
  "icc"
  "icons"
  "krita"
  "mime"
  "nvim"
  "recently-used.xbel"
  "themes"
)

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --backup-dir DIR     Restore portable data from a garuda-backup directory
  --with-ai-models     Install ComfyUI/Fooocus and download large model files
  --manual-links       Print manual/vendor install notes and exit
  --yes, -y            Use defaults for prompts
  --dry-run            Print commands without changing the system
  --help, -h           Show this help

This script intentionally skips KDE/Plasma/KWin state on Pop!_OS COSMIC.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backup-dir)
      BACKUP_DIR="${2:-}"
      shift 2
      ;;
    --with-ai-models)
      WITH_AI_MODELS=true
      shift
      ;;
    --manual-links)
      SHOW_MANUAL_LINKS=true
      shift
      ;;
    --yes|-y)
      ASSUME_YES=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

mkdir -p "$(dirname "$LOG_FILE")"

log() {
  printf '%s\n' "$*" | tee -a "$LOG_FILE"
}

run() {
  log "+ $*"
  if [[ "$DRY_RUN" == false ]]; then
    "$@"
  fi
}

sudo_run() {
  if [[ "$DRY_RUN" == true ]]; then
    log "+ sudo $*"
  else
    sudo "$@"
  fi
}

write_file() {
  local path="$1"
  local content="$2"
  log "+ write $path"
  if [[ "$DRY_RUN" == false ]]; then
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$content" > "$path"
  fi
}

write_root_file() {
  local path="$1"
  local content="$2"
  log "+ sudo write $path"
  if [[ "$DRY_RUN" == false ]]; then
    printf '%s\n' "$content" | sudo tee "$path" >/dev/null
  fi
}

print_manual_install_notes() {
  cat <<'EOF'

================================================================
Manual/vendor installs still needed for full app parity
================================================================

These apps were present on the Garuda system or backup, but should not be
blindly installed from random scripts on a fresh Pop!_OS system. Use the
official/vendor page below, sign in where needed, and prefer .deb/AppImage
builds for Ubuntu/Pop when offered.

Video, creative, and developer tools:

  DaVinci Resolve
    Why manual: Blackmagic requires an interactive download/registration flow
    and Linux support is picky about GPU drivers and distribution packaging.
    Link: https://www.blackmagicdesign.com/support/family/davinci-resolve-and-fusion

  Cursor
    Why manual: fast-moving vendor editor; download the current Linux .deb or
    AppImage directly from Cursor.
    Link: https://cursor.com/download/

  Ollama
    Why manual: installer configures its own service and GPU runtime details.
    Link: https://docs.ollama.com/linux
    Typical command: curl -fsSL https://ollama.com/install.sh | sh

  Sublime Text
    Why manual: best installed from Sublime's own apt repository if you want
    automatic updates.
    Link: https://www.sublimetext.com/docs/linux_repositories.html

Office suites:

  ONLYOFFICE Desktop Editors
    Why manual: vendor .deb/apt repo is preferred if you need exact OnlyOffice,
    while LibreOffice is already installed by the bootstrap.
    Link: https://www.onlyoffice.com/download-desktop.aspx

  WPS Office
    Why manual: vendor package and licensing/update behavior are separate from
    Ubuntu/Pop repositories.
    Link: https://www.wps.com/office/linux/

Wallets and communication:

  Exodus
    Why manual: wallet software must only come from the official vendor source.
    Verify the URL carefully before entering seed phrases or credentials.
    Link: https://www.exodus.com/support/en/articles/8598640-how-do-i-install-exodus

  Wire Desktop
    Why manual: Linux is not listed as officially supported in Wire support
    docs, though desktop releases may exist. Prefer the web app unless you
    explicitly need the desktop client.
    Link: https://support.wire.com/hc/en-us/articles/202960551-What-do-I-need-to-use-Wire

VPN/proxy clients:

  Hiddify Next
    Why manual: current Linux AppImage/release assets should be downloaded from
    the active project release page.
    Link: https://hiddifynext.app/en/download/

  v2rayA
    Why manual: needs service/proxy configuration and often an Xray/v2ray core.
    Link: https://v2raya.org/en/docs/prologue/installation/

  Xray-core
    Why manual: low-level proxy core; install only if you know which client or
    service configuration will own it.
    Link: https://github.com/XTLS/Xray-core

  KelVPN
    Why manual: account/key and vendor package flow.
    Link: https://kelvpn.com/download/linux

  Happ Desktop
    Why manual: release/channel is project-specific; use current GitHub release
    assets or vendor-provided links.
    Link: https://github.com/Happ-proxy/happ-desktop/releases

  Prizrak Box
    Why manual: release assets are external/project-specific; verify publisher
    and subscription provider before installing.
    Link: https://nneov.com/en/download/

  YPN
    Why manual: service/account-specific app with limited package metadata.
    Link: https://ypngo.com/

After installing manual apps:

  1. Re-run this bootstrap if needed; it is designed to be idempotent.
  2. Restore app config from the backup only after the app has launched once.
  3. For VPN/proxy clients, import subscriptions/keys manually and test DNS/IP
     leaks before relying on them.
  4. Reboot after GPU, Docker, VPN, or system service installs.

================================================================
EOF
}

confirm() {
  local prompt="$1"
  if [[ "$ASSUME_YES" == true ]]; then
    return 0
  fi
  read -r -p "$prompt [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

apt_has_package() {
  apt-cache show "$1" >/dev/null 2>&1
}

apt_install_available() {
  local available=()
  local skipped=()
  local pkg

  for pkg in "$@"; do
    if apt_has_package "$pkg"; then
      available+=("$pkg")
    else
      skipped+=("$pkg")
    fi
  done

  if ((${#available[@]} > 0)); then
    sudo_run apt-get install -y --no-install-recommends "${available[@]}"
  fi

  if ((${#skipped[@]} > 0)); then
    log "Skipped packages not present in current Pop/Ubuntu repos: ${skipped[*]}"
  fi
}

ubuntu_repo_codename() {
  local detected="${1:-}"
  local selected="${UBUNTU_REPO_CODENAME:-}"

  if [[ -n "$selected" ]]; then
    printf '%s' "$selected"
    return
  fi

  case "$detected" in
    focal|jammy|noble|oracular|plucky|questing)
      printf '%s' "$detected"
      ;;
    *)
      printf '%s' "noble"
      ;;
  esac
}

backup_existing() {
  local path="$1"
  if [[ -e "$path" && ! -L "$path" ]]; then
    local backup="$path.popos-bootstrap-backup.$(date +%Y%m%d%H%M%S)"
    run mv "$path" "$backup"
  fi
}

rsync_copy() {
  local src="$1"
  local dst="$2"
  [[ -e "$src" ]] || return 0
  run mkdir -p "$(dirname "$dst")"
  run rsync -a "$src" "$dst"
}

detect_backup_dir() {
  if [[ -n "$BACKUP_DIR" ]]; then
    return
  fi

  local candidate
  candidate="$(find "$HOME" "$REPO_DIR" -maxdepth 2 -type d -name 'garuda-backup-*' 2>/dev/null | sort | tail -n 1 || true)"
  if [[ -n "$candidate" ]]; then
    BACKUP_DIR="$candidate"
  fi
}

validate_backup_dir() {
  [[ -n "$BACKUP_DIR" ]] || return 0
  if [[ ! -d "$BACKUP_DIR" ]]; then
    echo "Backup directory does not exist: $BACKUP_DIR" >&2
    exit 1
  fi
  log "Using backup directory: $BACKUP_DIR"
}

print_header() {
  log "================================================================"
  log "Pop!_OS COSMIC workstation bootstrap"
  log "User: $USER"
  log "Home: $HOME"
  log "Log:  $LOG_FILE"
  log "================================================================"
}

ensure_popos() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    log "Detected OS: ${PRETTY_NAME:-unknown}"
    if [[ "${ID:-}" != "pop" && "${ID_LIKE:-}" != *"ubuntu"* ]]; then
      log "Warning: this is tuned for Pop!_OS/Ubuntu-family systems."
      confirm "Continue anyway?" || exit 1
    fi
  fi
}

update_system() {
  log "[1/15] Updating apt metadata and base system"
  sudo_run apt-get update
  sudo_run env DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y
}

install_core_packages() {
  log "[2/15] Installing core workstation packages"
  apt_install_available "${APT_CORE_PACKAGES[@]}"
  apt_install_available "${APT_DESKTOP_PACKAGES[@]}"
}

install_cosmic_packages() {
  log "[3/15] Ensuring COSMIC session components are present"
  apt_install_available "${COSMIC_PACKAGES[@]}"
}

install_vendor_repos() {
  log "[4/15] Installing vendor repositories for Docker, VS Code, Brave, and Tailscale"

  sudo_run install -m 0755 -d /etc/apt/keyrings

  if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
    run curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /tmp/docker.asc
    sudo_run install -m 0644 /tmp/docker.asc /etc/apt/keyrings/docker.asc
  fi

  local detected_codename codename arch
  detected_codename="$(. /etc/os-release && printf '%s' "${UBUNTU_CODENAME:-${VERSION_CODENAME:-noble}}")"
  codename="$(ubuntu_repo_codename "$detected_codename")"
  if [[ "$codename" != "$detected_codename" ]]; then
    log "Repo codename '$detected_codename' may be unsupported by vendor repos; using '$codename'. Override with UBUNTU_REPO_CODENAME=..."
  fi
  arch="$(dpkg --print-architecture)"

  if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
    write_root_file /etc/apt/sources.list.d/docker.list "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $codename stable"
  fi

  if [[ ! -f /etc/apt/keyrings/packages.microsoft.gpg ]]; then
    run curl -fsSL https://packages.microsoft.com/keys/microsoft.asc -o /tmp/packages.microsoft.asc
    run gpg --dearmor -o /tmp/packages.microsoft.gpg /tmp/packages.microsoft.asc
    sudo_run install -m 0644 /tmp/packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
  fi

  if [[ ! -f /etc/apt/sources.list.d/vscode.list ]]; then
    write_root_file /etc/apt/sources.list.d/vscode.list "deb [arch=$arch signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main"
  fi

  if [[ ! -f /etc/apt/keyrings/brave-browser-archive-keyring.gpg ]]; then
    run curl -fsSLo /tmp/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
    sudo_run install -m 0644 /tmp/brave-browser-archive-keyring.gpg /etc/apt/keyrings/brave-browser-archive-keyring.gpg
  fi

  if [[ ! -f /etc/apt/sources.list.d/brave-browser-release.sources ]]; then
    write_root_file /etc/apt/sources.list.d/brave-browser-release.sources "Types: deb
URIs: https://brave-browser-apt-release.s3.brave.com/
Suites: stable
Components: main
Architectures: $arch
Signed-By: /etc/apt/keyrings/brave-browser-archive-keyring.gpg"
  fi

  if [[ ! -f /usr/share/keyrings/tailscale-archive-keyring.gpg ]]; then
    run curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/$codename.noarmor.gpg" -o /tmp/tailscale.gpg
    sudo_run install -m 0644 /tmp/tailscale.gpg /usr/share/keyrings/tailscale-archive-keyring.gpg
  fi

  if [[ ! -f /etc/apt/sources.list.d/tailscale.list ]]; then
    run curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/$codename.tailscale-keyring.list" -o /tmp/tailscale.list
    sudo_run install -m 0644 /tmp/tailscale.list /etc/apt/sources.list.d/tailscale.list
  fi

  sudo_run apt-get update
  apt_install_available brave-browser code docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin tailscale
}

configure_flatpak() {
  log "[5/15] Configuring Flatpak and installing desktop apps"
  if ! flatpak remotes 2>/dev/null | awk '{print $1}' | grep -qx flathub; then
    run flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  fi

  local app
  for app in "${FLATPAK_APPS[@]}"; do
    run flatpak install -y --or-update flathub "$app" || true
  done
}

configure_ux() {
  log "[6/15] Applying portable COSMIC/GTK UX settings"

  run mkdir -p "$HOME/.config/environment.d"
  write_file "$HOME/.config/environment.d/cosmic-portable.conf" "# Portable Wayland/portal defaults from garuda-restore Pop!_OS bootstrap.
MOZ_ENABLE_WAYLAND=1
MOZ_USE_XINPUT2=1
GTK_USE_PORTAL=1
ELECTRON_OZONE_PLATFORM_HINT=auto
NPM_CONFIG_PREFIX=$HOME/.local"

  if have_cmd gsettings; then
    run gsettings set org.gnome.desktop.wm.preferences button-layout 'close,minimize,maximize:' || true
    run gsettings set org.gnome.desktop.interface clock-show-weekday true || true
    run gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true
    run gsettings set org.gnome.desktop.interface document-font-name 'Noto Sans 10' || true
    run gsettings set org.gnome.desktop.interface font-name 'Noto Sans 10' || true
    run gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrains Mono 10' || true
  fi

  run mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
  write_file "$HOME/.config/gtk-3.0/settings.ini" "[Settings]
gtk-application-prefer-dark-theme=1
gtk-decoration-layout=close,minimize,maximize:
gtk-font-name=Noto Sans 10
gtk-monospace-font-name=JetBrains Mono 10"
  write_file "$HOME/.config/gtk-4.0/settings.ini" "[Settings]
gtk-application-prefer-dark-theme=1
gtk-decoration-layout=close,minimize,maximize:
gtk-font-name=Noto Sans 10
gtk-monospace-font-name=JetBrains Mono 10"
}

configure_hardware() {
  log "[7/15] Applying Pop-safe hardware optimizations"

  if lspci | grep -qi nvidia; then
    sudo_run sed -i 's/^#\?WaylandEnable=.*/WaylandEnable=true/' /etc/gdm3/custom.conf 2>/dev/null || true
    sudo_run install -d /etc/modprobe.d
    write_root_file /etc/modprobe.d/nvidia-drm-modeset.conf "options nvidia_drm modeset=1"

    if ! have_cmd nvidia-smi && confirm "NVIDIA GPU detected but nvidia-smi is missing. Run ubuntu-drivers autoinstall?"; then
      apt_install_available ubuntu-drivers-common
      sudo_run ubuntu-drivers autoinstall
    fi
  fi

  if [[ -d /sys/module/zswap ]]; then
    write_root_file /etc/sysctl.d/99-popos-workstation.conf "vm.swappiness=133
vm.dirty_ratio=20
vm.dirty_background_ratio=10"
    sudo_run sysctl -p /etc/sysctl.d/99-popos-workstation.conf || true
  fi

  if compgen -G "/sys/block/nvme*" >/dev/null; then
    write_root_file /etc/udev/rules.d/60-nvme-scheduler.rules 'ACTION=="add|change", KERNEL=="nvme*", ATTR{queue/scheduler}="kyber"'
  fi

  sudo_run systemctl enable --now power-profiles-daemon || true
  sudo_run systemctl enable --now firewalld || true
}

restore_fonts_themes_wallpapers() {
  log "[8/15] Restoring fonts, themes, icons, wallpapers, and ICC profiles"
  [[ -n "$BACKUP_DIR" ]] || return 0

  rsync_copy "$BACKUP_DIR/.fonts/" "$HOME/.fonts/"
  rsync_copy "$BACKUP_DIR/.local-share-fonts/" "$HOME/.local/share/fonts/"
  rsync_copy "$BACKUP_DIR/.icons/" "$HOME/.icons/"
  rsync_copy "$BACKUP_DIR/.themes/" "$HOME/.themes/"
  rsync_copy "$BACKUP_DIR/local-share-themes/" "$HOME/.local/share/themes/"
  rsync_copy "$BACKUP_DIR/wallpapers/" "$HOME/Pictures/"
  rsync_copy "$BACKUP_DIR/icc-profiles/" "$HOME/.local/share/icc/"

  run fc-cache -fv
}

restore_portable_config() {
  log "[9/15] Restoring portable app config while skipping KDE/Plasma state"
  [[ -n "$BACKUP_DIR" ]] || return 0

  local item src dst
  if [[ -d "$BACKUP_DIR/config" ]]; then
    for item in "${CONFIG_ALLOWLIST[@]}"; do
      src="$BACKUP_DIR/config/$item"
      dst="$HOME/.config/$item"
      [[ -e "$src" ]] || continue
      backup_existing "$dst"
      rsync_copy "$src" "$dst"
    done
  fi

  if [[ -d "$BACKUP_DIR/local-share" ]]; then
    for item in "${LOCAL_SHARE_ALLOWLIST[@]}"; do
      src="$BACKUP_DIR/local-share/$item"
      dst="$HOME/.local/share/$item"
      [[ -e "$src" ]] || continue
      backup_existing "$dst"
      rsync_copy "$src" "$dst"
    done
  fi
}

restore_security_networks() {
  log "[10/15] Restoring SSH/GPG credentials and NetworkManager profiles"
  [[ -n "$BACKUP_DIR" ]] || return 0

  if [[ -d "$BACKUP_DIR/security/.ssh" ]]; then
    backup_existing "$HOME/.ssh"
    rsync_copy "$BACKUP_DIR/security/.ssh/" "$HOME/.ssh/"
    run chmod 700 "$HOME/.ssh"
    run find "$HOME/.ssh" -type f -not -name '*.pub' -exec chmod 600 {} +
    run find "$HOME/.ssh" -type f -name '*.pub' -exec chmod 644 {} +
  fi

  if [[ -d "$BACKUP_DIR/security/.gnupg" ]]; then
    backup_existing "$HOME/.gnupg"
    rsync_copy "$BACKUP_DIR/security/.gnupg/" "$HOME/.gnupg/"
    run chmod 700 "$HOME/.gnupg"
  fi

  rsync_copy "$BACKUP_DIR/security/.password-store/" "$HOME/.password-store/"

  if [[ -d "$BACKUP_DIR/networks/system-connections" ]]; then
    sudo_run mkdir -p /etc/NetworkManager/system-connections
    sudo_run rsync -a "$BACKUP_DIR/networks/system-connections/" /etc/NetworkManager/system-connections/
    sudo_run chmod 600 /etc/NetworkManager/system-connections/* || true
    sudo_run systemctl restart NetworkManager || true
  fi

  if [[ -d "$BACKUP_DIR/networks/wireguard" ]]; then
    sudo_run rsync -a "$BACKUP_DIR/networks/wireguard/" /etc/wireguard/
  fi
}

restore_dotfiles_dev() {
  log "[11/15] Restoring dotfiles and development environments"
  [[ -n "$BACKUP_DIR" ]] || return 0

  if [[ -d "$BACKUP_DIR/dotfiles" ]]; then
    local dot base
    for dot in "$BACKUP_DIR/dotfiles"/.* "$BACKUP_DIR/dotfiles"/*; do
      [[ -e "$dot" ]] || continue
      base="$(basename "$dot")"
      [[ "$base" == "." || "$base" == ".." || "$base" == "git" || "$base" == "oh-my-zsh-custom" ]] && continue
      [[ -f "$dot" ]] || continue
      backup_existing "$HOME/$base"
      rsync_copy "$dot" "$HOME/$base"
    done
    rsync_copy "$BACKUP_DIR/dotfiles/git/" "$HOME/.config/git/"
    rsync_copy "$BACKUP_DIR/dotfiles/oh-my-zsh-custom/" "$HOME/.oh-my-zsh/custom/"
  fi

  if [[ -d "$BACKUP_DIR/dev-envs" ]]; then
    rsync_copy "$BACKUP_DIR/dev-envs/.npmrc" "$HOME/.npmrc"
    rsync_copy "$BACKUP_DIR/dev-envs/.yarnrc" "$HOME/.yarnrc"
    rsync_copy "$BACKUP_DIR/dev-envs/.yarnrc.yml" "$HOME/.yarnrc.yml"
    rsync_copy "$BACKUP_DIR/dev-envs/.condarc" "$HOME/.condarc"
    rsync_copy "$BACKUP_DIR/dev-envs/.pip/" "$HOME/.pip/"
    rsync_copy "$BACKUP_DIR/dev-envs/.config/pip/" "$HOME/.config/pip/"
    rsync_copy "$BACKUP_DIR/dev-envs/.cargo/" "$HOME/.cargo/"
    rsync_copy "$BACKUP_DIR/dev-envs/go/" "$HOME/go/"
    rsync_copy "$BACKUP_DIR/dev-envs/.config/go/" "$HOME/.config/go/"
    rsync_copy "$BACKUP_DIR/dev-envs/.composer/" "$HOME/.composer/"
    rsync_copy "$BACKUP_DIR/dev-envs/.config/composer/" "$HOME/.config/composer/"
    rsync_copy "$BACKUP_DIR/dev-envs/.gemrc" "$HOME/.gemrc"

    if [[ -f "$BACKUP_DIR/dev-envs/installed-tools.txt" ]]; then
      grep -qx "nodejs" "$BACKUP_DIR/dev-envs/installed-tools.txt" && install_node || true
      grep -qx "rust" "$BACKUP_DIR/dev-envs/installed-tools.txt" && install_rust || true
      grep -qx "go" "$BACKUP_DIR/dev-envs/installed-tools.txt" && apt_install_available golang || true
      grep -qx "php" "$BACKUP_DIR/dev-envs/installed-tools.txt" && apt_install_available php composer || true
      grep -qx "ruby" "$BACKUP_DIR/dev-envs/installed-tools.txt" && apt_install_available ruby-full rubygems || true
    fi
  fi
}

install_node() {
  if [[ ! -d "$HOME/.nvm" ]]; then
    run curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh -o /tmp/nvm-install.sh
    run bash /tmp/nvm-install.sh
  fi

  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1091
  [[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"
  if have_cmd nvm; then
    local node_ver="--lts"
    [[ -f "$BACKUP_DIR/dev-envs/node-version.txt" ]] && node_ver="$(tr -d 'v' < "$BACKUP_DIR/dev-envs/node-version.txt")"
    run nvm install "$node_ver" || run nvm install --lts
    run nvm alias default "$node_ver" || true
  fi
}

install_rust() {
  if ! have_cmd rustup; then
    run curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o /tmp/rustup-init.sh
    run sh /tmp/rustup-init.sh -y
  fi
}

restore_apps_browsers_ai() {
  log "[12/15] Restoring browsers, app plugins, Docker config, and AI tool config"
  [[ -n "$BACKUP_DIR" ]] || return 0

  rsync_copy "$BACKUP_DIR/browsers/mozilla/" "$HOME/.mozilla/"
  rsync_copy "$BACKUP_DIR/browsers/librewolf/" "$HOME/.librewolf/"
  rsync_copy "$BACKUP_DIR/blender/" "$HOME/.config/blender/"
  rsync_copy "$BACKUP_DIR/app-data/GIMP/" "$HOME/.config/GIMP/"
  rsync_copy "$BACKUP_DIR/app-data/inkscape-extensions/" "$HOME/.config/inkscape/extensions/"
  rsync_copy "$BACKUP_DIR/app-data/krita/" "$HOME/.local/share/krita/"
  rsync_copy "$BACKUP_DIR/docker/.docker/" "$HOME/.docker/"

  if [[ -f "$BACKUP_DIR/app-data/vscode-extensions.txt" ]] && have_cmd code; then
    while IFS= read -r ext; do
      [[ -n "$ext" ]] && run code --install-extension "$ext" || true
    done < "$BACKUP_DIR/app-data/vscode-extensions.txt"
  fi

  rsync_copy "$BACKUP_DIR/ai-tools/claude-code/.claude.json" "$HOME/.claude.json"
  rsync_copy "$BACKUP_DIR/ai-tools/claude-code/settings.json" "$HOME/.claude/settings.json"
  rsync_copy "$BACKUP_DIR/ai-tools/claude-code/.credentials.json" "$HOME/.claude/.credentials.json"
  rsync_copy "$BACKUP_DIR/ai-tools/claude-code/commands/" "$HOME/.claude/commands/"
  rsync_copy "$BACKUP_DIR/ai-tools/claude-code/templates/" "$HOME/.claude/templates/"
  rsync_copy "$BACKUP_DIR/ai-tools/claude-code/roles/" "$HOME/.claude/roles/"
  rsync_copy "$BACKUP_DIR/ai-tools/claude-code/scripts/" "$HOME/.claude/scripts/"
  rsync_copy "$BACKUP_DIR/ai-tools/claude-code/knowledge/" "$HOME/.claude/knowledge/"
  rsync_copy "$BACKUP_DIR/ai-tools/codex/" "$HOME/.codex/"
  rsync_copy "$BACKUP_DIR/ai-tools/qwen-code/.qwen-code.json" "$HOME/.qwen-code.json"
  rsync_copy "$BACKUP_DIR/ai-tools/qwen-code/home-dot-qwen-code/" "$HOME/.qwen-code/"
  rsync_copy "$BACKUP_DIR/ai-tools/qwen-code/home-dot-qwen/" "$HOME/.qwen/"
  rsync_copy "$BACKUP_DIR/ai-tools/qwen-code/config-qwen-code/" "$HOME/.config/qwen-code/"
}

install_ai_tools() {
  log "[13/15] Installing AI workbench launch directories"

  if [[ "$WITH_AI_MODELS" == false ]]; then
    log "Skipping ComfyUI/Fooocus model downloads. Re-run with --with-ai-models to fetch large models."
    return 0
  fi

  apt_install_available python3-venv python3-pip git wget

  if [[ ! -d "$HOME/ComfyUI" ]]; then
    run git clone https://github.com/Comfy-Org/ComfyUI.git "$HOME/ComfyUI"
  fi
  run python3 -m venv "$HOME/ComfyUI/venv"
  run "$HOME/ComfyUI/venv/bin/pip" install --upgrade pip
  run "$HOME/ComfyUI/venv/bin/pip" install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu126
  run "$HOME/ComfyUI/venv/bin/pip" install -r "$HOME/ComfyUI/requirements.txt"

  if [[ ! -d "$HOME/Fooocus" ]]; then
    run git clone https://github.com/lllyasviel/Fooocus.git "$HOME/Fooocus"
  fi
  run python3 -m venv "$HOME/Fooocus/venv"
  run "$HOME/Fooocus/venv/bin/pip" install --upgrade pip
  run "$HOME/Fooocus/venv/bin/pip" install torch torchvision --index-url https://download.pytorch.org/whl/cu121
  run "$HOME/Fooocus/venv/bin/pip" install -r "$HOME/Fooocus/requirements_versions.txt"
}

enable_services() {
  log "[14/15] Enabling common services"
  sudo_run usermod -aG docker "$USER" || true
  sudo_run systemctl enable --now docker || true
  sudo_run systemctl enable --now ssh || true
  sudo_run systemctl enable --now tailscaled || true
  sudo_run systemctl enable --now firewalld || true
  run systemctl --user daemon-reload || true
}

final_update() {
  log "[15/15] Final refresh"
  sudo_run apt-get update
  sudo_run apt-get autoremove -y
  if have_cmd flatpak; then
    run flatpak update -y || true
  fi
  run xdg-user-dirs-update || true
  run update-desktop-database "$HOME/.local/share/applications" || true
  run fc-cache -fv || true
}

main() {
  if [[ "$SHOW_MANUAL_LINKS" == true ]]; then
    print_manual_install_notes
    exit 0
  fi

  detect_backup_dir
  validate_backup_dir
  print_header
  ensure_popos

  update_system
  install_core_packages
  install_cosmic_packages
  install_vendor_repos
  configure_flatpak
  configure_ux
  configure_hardware
  restore_fonts_themes_wallpapers
  restore_portable_config
  restore_security_networks
  restore_dotfiles_dev
  restore_apps_browsers_ai
  install_ai_tools
  enable_services
  final_update

  log "================================================================"
  log "Pop!_OS COSMIC bootstrap complete."
  log "Reboot required for drivers, services, fonts, groups, and Wayland env."
  log "Run: sudo reboot"
  log "================================================================"
  print_manual_install_notes | tee -a "$LOG_FILE"
}

main "$@"
