_universal_research_agent_kit_headroom_command() {
  local headroom_bin
  local python_headroom_bin

  if [ -d "$HOME/.universal-research-agent-kit/.lock" ]; then
    echo "The kit installer is running. Wait for it to finish before starting a new Headroom session." >&2
    return 1
  fi
  if [ -x "$HOME/.universal-research-agent-kit/tooling/bin/headroom" ]; then
    PATH="$HOME/.universal-research-agent-kit/tooling/bin:$PATH" \
      command "$HOME/.universal-research-agent-kit/tooling/bin/headroom" "$@"
    return
  fi
  headroom_bin="$(command -v headroom 2>/dev/null || true)"
  if [ -n "$headroom_bin" ]; then
    command "$headroom_bin" "$@"
    return
  fi
  if [ -x "$HOME/.local/bin/headroom" ]; then
    command "$HOME/.local/bin/headroom" "$@"
    return
  fi
  if command -v python3 >/dev/null 2>&1; then
    python_headroom_bin="$(python3 -c 'import site; print(site.getuserbase() + "/bin/headroom")' 2>/dev/null || true)"
    if [ -x "$python_headroom_bin" ]; then
      command "$python_headroom_bin" "$@"
      return
    fi
  fi
  echo "headroom is unavailable; install it before using claude or codex wrappers." >&2
  return 127
}

claude() {
  local KIT_COMMAND_KIND
  if _universal_research_agent_kit_direct_command claude "$@"; then
    (
      if [ "$KIT_COMMAND_KIND" = remote ]; then
        unset ANTHROPIC_BASE_URL
        if [ -x "$HOME/.universal-research-agent-kit/tooling/uv-tools/headroom-ai/bin/python" ]; then
          _universal_research_agent_kit_runtime claude-direct-check || exit
        fi
      fi
      _universal_research_agent_kit_cli claude "$@"
    )
  elif [ -f "$HOME/.universal-research-agent-kit/headroom.json" ]; then
    _universal_research_agent_kit_runtime launch claude "$@"
  else
    _universal_research_agent_kit_headroom_command wrap claude -- "$@"
  fi
}

codex() {
  local KIT_COMMAND_KIND
  if _universal_research_agent_kit_direct_command codex "$@"; then
    if [ "$KIT_COMMAND_KIND" = remote ]; then
      _universal_research_agent_kit_codex_lifecycle "$@"
    else
      _universal_research_agent_kit_cli codex "$@"
    fi
  elif [ -f "$HOME/.universal-research-agent-kit/headroom.json" ]; then
    _universal_research_agent_kit_runtime launch codex "$@"
  else
    _universal_research_agent_kit_headroom_command wrap codex -- "$@"
  fi
}

_universal_research_agent_kit_cli() {
  local tool="$1" binary="$HOME/.universal-research-agent-kit/cli/bin/$1"
  shift
  if [ -e "$binary" ] || [ -L "$binary" ]; then
    command "$binary" "$@"
  else
    command "$tool" "$@"
  fi
}

_universal_research_agent_kit_runtime() {
  command "$HOME/.universal-research-agent-kit/tooling/uv-tools/headroom-ai/bin/python" \
    -I -B "$HOME/.config/headroom/runtime.py" "$@"
}

# Inspect tokens, never the joined command line: a prompt/option value may
# contain the words remote-control or --rc without requesting that mode.
_universal_research_agent_kit_direct_command() {
  local tool="$1" skip=0 positional=0 arg
  shift
  KIT_COMMAND_KIND=admin
  for arg in "$@"; do
    if [ "$skip" -eq 1 ]; then skip=0; continue; fi
    case "$arg" in
      --) return 1 ;;
      --help|--version|-h) [ "$positional" -eq 0 ] && return 0 ;;
    esac
    if [ "$tool" = codex ]; then
      case "$arg" in
        -c|--config|-p|--profile|-C|--cd|-m|--model|-s|--sandbox|-a|--ask-for-approval|-i|--image|--enable|--disable|--add-dir|--remote) skip=1; continue ;;
        -V) return 0 ;;
        -*) continue ;;
        remote-control|app-server) KIT_COMMAND_KIND=remote; return 0 ;;
        login|logout|mcp|mcp-server|plugin|completion|update|features) return 0 ;;
        *) return 1 ;;
      esac
    else
      case "$arg" in
        --remote-control|--remote-control=*|--rc|--rc=*) KIT_COMMAND_KIND=remote; return 0 ;;
        --model|--agent|--agents|--settings|--setting-sources|--permission-mode|--effort|--system-prompt|--append-system-prompt|--output-format|--input-format|--json-schema|--max-budget-usd|--fallback-model|--session-id|--name|-n|--debug-file|--remote-control-session-name-prefix) skip=1; continue ;;
        -v) [ "$positional" -eq 0 ] && return 0 ;;
        -*) continue ;;
        remote-control) [ "$positional" -eq 0 ] && { KIT_COMMAND_KIND=remote; return 0; } ;;
        auth|mcp|plugin|doctor|install|update|upgrade) [ "$positional" -eq 0 ] && return 0 ;;
      esac
      positional=1
    fi
  done
  return 1
}

_universal_research_agent_kit_codex_lifecycle() {
  local base="${CODEX_HOME:-$HOME/.codex}/packages/standalone/current"
  if [ -x "$base/bin/codex" ]; then
    command "$base/bin/codex" "$@"
  elif [ -x "$base/codex" ]; then
    command "$base/codex" "$@"
  else
    _universal_research_agent_kit_cli codex "$@"
  fi
}

claude_raw() {
  _universal_research_agent_kit_cli claude "$@"
}

codex_raw() {
  _universal_research_agent_kit_cli codex "$@"
}

# Raw means only shell-dispatch bypass. Codex still reads its persistent provider.
claude_rc() {
  claude remote-control "$@"
}
