#!/usr/bin/env bash
# Stage: snapshots - snapper + DNF5 pre/post snapshots + grub-btrfs.
set -Eeuo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

CFG=/etc/snapper/configs/root

usage() { echo "snapshots [--dry-run]"; }

parse_args() {
  while (( $# )); do
    case "$1" in
      --dry-run) FEDORA_KDE_DRY_RUN=1; export FEDORA_KDE_DRY_RUN ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown argument: $1" ;;
    esac
    shift
  done
}

set_cfg() {
  local key="$1" value="$2"
  if grep -qE "^${key}=" "$CFG"; then
    sed -i -E "s|^${key}=.*|${key}=\"${value}\"|" "$CFG"
  else
    printf '%s="%s"\n' "$key" "$value" >>"$CFG"
  fi
}

write_actions_hook() {
  local dir=/etc/dnf/libdnf5-plugins/actions.d
  mkdir -p "$dir"
  cat >"$dir/snapper.actions" <<'TXT'
# Pre/post btrfs snapshots around every DNF5 transaction (official recipe).
pre_transaction::::/usr/bin/sh -c echo\ "tmp.cmd=$(ps\ -o\ command\ --no-headers\ -p\ '${pid}')"
pre_transaction::::/usr/bin/sh -c echo\ "tmp.snapper_pre=$(snapper\ -c\ root\ create\ -c\ number\ -t\ pre\ -p\ -d\ '${tmp.cmd}')"
post_transaction::::/usr/bin/sh -c [\ -n\ "${tmp.snapper_pre}"\ ]\ \&\&\ snapper\ -c\ root\ create\ -t\ post\ --pre-number\ "${tmp.snapper_pre}"\ -d\ "${tmp.cmd}"
TXT
  ok "DNF5 snapshot hook written"
}

main() {
  parse_args "$@"
  init_log snapshots
  [[ "$FEDORA_KDE_DRY_RUN" == 1 ]] && { log "dry-run: would configure snapper + grub-btrfs"; exit 0; }
  require_root

  dnf_install snapper btrfs-assistant libdnf5-plugin-actions
  if ! dnf_install grub-btrfs; then
    warn "ALT: grub-btrfs not available; enable the kylegospo COPR in the repos stage"
  fi

  if [[ ! -f "$CFG" ]]; then
    snapper -c root create-config /
  else
    ok "snapper root config already exists"
  fi
  [[ -f "$CFG" ]] || die "snapper root config was not created"

  set_cfg TIMELINE_MIN_AGE 1800
  set_cfg TIMELINE_LIMIT_HOURLY 5
  set_cfg TIMELINE_LIMIT_DAILY 7
  set_cfg TIMELINE_LIMIT_WEEKLY 4
  set_cfg TIMELINE_LIMIT_MONTHLY 3
  set_cfg TIMELINE_LIMIT_YEARLY 1
  set_cfg NUMBER_LIMIT 50
  set_cfg NUMBER_LIMIT_IMPORTANT 10
  ok "snapper limits configured"

  write_actions_hook

  # /.snapshots is a btrfs subvolume, not a mount: fix SELinux labels.
  if [[ -d /.snapshots ]]; then
    restorecon -Rv /.snapshots >/dev/null 2>&1 || true
  fi

  # grub-btrfs: the packaged .path unit binds to a .snapshots.mount that
  # does not exist for a nested subvolume; override it (noratek caveat).
  if [[ -f /usr/lib/systemd/system/grub-btrfs.path || -f /etc/systemd/system/grub-btrfs.path ]]; then
    mkdir -p /etc/systemd/system/grub-btrfs.path.d
    cat >/etc/systemd/system/grub-btrfs.path.d/override.conf <<'TXT'
[Path]
PathChanged=
PathModified=/.snapshots
TXT
    ok "grub-btrfs.path override written"
  fi
  systemctl daemon-reload
  systemctl enable --now grub-btrfsd.service 2>/dev/null || warn "grub-btrfsd.service not available"
  systemctl enable --now grub-btrfs.path 2>/dev/null || true

  systemctl enable --now snapper-timeline.timer snapper-cleanup.timer 2>/dev/null || \
    warn "snapper timers not enabled"

  if have grub2-mkconfig; then
    grub_regenerate
  fi

  if [[ "$(snapper -c root list 2>/dev/null | wc -l)" -lt 3 ]]; then
    snapper -c root create -d "post-install" --cleanup-algorithm number || warn "snapshot failed"
  fi
  ok "snapshots ready"
}

main "$@"
