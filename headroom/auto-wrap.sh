_universal_research_agent_kit_headroom_command() {
  local headroom_bin
  local python_headroom_bin

  if [ -x "$HOME/.universal-research-agent-kit/tooling/bin/headroom" ]; then
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
  _universal_research_agent_kit_headroom_command wrap claude -- "$@"
}

codex() {
  _universal_research_agent_kit_headroom_command wrap codex -- "$@"
}

claude_raw() {
  command claude "$@"
}

codex_raw() {
  command codex "$@"
}
