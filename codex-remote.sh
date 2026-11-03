#!/bin/sh
[ -n "${BASH_VERSION:-}" ] || exec bash "$0" "$@"
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install.sh"

usage() {
  cat <<'EOF'
Usage: sh codex-remote.sh [status|enable|pair|disable|repair]
  status   Inspect daemon, Remote Control and automatic startup (default).
  enable   Enable Remote Control and boot/login startup using installed tools.
  pair     Pair a device through the installed managed Codex.
  disable  Disable Remote Control and automatic startup; keep the local daemon.
  repair   Retry enable with bounded recovery of a verified unmanaged listener.

Install or update the kit separately with sh install.sh.
EOF
}

[ "$#" -le 1 ] || { usage >&2; exit 2; }
action="${1:-status}"
case "$action" in
  -h|--help|help) usage; exit 0 ;;
  status|enable|pair|disable|repair) ;;
  *) usage >&2; exit 2 ;;
esac
kit_validate_home
[ -z "${CODEX_HOME:-}" ] || [ "$CODEX_HOME" = "$HOME/.codex" ] ||
  kit_die "Custom CODEX_HOME is not supported by this kit."

case "$action" in
  status) show_codex_remote ;;
  pair) pair_codex_remote ;;
  enable|disable|repair)
    codex_remote_capability >/dev/null || kit_die "Managed Remote Control is unavailable. Run sh install.sh first."
    KIT_HEADROOM_PYTHON="${KIT_HEADROOM_PYTHON:-$HOME/.universal-research-agent-kit/tooling/uv-tools/headroom-ai/bin/python}"
    [ -x "$KIT_HEADROOM_PYTHON" ] || kit_die "Managed Python is unavailable. Run sh install.sh first."
    kit_init_state
    trap 'kit_release_lock' EXIT
    case "$action" in
      enable) enable_codex_remote 0 ;;
      repair) enable_codex_remote 1 ;;
      disable) disable_codex_remote ;;
    esac
    ;;
esac
