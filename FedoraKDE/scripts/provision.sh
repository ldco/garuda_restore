#!/usr/bin/env bash
# Stage: provision - turn a fresh Fedora 45 KDE install into this machine.
# Runs as root on the new system.  Every stage is idempotent (state markers).
set -Eeuo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"
export FEDORA_KDE_ROOT="${FEDORA_KDE_ROOT:-$(cd -- "$HERE/.." && pwd)}"

STAGES=(repos base nvidia asus security-baseline snapshots ux apps shell finalize)
ONLY=""
FROM=""
SKIP_APPS=0
WITH_OPTIONAL=0
AUTO=0
FORCE=0
SWAPFILE_GB="${FEDORA_KDE_SWAPFILE_GB:-32}"

usage() {
  cat <<'EOF'
provision [options]

  --yes                non-interactive (no confirmation prompts)
  --auto               first-boot mode: stop at a reboot requirement instead
                       of prompting (used by fedora-kde-provision.service)
  --with-optional      also apply the opt-in hardening (fapolicyd, usbguard, AIDE)
  --skip-apps          do not run the app package map
  --only STAGE         run a single stage
  --from STAGE         start from a stage
  --force              re-run stages even if their marker exists
  --dry-run            print the plan
EOF
}

parse_args() {
  while (( $# )); do
    case "$1" in
      --yes) FEDORA_KDE_ASSUME_YES=1; export FEDORA_KDE_ASSUME_YES ;;
      --auto) AUTO=1; FEDORA_KDE_ASSUME_YES=1; export FEDORA_KDE_ASSUME_YES ;;
      --with-optional) WITH_OPTIONAL=1 ;;
      --skip-apps) SKIP_APPS=1 ;;
      --only) ONLY="${2:?--only needs a value}"; shift ;;
      --from) FROM="${2:?--from needs a value}"; shift ;;
      --force) FORCE=1 ;;
      --dry-run) FEDORA_KDE_DRY_RUN=1; export FEDORA_KDE_DRY_RUN ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown argument: $1" ;;
    esac
    shift
  done
}

stage_repos() {
  local rel
  rel="$(rpm -E %fedora)"
  dnf_install dnf-plugins-core
  if ! rpm -q rpmfusion-free-release >/dev/null 2>&1; then
    dnf -y install \
      "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${rel}.noarch.rpm" \
      "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${rel}.noarch.rpm"
  fi
  if ! rpm -q terra-release >/dev/null 2>&1; then
    dnf -y install --nogpgcheck \
      --repofrompath "terra,https://repos.fyralabs.com/terra${rel}" \
      terra-release terra-gpg-keys
  fi
  if ! dnf repolist --enabled 2>/dev/null | grep -q 'kylegospo/grub-btrfs'; then
    dnf -y copr enable kylegospo/grub-btrfs
  fi
  dnf -y makecache
  ok "repositories ready"
}

stage_base() {
  local kver
  kver="$(uname -r)"
  dnf_install akmods kmodtool mokutil openssl zsh git curl wget jq rsync \
    btop fastfetch ripgrep fd-find bat fzf zoxide flatpak plasma-firewall \
    switcheroo-control glx-utils tpm2-tools tpm2-tss snapper btrfs-assistant \
    libdnf5-plugin-actions grub2-tools-extra policycoreutils-python-utils
  if ! dnf -y install "kernel-devel-${kver}"; then
    warn "kernel-devel-${kver} not available; installing the latest kernel-devel"
    dnf_install kernel-devel
    warn "akmod-nvidia will build for the latest kernel after the next reboot"
  fi

  if [[ "$SWAPFILE_GB" != 0 ]] && ! swapon --show=NAME --noheadings | grep -qx '/swap/swapfile'; then
    log "creating a ${SWAPFILE_GB} GiB btrfs swapfile for OOM headroom"
    btrfs subvolume show /swap >/dev/null 2>&1 || btrfs subvolume create /swap
    if [[ ! -f /swap/swapfile ]]; then
      btrfs filesystem mkswapfile --size "${SWAPFILE_GB}g" /swap/swapfile
    fi
    swapon /swap/swapfile
    append_line_once /etc/fstab '/swap/swapfile none swap defaults 0 0'
  fi
  systemctl set-default graphical.target
  ok "base packages ready"
}

stage_nvidia() {
  # shellcheck disable=SC2310
  "$HERE/nvidia.sh" ${AUTO:+--auto} || return $?
}

stage_asus() {
  "$HERE/asus.sh"
}

stage_security() {
  "$HERE/security.sh" baseline
  if [[ "$WITH_OPTIONAL" == 1 ]]; then
    "$HERE/security.sh" optional
  fi
}

stage_snapshots() {
  "$HERE/snapshots.sh"
}

stage_ux() {
  "$HERE/restore-ux.sh"
}

stage_apps() {
  if [[ "$SKIP_APPS" == 1 ]]; then
    warn "app installation skipped (--skip-apps)"
    return 0
  fi
  "$HERE/apps.sh"
}

stage_shell() {
  local tarball home rc
  tarball="$(state_get tarball-used)"
  home="$(user_home)"
  rc="$home/.zshrc"
  if [[ -n "$tarball" && -f "$tarball" ]]; then
    tar -xzf "$tarball" -C /tmp --wildcards '*/.zshrc' 2>/dev/null || true
    local src
    src="$(find /tmp -maxdepth 2 -name .zshrc -newermt '-10 minutes' 2>/dev/null | head -1)"
    if [[ -n "$src" ]]; then
      cp "$src" "$rc"
      rm -f "$src"
    fi
  fi
  if [[ -f "$rc" ]]; then
    python3 - "$rc" <<'PY'
import re
import sys

path = sys.argv[1]
drop = re.compile(r'^\s*alias\s+(fixpacman|grubup|pacman|paru|yay|update-grub)\s*=')
lines = open(path, encoding="utf-8").read().splitlines()
out = [ln for ln in lines if not drop.match(ln)]
if not any('grub2-mkconfig' in ln for ln in out):
    out.append("alias grubup='sudo grub2-mkconfig -o /boot/grub2/grub.cfg'")
if not any('dnf upgrade' in ln for ln in out):
    out.append("alias update='sudo dnf upgrade --refresh'")
open(path, "w", encoding="utf-8").write("\n".join(out) + "\n")
PY
    chown "$(target_user):$(target_user)" "$rc"
    ok "shell config restored and pacman aliases rewritten"
  else
    warn "no .zshrc found in the backup; leaving the shell default"
  fi

  if [[ ! -d "$home/.oh-my-zsh" ]]; then
    as_user git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$home/.oh-my-zsh" || \
      warn "oh-my-zsh clone failed"
  fi
  local plugin
  for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
    if [[ ! -d "$home/.oh-my-zsh/custom/plugins/$plugin" ]]; then
      as_user git clone --depth=1 "https://github.com/zsh-users/${plugin}.git" \
        "$home/.oh-my-zsh/custom/plugins/$plugin" || warn "plugin $plugin clone failed"
    fi
  done
  chsh -s /usr/bin/zsh "$(target_user)" || warn "chsh failed"
}

stage_finalize() {
  dracut -f --regenerate-all
  if [[ -f /etc/snapper/configs/root ]]; then
    snapper -c root create -d "provisioned" --cleanup-algorithm number || warn "snapshot failed"
  fi
  state_mark provisioned
  cat <<'EOF'

Provisioning finished. Remaining manual steps:
  1. reboot
  2. in the blue MOK screen: Enroll MOK -> Continue -> enter the password
     you set for mokutil -> Reboot
  3. after login:
       sudo /root/FedoraKDE/install.sh tpm2-enroll --yes
       sudo /root/FedoraKDE/install.sh verify --expect-tpm2
EOF
}

run_stage() {
  local stage="$1"
  if [[ "$FORCE" != 1 ]] && state_check "$stage"; then
    ok "stage '$stage' already done (marker present)"
    return 0
  fi
  log "--- stage: $stage ---"
  if [[ "$FEDORA_KDE_DRY_RUN" == 1 ]]; then
    log "dry-run: would run stage $stage"
    return 0
  fi
  case "$stage" in
    repos) stage_repos ;;
    base) stage_base ;;
    nvidia)
      if ! stage_nvidia; then
        warn "stage nvidia requires a reboot (MOK enrollment pending)"
        resume_point mok
        exit 3
      fi
      ;;
    asus) stage_asus ;;
    security-baseline) stage_security ;;
    snapshots) stage_snapshots ;;
    ux) stage_ux ;;
    apps) stage_apps ;;
    shell) stage_shell ;;
    finalize) stage_finalize ;;
    *) die "unknown stage: $stage" ;;
  esac
  state_mark "$stage"
  ok "stage '$stage' done"
}

main() {
  parse_args "$@"
  init_log provision
  [[ "$FEDORA_KDE_DRY_RUN" == 1 ]] || require_root

  local stage started=0
  for stage in "${STAGES[@]}"; do
    if [[ -n "$ONLY" && "$stage" != "$ONLY" ]]; then continue; fi
    if [[ -n "$FROM" && "$started" == 0 ]]; then
      if [[ "$stage" != "$FROM" ]]; then continue; fi
      started=1
    fi
    run_stage "$stage"
  done
}

main "$@"
