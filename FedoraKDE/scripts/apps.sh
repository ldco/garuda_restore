#!/usr/bin/env bash
# Stage: apps - install the user-facing application set from packages/.
# Never aborts the provisioning on a single package; writes a report.
set -Eeuo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"
export FEDORA_KDE_ROOT="${FEDORA_KDE_ROOT:-$(cd -- "$HERE/.." && pwd)}"

MAP="$FEDORA_KDE_ROOT/packages/arch-to-fedora.tsv"
STRICT=0
REPORT=""

usage() {
  cat <<'EOF'
apps [options]

  --strict-apps   exit non-zero if any package ended up FAIL
  --map PATH      alternative arch-to-fedora.tsv
  --dry-run       list the plan
EOF
}

parse_args() {
  while (( $# )); do
    case "$1" in
      --strict-apps) STRICT=1 ;;
      --map) MAP="${2:?--map needs a value}"; shift ;;
      --dry-run) FEDORA_KDE_DRY_RUN=1; export FEDORA_KDE_DRY_RUN ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown argument: $1" ;;
    esac
    shift
  done
}

record() {
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "${5:-}" >>"$REPORT"
}

resolve_native() {
  local arch="$1" want="$2" alt=""
  if rpm -q "$want" >/dev/null 2>&1; then
    record "$arch" "$want" native OK "already present"
    return 0
  fi
  if dnf -y install --setopt=install_weak_deps=False "$want" >/dev/null 2>&1; then
    record "$arch" "$want" native OK ""
    return 0
  fi
  alt="$(dnf -q search "$want" 2>/dev/null \
    | grep -oE '^[A-Za-z0-9_.+-]+\.(x86_64|noarch|i686)' \
    | sed -E 's/\.(x86_64|noarch|i686)$//' | head -1 || true)"
  if [[ -n "$alt" && "$alt" != "$want" ]] && dnf -y install --setopt=install_weak_deps=False "$alt" >/dev/null 2>&1; then
    record "$arch" "$alt" native ALT "searched from $want"
    return 0
  fi
  record "$arch" "$want" native FAIL "not packaged"
  return 0
}

ensure_flathub() {
  if ! flatpak remotes --columns=name 2>/dev/null | grep -qx flathub; then
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  fi
}

install_flatpak() {
  local arch="$1" app="$2"
  ensure_flathub
  if flatpak install -y --noninteractive flathub "$app" >/dev/null 2>&1; then
    record "$arch" "$app" flatpak FLATPAK ""
  else
    record "$arch" "$app" flatpak FAIL "flathub install failed"
  fi
}

main() {
  parse_args "$@"
  init_log apps
  [[ -f "$MAP" ]] || die "package map not found: $MAP"
  REPORT="$FEDORA_KDE_ROOT/packages/report-$(date +%Y%m%d-%H%M%S).tsv"
  [[ "$FEDORA_KDE_DRY_RUN" == 1 ]] && { log "dry-run: would install $(( $(grep -vc '^#' "$MAP") )) mapped apps"; exit 0; }
  require_root
  dnf_install flatpak
  printf 'arch\tfedora\tmode\tstatus\tnote\n' >"$REPORT"

  local -a n_arch=() n_pkg=()
  local arch fedora mode note i j
  while IFS=$'\t' read -r arch fedora mode note; do
    [[ -z "$arch" || "$arch" == \#* ]] && continue
    case "$mode" in
      native) n_arch+=("$arch"); n_pkg+=("$fedora") ;;
      flatpak) install_flatpak "$arch" "$fedora" ;;
      manual) record "$arch" "$fedora" manual MANUAL "${note:-needs manual install}" ;;
      drop) : ;;
      *) warn "unknown mode '$mode' for $arch" ;;
    esac
  done <"$MAP"

  i=0
  while (( i < ${#n_pkg[@]} )); do
    local -a chunk=()
    for (( j = i; j < i + 20 && j < ${#n_pkg[@]}; j++ )); do
      chunk+=("${n_pkg[$j]}")
    done
    if dnf -y install --setopt=install_weak_deps=False "${chunk[@]}" >/dev/null 2>&1; then
      for (( j = i; j < i + 20 && j < ${#n_pkg[@]}; j++ )); do
        record "${n_arch[$j]}" "${n_pkg[$j]}" native OK ""
      done
    else
      for (( j = i; j < i + 20 && j < ${#n_pkg[@]}; j++ )); do
        resolve_native "${n_arch[$j]}" "${n_pkg[$j]}"
      done
    fi
    i=$(( i + 20 ))
  done

  cp "$REPORT" "$FEDORA_KDE_LOG_DIR/" 2>/dev/null || true
  local fails manuals
  fails="$(awk -F'\t' '$4=="FAIL"' "$REPORT" | wc -l)"
  manuals="$(awk -F'\t' '$4=="MANUAL"{print $1" -> "$2}' "$REPORT")"
  ok "report: $REPORT"
  if [[ -n "$manuals" ]]; then
    warn "MANUAL packages (install yourself):"
    printf '%s\n' "$manuals" >&2
  fi
  if (( fails > 0 )); then
    warn "$fails package(s) FAILED"
    if (( STRICT )); then die "strict mode: package failures are fatal"; fi
  else
    ok "no package failures"
  fi
}

main "$@"
