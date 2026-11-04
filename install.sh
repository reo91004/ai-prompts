#!/bin/sh
# Re-exec before parsing Bash functions; works with dash and macOS Bash 3.2.
[ -n "${BASH_VERSION:-}" ] || exec bash "$0" "$@"
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_PYTHON_VERSION=3.13
source "$ROOT/scripts/bootstrap_cli.sh"
source "$ROOT/scripts/humanizer.sh"
source "$ROOT/scripts/sequential_thinking.sh"
source "$ROOT/scripts/install_common.sh"
source "$ROOT/scripts/install_core.sh"
source "$ROOT/scripts/install_integrations.sh"
source "$ROOT/scripts/install_tooling.sh"
source "$ROOT/scripts/install_verify.sh"

main() {
  PROFILE=ponytail
  WITH_STATUSLINE=1
  KIT_STOP_HEADROOM=0
  action=install
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --integrations)
        [ "$#" -ge 2 ] || kit_die "--integrations requires none or ponytail"
        case "$2" in none|ponytail) PROFILE="$2" ;; *) kit_die "Unknown integration profile: $2" ;; esac
        shift 2 ;;
      --with-statusline) WITH_STATUSLINE=1; shift ;;
      --without-statusline) WITH_STATUSLINE=0; shift ;;
      --verify) [ "$action" = install ] || kit_die "Choose only one action"; action=verify; shift ;;
      --headroom-status) [ "$action" = install ] || kit_die "Choose only one action"; action=headroom_status; shift ;;
      --remove-headroom) [ "$action" = install ] || kit_die "Choose only one action"; action=headroom_remove; shift ;;
      --cleanup-backups) [ "$action" = install ] || kit_die "Choose only one action"; action=cleanup; shift ;;
      -h|--help)
        cat <<'HELP'
Usage: sh install.sh [--integrations ponytail|none] [--without-statusline] [--verify | --cleanup-backups]
Default: update Codex, Claude Code, OpenCode V2, core skills, Humanizer, Ponytail, MCP, Graphify, Headroom and statuslines.
All three CLIs are checked against their official latest release on every install. Global user skills are replaced after backup.
Python 3.13 and pinned uv are provisioned in the kit; no manual pip/system Python setup is needed.
Kit-owned Headroom services/MCP servers are stopped normally before installation and the service starts afterward.
Standard existing headroom-default deployments are backed up and adopted in place, retaining their profile and sessions.
Invalid managed tooling is backed up, cleared and rebuilt automatically; unrelated active jobs block replacement.
  --integrations none  Remove kit-owned Ponytail and legacy LazyCodex; keep MCP and tooling.
  --without-statusline Preserve existing statuslines and skip their verification.
  --with-statusline    Install both bundled statuslines (default; requires jq).
  --verify             Check source and installed files without installing or changing HOME.
  --headroom-status    Check the kit service, readiness, interpreter and Codex routing.
  --remove-headroom    Remove only the kit persistent service/provider; restore prior root settings.
  --cleanup-backups    Delete backup snapshots only; refuse while an install holds the lock.
  Remote Control: run sh codex-remote.sh enable after installation; pair separately.
Environment: UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS=1 leaves integrations untouched;
UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_TOOLING=1 leaves Graphify/Headroom untouched.
Explicit skips are recorded as skipped, not verified installations.
HELP
        return ;;
      *) kit_die "Unknown argument: $1" ;;
    esac
  done
  [ -z "${CODEX_HOME:-}" ] || [ "$CODEX_HOME" = "$HOME/.codex" ] ||
    kit_die "Custom CODEX_HOME is not supported; unset it before running this installer. No paths were changed."
  case "$action" in
    verify) verify_install; return ;;
    cleanup) cleanup_backups; return ;;
    headroom_status)
      "$HOME/.universal-research-agent-kit/tooling/uv-tools/headroom-ai/bin/python" -I -B "$ROOT/headroom/runtime.py" check
      return ;;
    headroom_remove)
      kit_init_state
      trap 'kit_release_lock' EXIT
      kit_backup_path "$HOME/.codex/config.toml" "headroom-remove/config.toml"
      "$HOME/.universal-research-agent-kit/tooling/uv-tools/headroom-ai/bin/python" -I -B "$ROOT/headroom/runtime.py" remove
      return ;;
  esac
  [ -z "${CLAUDE_CONFIG_DIR:-}" ] || kit_die "CLAUDE_CONFIG_DIR is not supported by this installer; unset it and rerun."
  kit_validate_home
  if [ "$WITH_STATUSLINE" -eq 1 ]; then
    command -v jq >/dev/null 2>&1 || kit_die "Claude statusline requires jq. Install jq (brew install jq or sudo apt install jq), or use --without-statusline."
  fi
  kit_maintenance_run opencode-idle || kit_die "OpenCode is in use; installation did not change this host."
  if [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_TOOLING:-0}" != 1 ]; then
    if [ -f "$HOME/.universal-research-agent-kit/headroom.json" ] ||
        [ -f "$HOME/.headroom/deploy/default/manifest.json" ] || ! kit_tooling_idle >/dev/null 2>&1; then
      if ! kit_maintenance_run inspect; then
        # The initial busy check is quiet because recognized Headroom can be
        # paused automatically. On refusal, show the remaining PID so the
        # user can identify an older installation or a different active job.
        kit_tooling_idle || true
        kit_die "Installation stopped before changing this host."
      fi
      KIT_STOP_HEADROOM=1
    fi
  fi
  kit_init_state
  kit_enable_rollback
  kit_maintenance_run opencode-idle || kit_die "OpenCode became active before installation."
  if [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_TOOLING:-0}" != 1 ]; then
    if [ "$KIT_STOP_HEADROOM" -eq 1 ]; then
      KIT_MAINTENANCE_RECORD="$KIT_BACKUP_DIR/headroom-maintenance.json"
      echo "Pausing kit Headroom for installation. MCP clients may need to reconnect afterward."
      kit_maintenance_run pause "$KIT_MAINTENANCE_RECORD" || kit_die "Headroom shutdown failed; environment replacement was not started."
    fi
    kit_tooling_idle || kit_die "Installation stopped after acquiring its lock."
    if [ "$KIT_STOP_HEADROOM" -eq 1 ]; then
      KIT_HEADROOM_PROFILE="$(kit_maintenance_run profile "$KIT_MAINTENANCE_RECORD")" || kit_die "Cannot identify the paused Headroom deployment."
      case "$KIT_HEADROOM_PROFILE" in default|research-agent-kit) ;; *) kit_die "Unexpected maintenance profile." ;; esac
      kit_backup_path "$HOME/.headroom/deploy/$KIT_HEADROOM_PROFILE" "maintenance/deployment"
      if [ "$(uname -s)" = Darwin ]; then
        kit_backup_path "$HOME/Library/LaunchAgents/com.headroom.$KIT_HEADROOM_PROFILE.plist" "maintenance/service.plist"
      else
        kit_backup_path "$HOME/.config/systemd/user/headroom-$KIT_HEADROOM_PROFILE.service" "maintenance/service.unit"
      fi
      kit_require_regular_or_absent "$KIT_STATE_ROOT/headroom.json"
      kit_backup_path "$KIT_STATE_ROOT/headroom.json" "maintenance/ownership"
    fi
  fi
  if [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS:-0}" != 1 ]; then
    bootstrap_cli
  fi
  if [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_TOOLING:-0}" != 1 ]; then
    prepare_tooling
    prepare_crucible
    kit_require_regular_or_absent "$HOME/.codex/config.toml"
    kit_backup_path "$HOME/.codex/config.toml" "legacy/config.toml"
    "$KIT_HEADROOM_PYTHON" -I -B "$ROOT/headroom/runtime.py" migrate-legacy || kit_die "Legacy Headroom migration failed."
    if [ -f "${KIT_MAINTENANCE_RECORD:-}" ]; then
      "$KIT_HEADROOM_PYTHON" -I -B "$ROOT/headroom/runtime.py" adopt-default "$KIT_MAINTENANCE_RECORD" || kit_die "Default Headroom adoption failed."
    fi
  fi
  if [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS:-0}" != 1 ]; then
    if [ "${KIT_TEST_FIXTURES_ONLY:-0}" = 1 ] && [ -n "${KIT_TEST_HUMANIZER_REPOSITORY:-}" ]; then
      prepare_humanizer --fixture-repository "$KIT_TEST_HUMANIZER_REPOSITORY"
    else
      prepare_humanizer
    fi
  fi
  kit_maintenance_run opencode-idle || kit_die "OpenCode became active before skill replacement."
  install_core
  kit_replace_managed_block "$HOME/.config/git/ignore" "$ROOT/global_research_agents.gitignore" git/ignore '# BEGIN UNIVERSAL RESEARCH AGENT KIT' '# END UNIVERSAL RESEARCH AGENT KIT'
  if [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS:-0}" = 1 ]; then
    kit_write_integrations_state "$PROFILE" skipped_env skipped_env skipped_env skipped_env skipped_env
  else
    install_integrations
  fi
  if [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_TOOLING:-0}" = 1 ]; then
    kit_write_tooling_state skipped_env skipped_env skipped_env skipped_env - - "$HOME/.universal-research-agent-kit/tooling/bin"
  else
    install_tooling
  fi
  if [ "$WITH_STATUSLINE" -eq 1 ]; then install_statusline; fi
  verify_install
  # Package manager removals cannot be rolled back by the file journal. Keep
  # the verified replacement installed if a manager reports a cleanup failure.
  trap 'kit_release_lock' EXIT
  if [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS:-0}" != 1 ]; then
    prune_old_ponytail_revisions
    cleanup_legacy_clis
  fi
  kit_cleanup_work
  echo "Done for the verified scope. Restart Claude Code, Codex and OpenCode sessions."
}
[ "${BASH_SOURCE[0]}" != "$0" ] || main "$@"
