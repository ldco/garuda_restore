#!/usr/bin/env bash
# Stage: ux - transplant the Garuda KDE 6.8 experience onto Fedora KDE 6.8.
set -Eeuo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

TARBALL="${FEDORA_KDE_BACKUP_TARBALL:-}"
REPORT=""
TMP=""
USER_NAME="$(target_user)"
HOME_DIR="$(user_home)"
APPLETS="$HOME_DIR/.config/plasma-org.kde.plasma.desktop-appletsrc"

cleanup() { [[ -n "$TMP" && -d "$TMP" ]] && rm -rf "$TMP"; }
trap cleanup EXIT

usage() {
  cat <<'EOF'
restore-ux [options]

  --tarball PATH   garuda backup tarball (default: newest -last.tar.gz on the WD)
  --dry-run        print the plan, change nothing
EOF
}

parse_args() {
  while (( $# )); do
    case "$1" in
      --tarball) TARBALL="${2:?--tarball needs a value}"; shift ;;
      --dry-run) FEDORA_KDE_DRY_RUN=1; export FEDORA_KDE_DRY_RUN ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown argument: $1" ;;
    esac
    shift
  done
}

resolve_tarball() {
  [[ -n "$TARBALL" ]] && { printf '%s\n' "$TARBALL"; return 0; }
  local st
  st="$(state_get tarball-used)"
  [[ -n "$st" && -f "$st" ]] && { printf '%s\n' "$st"; return 0; }
  find /run/media/*/*/LinuxDCO/backups /run/media/*/*/backups "$HOME/garuda-backup" \
    -maxdepth 1 -name 'garuda-backup-*-last.tar.gz' -printf '%T@ %p\n' 2>/dev/null \
    | sort -n | tail -1 | cut -d' ' -f2-
}

install_theme_packages() {
  local pkg
  for pkg in plasma6-applets-window-title plasma6-applets-panel-colorizer plasma-applet-window-buttons; do
    if dnf -y install "$pkg" >/dev/null 2>&1; then
      ok "installed $pkg"
    else
      warn "ALT: $pkg is not packaged for Fedora; the applet will be removed"
    fi
  done
}

sanitize_appletsrc() {
  local file="$1" report="$2"
  python3 - "$file" "$report" <<'PY'
import re
import sys

path, report = sys.argv[1], sys.argv[2]
try:
    lines = open(path, encoding="utf-8").read().splitlines()
except OSError:
    raise SystemExit(0)

providers = {
    "org.kde.plasma.windowtitle": "plasma6-applets-window-title",
    "com.github.zren.panelcolorizer": "plasma6-applets-panel-colorizer",
    "org.kde.windowbuttons": "plasma-applet-window-buttons",
}

def installed(pkg):
    import subprocess
    return subprocess.run(["rpm", "-q", pkg], capture_output=True).returncode == 0

blocks, current = [], []
for line in lines:
    if line.startswith("[") and current:
        blocks.append(current)
        current = []
    current.append(line)
if current:
    blocks.append(current)

removed_ids = set()
removed_names = set()
for block in blocks:
    header = block[0].strip()
    match = re.match(r"^\[Containments\]\[(\d+)\]\[Applets\]\[(\d+)\]$", header)
    if not match:
        continue
    plugin = ""
    for line in block:
        if line.startswith("plugin="):
            plugin = line.split("=", 1)[1].strip()
    for needle, pkg in providers.items():
        if needle in plugin and not installed(pkg):
            removed_ids.add((match.group(1), match.group(2)))
            removed_names.add(plugin)

out = []
skip_applet = None
for block in blocks:
    header = block[0].strip()
    match = re.match(r"^\[Containments\]\[(\d+)\]\[Applets\]\[(\d+)\](?:\[|$)", header)
    if match and (match.group(1), match.group(2)) in removed_ids:
        for line in block:
            out.append("# " + line if line.strip() and not line.startswith("#") else line)
        continue
    out.append("\n".join(block))

if removed_names:
    with open(report, "w", encoding="utf-8") as fh:
        fh.write("# FedoraKDE UX diff (runtime)\n\n")
        for name in sorted(removed_names):
            fh.write("- removed applet: `%s` (provider not available)\n" % name)

open(path, "w", encoding="utf-8").write("\n".join(out) + "\n")
print("removed applets: %d" % len(removed_names))
PY
}

set_json_output_flags() {
  local file="$HOME_DIR/.config/kwinoutputconfig.json"
  [[ -f "$file" ]] || return 0
  python3 - "$file" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    data = json.load(open(path, encoding="utf-8"))
except (OSError, ValueError):
    raise SystemExit(0)
for output in data.get("outputs", []):
    output["allowDdcCi"] = False
    output["vrrPolicy"] = "Never"
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=4)
    fh.write("\n")
PY
}

apply_settings() {
  local font='Fira Sans,12,-1,5,400,0,0,0,0,0,0,0,0,0,0,1' fixed='FiraCode Nerd Font Mono,12,-1,5,400,0,0,0,0,0,0,0,0,0,0,1'
  as_user kwriteconfig6 --file kdeglobals --group KDE --key ColorScheme BreezeDark || true
  as_user kwriteconfig6 --file kdeglobals --group General --key font "$font" || true
  as_user kwriteconfig6 --file kdeglobals --group General --key menuFont "$font" || true
  as_user kwriteconfig6 --file kdeglobals --group General --key toolBarFont "$font" || true
  as_user kwriteconfig6 --file kdeglobals --group General --key smallestReadableFont "$font" || true
  as_user kwriteconfig6 --file kdeglobals --group General --key activeFont "$font" || true
  as_user kwriteconfig6 --file kdeglobals --group General --key fixed "$fixed" || true
  as_user kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled false || true
  as_user kwriteconfig6 --file kwinrc --group Plugins --key forceblurEnabled false || true
  as_user kwriteconfig6 --file kwinrc --group Plugins --key kwin4_effect_shapecornersEnabled false || true
  as_user gsettings set org.gnome.desktop.wm.preferences button-layout 'close,minimize,maximize:' 2>/dev/null || true
  if have plasma-apply-colorscheme; then
    as_user plasma-apply-colorscheme BreezeDark >/dev/null 2>&1 || true
  fi
  set_json_output_flags
  ok "KDE appearance applied (BreezeDark, Fira, blur off, DDC off)"
}

install_fonts() {
  local pkg found=""
  for pkg in fira-sans-fonts fira-code-fonts fira-mono-fonts; do
    if dnf -y install "$pkg" >/dev/null 2>&1; then found="$found $pkg"; fi
  done
  [[ -n "$found" ]] && ok "font packages:$found" || warn "ALT: no Fira packages found in the enabled repos"
  if have fc-cache; then
    as_user fc-cache -f >/dev/null 2>&1 || true
  fi
}

check_result() {
  local panels scheme
  panels="$(grep -cE '^[[:space:]]*plugin=org\.kde\.panel[[:space:]]*$' "$APPLETS" 2>/dev/null || echo 0)"
  scheme="$(kreadconfig6 --file "$HOME_DIR/.config/kdeglobals" --group KDE --key ColorScheme 2>/dev/null || true)"
  [[ "$panels" == 4 ]] && ok "panel layout: 4 panels" || warn "panel layout: $panels panels (expected 4)"
  [[ "$scheme" == BreezeDark ]] && ok "color scheme: BreezeDark" || warn "color scheme: '${scheme:-unset}'"
  if fc-match 'Fira Sans' 2>/dev/null | grep -qi 'Fira'; then
    ok "Fira Sans resolves"
  else
    warn "Fira Sans does not resolve yet"
  fi
}

main() {
  parse_args "$@"
  init_log ux
  TARBALL="$(resolve_tarball)"
  [[ -n "$TARBALL" && -f "$TARBALL" ]] || die "backup tarball not found; pass --tarball"
  state_set tarball-used "$TARBALL"
  log "restoring UX from $TARBALL"

  if [[ "$FEDORA_KDE_DRY_RUN" == 1 ]]; then
    log "dry-run: would extract config/, dotfiles/, .fonts/, wallpapers/ into $HOME_DIR"
    exit 0
  fi
  [[ ${EUID} -eq 0 ]] || die "run as root (user files are chowned afterwards)"
  require_cmd tar rsync

  TMP="$(mktemp -d)"
  local rootdir
  rootdir="$(tar -tzf "$TARBALL" | head -1 | cut -d/ -f1)"
  [[ -n "$rootdir" ]] || die "cannot read the tarball root"
  tar -xzf "$TARBALL" -C "$TMP" "$rootdir/config" "$rootdir/dotfiles" "$rootdir/.fonts" "$rootdir/wallpapers" 2>/dev/null || true
  local src="$TMP/$rootdir"

  install -d -o "$USER_NAME" -g "$USER_NAME" "$HOME_DIR/.config" "$HOME_DIR/.local/share/fonts" "$HOME_DIR/Pictures/wallpapers"

  if [[ -d "$src/config" ]]; then
    if [[ -d "$HOME_DIR/.config" && ! -d "$HOME_DIR/.config.fedora-prev" ]] \
       && [[ "$(du -sm "$HOME_DIR/.config" 2>/dev/null | cut -f1)" -lt 2048 ]]; then
      cp -a "$HOME_DIR/.config" "$HOME_DIR/.config.fedora-prev"
      ok "previous ~/.config backed up to ~/.config.fedora-prev"
    fi
    rsync -a "$src/config/" "$HOME_DIR/.config/"
    ok "restored ~/.config"
  fi

  if [[ -d "$src/dotfiles" ]]; then
    rsync -a --exclude '.zshrc' "$src/dotfiles/" "$HOME_DIR/"
    ok "restored dotfiles (shell rc is handled by the shell stage)"
  fi
  if [[ -d "$src/.fonts" ]]; then
    rsync -a "$src/.fonts/" "$HOME_DIR/.local/share/fonts/"
    ok "restored user fonts"
  fi
  if [[ -d "$src/wallpapers" ]]; then
    rsync -a "$src/wallpapers/" "$HOME_DIR/Pictures/wallpapers/"
    ok "restored wallpapers"
  fi
  chown -R "$USER_NAME:$USER_NAME" "$HOME_DIR/.config" "$HOME_DIR/.local/share/fonts" "$HOME_DIR/Pictures/wallpapers" 2>/dev/null || true
  [[ -f "$HOME_DIR/.zshrc" ]] && chown "$USER_NAME:$USER_NAME" "$HOME_DIR/.zshrc" || true

  install_theme_packages
  if [[ -f "$APPLETS" ]]; then
    REPORT="$FEDORA_KDE_LOG_DIR/UX-DIFF-runtime.md"
    mkdir -p "$FEDORA_KDE_LOG_DIR"
    sanitize_appletsrc "$APPLETS" "$REPORT"
    chown "$USER_NAME:$USER_NAME" "$APPLETS"
  else
    warn "no plasma-org.kde.plasma.desktop-appletsrc in the backup"
  fi

  install_fonts
  apply_settings
  check_result
  ok "UX restore complete"
}

main "$@"
