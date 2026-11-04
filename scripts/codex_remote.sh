#!/usr/bin/env bash
# Sourced by codex-remote.sh after the shared helpers.

codex_remote_capability() {
  local binary
  binary="$(managed_codex)" || { echo "Managed standalone Codex is unavailable." >&2; return 1; }
  "$binary" --version &&
    "$binary" app-server daemon version --help >/dev/null &&
    "$binary" app-server daemon bootstrap --help >/dev/null &&
    "$binary" remote-control start --help >/dev/null
}

codex_startup_command() {
  "${KIT_HEADROOM_PYTHON:-$HOME/.universal-research-agent-kit/tooling/uv-tools/headroom-ai/bin/python}" \
    -I -B "$ROOT/scripts/codex_startup.py" "$@"
}

backup_codex_startup() {
  local startup_path
  startup_path="$(codex_startup_command check "$1")" || return 1
  KIT_REMOTE_BACKUP_INDEX=$((${KIT_REMOTE_BACKUP_INDEX:-0} + 1))
  kit_backup_path "$startup_path" "remote-control/startup-$KIT_REMOTE_BACKUP_INDEX"
}

enable_codex_remote() {
  local binary action=repair
  [ "${1:-1}" = 1 ] || action=enable
  kit_require_regular_or_absent "$KIT_STATE_ROOT/codex-remote-control.state"
  codex_remote_capability || kit_die "Installed Codex does not support the required managed Remote Control commands."
  binary="$(managed_codex)"
  backup_codex_startup "$binary" || return 1
  # The helper keeps native JSON (including environment IDs) out of kit state.
  "${KIT_HEADROOM_PYTHON:-$HOME/.universal-research-agent-kit/tooling/uv-tools/headroom-ai/bin/python}" \
    -I -B "$ROOT/scripts/codex_remote.py" "$action" "$binary" || return 1
  codex_startup_command install "$binary" || return 1
  printf '%s\n' 'enabled=1' > "$KIT_STATE_ROOT/codex-remote-control.state"
  echo "Pair separately on this host: sh codex-remote.sh pair"
}

disable_codex_remote() {
  local binary
  binary="$(managed_codex)" || kit_die "No managed Codex installation; no remote host was changed."
  kit_require_regular_or_absent "$KIT_STATE_ROOT/codex-remote-control.state"
  backup_codex_startup "$binary" || return 1
  codex_startup_command remove "$binary" || return 1
  "$binary" app-server daemon disable-remote-control >/dev/null || kit_die "Could not disable Codex Remote Control."
  printf '%s\n' 'enabled=0' > "$KIT_STATE_ROOT/codex-remote-control.state"
  echo "Codex Remote Control disabled on this host. Local Codex/Headroom remain available."
}

show_codex_remote() {
  local binary python failed=0
  if [ -f "$HOME/.universal-research-agent-kit/codex-remote-control.state" ] &&
      grep -Fqx 'enabled=1' "$HOME/.universal-research-agent-kit/codex-remote-control.state"; then
    echo "Kit Remote Control setup: enabled."
  else
    echo "No completed Remote Control setup is recorded, or the kit setting is disabled."
    echo "The native daemon may still be enabled after a partial setup failure."
    echo "Complete/retry setup: sh codex-remote.sh enable"
    failed=1
  fi
  python="${KIT_HEADROOM_PYTHON:-$HOME/.universal-research-agent-kit/tooling/uv-tools/headroom-ai/bin/python}"
  if ! binary="$(managed_codex)"; then
    echo "Managed Codex: unavailable. Run sh install.sh."
    echo "Daemon, Remote Control preference and automatic startup: not inspected."
    return 1
  fi
  if [ ! -x "$python" ]; then
    echo "Managed Python: unavailable. Run sh install.sh."
    echo "Daemon, Remote Control preference and automatic startup: not inspected."
    return 1
  fi
  "$python" -I -B "$ROOT/scripts/codex_remote.py" status "$binary" || failed=1
  if ! codex_startup_command verify "$binary"; then
    echo "Codex automatic startup: not verified."
    failed=1
  fi
  return "$failed"
}

pair_codex_remote() {
  local binary
  binary="$(managed_codex)" || kit_die "No managed Codex installation. Run sh install.sh first."
  "$binary" remote-control pair
}
