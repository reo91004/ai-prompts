#!/usr/bin/env bash
# Sourced by install.sh.

tool_version_matches() {
  local command_name="$1"
  local expected_version="$2"
  local candidate
  local output

  output="$("$command_name" --version 2>&1)" || return 1
  while IFS= read -r candidate; do
    [ "$candidate" = "$expected_version" ] && return 0
  done <<EOF
$(printf '%s\n' "$output" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z]+)*' || true)
EOF
  return 1
}


# Graphify rewrites every installed skill whenever it runs, even for --version,
# so these paths are backed up before the first invocation.
backup_graphify_skills() {
[ "${GRAPHIFY_SKILLS_BACKED_UP:-0}" -eq 0 ] || return 0
GRAPHIFY_CLAUDE_PROMPT="$HOME/.claude/CLAUDE.md"
GRAPHIFY_CLAUDE_SKILL="$HOME/.claude/skills/graphify"
GRAPHIFY_CODEX_SKILL="$HOME/.codex/skills/graphify"
for graphify_parent in "$HOME/.claude" "$HOME/.claude/skills" "$HOME/.codex" "$HOME/.codex/skills"; do
  [ ! -L "$graphify_parent" ] || kit_die "Refusing a symlinked Graphify parent: $graphify_parent"
  if [ -e "$graphify_parent" ] && [ ! -d "$graphify_parent" ]; then
    kit_die "Graphify parent is not a directory: $graphify_parent"
  fi
done
kit_require_regular_or_absent "$GRAPHIFY_CLAUDE_PROMPT"
for graphify_skill in "$GRAPHIFY_CLAUDE_SKILL" "$GRAPHIFY_CODEX_SKILL"; do
  [ ! -L "$graphify_skill" ] || kit_die "Refusing a symlinked Graphify skill: $graphify_skill"
  if [ -e "$graphify_skill" ] && [ ! -d "$graphify_skill" ]; then
    kit_die "Graphify skill path is not a directory: $graphify_skill"
  fi
done
kit_backup_path "$GRAPHIFY_CLAUDE_PROMPT" "tooling/graphify-claude-prompt"
kit_backup_path "$GRAPHIFY_CLAUDE_SKILL" "tooling/graphify-claude-skill"
kit_backup_path "$GRAPHIFY_CODEX_SKILL" "tooling/graphify-codex-skill"

GRAPHIFY_EXISTING_INDEX=0
for graphify_existing_skill in \
  "$HOME/.config/opencode/skills/graphify" \
  "$HOME/.config/kilo/skills/graphify" \
  "$HOME/.aider/graphify" \
  "$HOME/.copilot/skills/graphify" \
  "$HOME/.openclaw/skills/graphify" \
  "$HOME/.factory/skills/graphify" \
  "$HOME/.trae/skills/graphify" \
  "$HOME/.trae-cn/skills/graphify" \
  "$HOME/.hermes/skills/graphify" \
  "$HOME/.gemini/config/skills/graphify" \
  "$HOME/.kiro/skills/graphify" \
  "$HOME/.pi/agent/skills/graphify" \
  "$HOME/.codebuddy/skills/graphify" \
  "$HOME/.agents/skills/graphify" \
  "$HOME/.config/agents/skills/graphify" \
  "$HOME/.config/devin/skills/graphify" \
  "$HOME/.kimi/skills/graphify"; do
  [ "$graphify_existing_skill" = "$GRAPHIFY_CLAUDE_SKILL" ] && continue
  [ "$graphify_existing_skill" = "$GRAPHIFY_CODEX_SKILL" ] && continue
  # Linked skills are safe only when their contents are already backed up above.
  if [ -L "$graphify_existing_skill" ] &&
      [ ! "$graphify_existing_skill" -ef "$GRAPHIFY_CLAUDE_SKILL" ] &&
      [ ! "$graphify_existing_skill" -ef "$GRAPHIFY_CODEX_SKILL" ]; then
    kit_die "Refusing a symlinked Graphify skill: $graphify_existing_skill"
  fi
  if [ -e "$graphify_existing_skill" ] && [ ! -d "$graphify_existing_skill" ]; then
    kit_die "Graphify skill path is not a directory: $graphify_existing_skill"
  fi
  if [ -e "$graphify_existing_skill" ]; then
    kit_backup_path "$graphify_existing_skill" "tooling/graphify-existing-$GRAPHIFY_EXISTING_INDEX"
    GRAPHIFY_EXISTING_INDEX=$((GRAPHIFY_EXISTING_INDEX + 1))
  fi
done
GRAPHIFY_SKILLS_BACKED_UP=1
}

prepare_tooling() {
[ "${KIT_TOOLING_PREPARED:-0}" -eq 0 ] || return 0
backup_graphify_skills
GRAPHIFY_VERSION="$(latest_pypi_version graphifyy)"
HEADROOM_VERSION="$(latest_pypi_version headroom-ai)"
KIT_UV_VERSION="$(latest_pypi_version uv)"
GRAPHIFY_PACKAGE="graphifyy==$GRAPHIFY_VERSION"
HEADROOM_PACKAGE="headroom-ai[all]==$HEADROOM_VERSION"
TOOL_ROOT="$KIT_STATE_ROOT/tooling"
TOOL_BIN_DIR="$TOOL_ROOT/bin"
TOOL_UV_DIR="$TOOL_ROOT/uv-tools"
TOOL_ROOT_PREPARED=0
KIT_UV_BIN="$TOOL_ROOT/uv-bin/uv"
KIT_UV_READY=0

validate_tool_path() {
  local path="$1"

  [ ! -L "$path" ] || kit_die "Refusing a symlinked managed tooling path: $path"
  if [ -e "$path" ] && [ ! -d "$path" ]; then
    kit_die "Managed tooling path is not a directory: $path"
  fi
}

validate_tool_path "$TOOL_ROOT"
validate_tool_path "$TOOL_BIN_DIR"
validate_tool_path "$TOOL_UV_DIR"

prepare_managed_tool_root() {
  [ "$TOOL_ROOT_PREPARED" -eq 0 ] || return 0

  kit_tooling_idle || kit_die "Installation stopped before changing managed tooling."
  kit_backup_path "$TOOL_ROOT" "tooling/environment"
  if [ -d "$TOOL_ROOT" ]; then
    kit_tooling_idle || kit_die "Installation stopped before clearing the old managed environment."
    echo "Managed tooling failed validation; rebuilding from an empty directory. Backup: $KIT_BACKUP_DIR/tooling/environment"
    rm -rf -- "$TOOL_ROOT"
  fi
  kit_require_real_dir "$TOOL_ROOT"
  kit_require_real_dir "$TOOL_BIN_DIR"
  kit_require_real_dir "$TOOL_UV_DIR"
  TOOL_ROOT_PREPARED=1
}

ensure_uv() {
  [ "$KIT_UV_READY" -eq 0 ] || return 0
  prepare_managed_tool_root
  if [ ! -x "$KIT_UV_BIN" ]; then
    kit_require_real_dir "$TOOL_ROOT/uv-bin"
    if command -v uv >/dev/null 2>&1 && tool_version_matches uv "$KIT_UV_VERSION"; then
      cp "$(command -v uv)" "$KIT_UV_BIN"
    else
      echo "Preparing kit-local uv $KIT_UV_VERSION (no system Python required)."
      download_file "https://astral.sh/uv/$KIT_UV_VERSION/install.sh" "$KIT_WORK_DIR/install-uv.sh"
      UV_UNMANAGED_INSTALL="$TOOL_ROOT/uv-bin" sh "$KIT_WORK_DIR/install-uv.sh" || kit_die "uv bootstrap failed."
    fi
  fi
  tool_version_matches "$KIT_UV_BIN" "$KIT_UV_VERSION" || kit_die "Kit uv does not report $KIT_UV_VERSION."
  kit_require_real_dir "$TOOL_ROOT/python"
  export UV_PYTHON_INSTALL_DIR="$TOOL_ROOT/python"
  export UV_TOOL_DIR="$TOOL_UV_DIR"
  export UV_TOOL_BIN_DIR="$TOOL_BIN_DIR"
  export UV_PYTHON_DOWNLOADS=automatic
  export UV_CACHE_DIR="$KIT_WORK_DIR/uv-cache"
  export UV_LINK_MODE=copy
  kit_tooling_idle || kit_die "Installation stopped before provisioning managed Python."
  "$KIT_UV_BIN" --no-config python install --managed-python --no-bin "$KIT_PYTHON_VERSION" ||
    kit_die "Failed to provision kit Python $KIT_PYTHON_VERSION."
  KIT_UV_READY=1
}

tool_environment_ready() {
  local command_name="$1"
  local expected_version="$2"
  local distribution="$3"
  local command_path="$TOOL_BIN_DIR/$1"
  local python_path="$TOOL_UV_DIR/$distribution/bin/python"

  [ -x "$command_path" ] && [ -x "$python_path" ] || return 1
  tool_version_matches "$command_path" "$expected_version" || return 1
  "$python_path" -I -B "$ROOT/headroom/runtime.py" environment "$distribution" "$expected_version" || return 1
  "$KIT_UV_BIN" --no-config pip check --python "$python_path" || return 1
  if [ "$command_name" = headroom ]; then
    "$python_path" -I -B "$ROOT/headroom/runtime.py" dependencies "$expected_version" || return 1
  fi
}

ensure_tool() {
  local command_name="$1"
  local package="$2"
  local expected_version="$3"
  local install_state_var="$4"
  local distribution="$5"

  ensure_uv
  kit_tooling_idle || kit_die "Installation stopped before replacing $command_name."
  echo "Installing/repairing $command_name in its kit-managed Python environment."
  "$KIT_UV_BIN" --no-config tool install --managed-python --python "$KIT_PYTHON_VERSION" \
    --reinstall "$package" || kit_die "Failed to install $command_name with uv."
  hash -r 2>/dev/null || true
  tool_environment_ready "$command_name" "$expected_version" "$distribution" ||
    kit_die "Managed Python environment verification failed for $command_name."
  printf -v "$install_state_var" '%s' installed
}

# Always put the managed bin first. A previous run leaves this directory in the
# shell rc, and ~/.profile can prepend ~/.local/bin ahead of it, so testing for
# mere presence would let a stale copy there shadow the version installed here.
PATH="$TOOL_BIN_DIR:$PATH"
export PATH
hash -r 2>/dev/null || true

GRAPHIFY_STATE=""
HEADROOM_STATE=""
if [ -x "$KIT_UV_BIN" ] && tool_version_matches "$KIT_UV_BIN" "$KIT_UV_VERSION" &&
    tool_environment_ready graphify "$GRAPHIFY_VERSION" graphifyy &&
    tool_environment_ready headroom "$HEADROOM_VERSION" headroom-ai; then
  GRAPHIFY_STATE=present
  HEADROOM_STATE=present
else
  ensure_tool graphify "$GRAPHIFY_PACKAGE" "$GRAPHIFY_VERSION" GRAPHIFY_STATE graphifyy
  ensure_tool headroom "$HEADROOM_PACKAGE" "$HEADROOM_VERSION" HEADROOM_STATE headroom-ai
fi
GRAPHIFY_BIN="$(command -v graphify 2>/dev/null || true)"
[ -n "$GRAPHIFY_BIN" ] || kit_die "Graphify installation completed but its command is not on PATH: $TOOL_BIN_DIR"

HEADROOM_BIN="$(command -v headroom 2>/dev/null || true)"
[ -n "$HEADROOM_BIN" ] || kit_die "Headroom installation completed but its command is not on PATH: $TOOL_BIN_DIR"
KIT_HEADROOM_PYTHON="$TOOL_UV_DIR/headroom-ai/bin/python"
KIT_TOOLING_PREPARED=1
}

install_tooling() {
prepare_tooling

HEADROOM_WRAPPER="$HOME/.config/headroom/auto-wrap.sh"
kit_require_regular_or_absent "$HEADROOM_WRAPPER"
kit_backup_path "$HEADROOM_WRAPPER" "tooling/headroom-auto-wrap.sh"
kit_replace_file "$ROOT/headroom/auto-wrap.sh" "$HEADROOM_WRAPPER" || kit_die "Failed to install the Headroom wrapper."
kit_require_regular_or_absent "$HOME/.config/headroom/runtime.py"
kit_backup_path "$HOME/.config/headroom/runtime.py" "tooling/headroom-runtime.py"
kit_replace_file "$ROOT/headroom/runtime.py" "$HOME/.config/headroom/runtime.py"
KIT_HEADROOM_PYTHON="$TOOL_UV_DIR/headroom-ai/bin/python"


backup_graphify_skills

CODEX_AGENTS="$HOME/.codex/AGENTS.md"
CODEX_GRAPHIFY_BLOCK="$KIT_WORK_DIR/graphify-codex-agents-block"
cat > "$CODEX_GRAPHIFY_BLOCK" <<'EOF'
# BEGIN UNIVERSAL RESEARCH AGENT KIT GRAPHIFY
## Graphify

For an explicit graph request or an existing useful project graph, use the installed Graphify skill and its scoped query/path/explain workflow. Do not build or query a graph as a prerequisite for ordinary code reading.

The global Graphify skill is installed at `~/.codex/skills/graphify/SKILL.md`.
# END UNIVERSAL RESEARCH AGENT KIT GRAPHIFY
EOF
kit_replace_managed_block "$CODEX_AGENTS" "$CODEX_GRAPHIFY_BLOCK" "tooling/graphify-codex-agents" '# BEGIN UNIVERSAL RESEARCH AGENT KIT GRAPHIFY' '# END UNIVERSAL RESEARCH AGENT KIT GRAPHIFY'


SHELL_BLOCK="$KIT_WORK_DIR/headroom-shell-block"
cat > "$SHELL_BLOCK" <<'EOF'
# BEGIN UNIVERSAL RESEARCH AGENT KIT HEADROOM
case ":$PATH:" in
  *:"$HOME/.local/bin":*) ;;
  *) PATH="$HOME/.local/bin:$PATH" ; export PATH ;;
esac
case ":$PATH:" in
  *:"$HOME/.universal-research-agent-kit/cli/bin":*) ;;
  *) PATH="$HOME/.universal-research-agent-kit/cli/bin:$PATH" ; export PATH ;;
esac
case ":$PATH:" in
  *:"$HOME/.universal-research-agent-kit/tooling/bin":*) ;;
  *) PATH="$HOME/.universal-research-agent-kit/tooling/bin:$PATH" ; export PATH ;;
esac
[ -f "$HOME/.config/headroom/auto-wrap.sh" ] && source "$HOME/.config/headroom/auto-wrap.sh"
# END UNIVERSAL RESEARCH AGENT KIT HEADROOM
EOF
kit_replace_managed_block "$HOME/.zshrc" "$SHELL_BLOCK" "shell/zshrc" '# BEGIN UNIVERSAL RESEARCH AGENT KIT HEADROOM' '# END UNIVERSAL RESEARCH AGENT KIT HEADROOM'
kit_replace_managed_block "$HOME/.bashrc" "$SHELL_BLOCK" "shell/bashrc" '# BEGIN UNIVERSAL RESEARCH AGENT KIT HEADROOM' '# END UNIVERSAL RESEARCH AGENT KIT HEADROOM'

"$GRAPHIFY_BIN" install --platform claude || kit_die "Graphify Claude global installation failed."
"$GRAPHIFY_BIN" install --platform codex || kit_die "Graphify Codex global installation failed."

# Install shared MCP configuration once; normal sessions never rewrite it.
kit_backup_path "$HOME/.codex/config.toml" "tooling/headroom-codex-config"
for mcp_path in "$HOME/.claude.json" "$HOME/.claude/mcp.json"; do
  kit_require_regular_or_absent "$mcp_path"
done
kit_backup_path "$HOME/.claude.json" "tooling/headroom-claude-config"
kit_backup_path "$HOME/.claude/mcp.json" "tooling/headroom-claude-legacy-mcp"
"$KIT_HEADROOM_PYTHON" -I -B "$ROOT/headroom/runtime.py" install-mcp codex || kit_die "Headroom Codex MCP registration failed."
"$KIT_HEADROOM_PYTHON" -I -B "$ROOT/headroom/runtime.py" install-mcp claude || kit_die "Headroom Claude MCP registration failed."

kit_require_regular_or_absent "$KIT_STATE_ROOT/headroom.json"
kit_backup_path "$KIT_STATE_ROOT/headroom.json" "tooling/headroom-state"
KIT_HEADROOM_CREATED=0
[ -f "$KIT_STATE_ROOT/headroom.json" ] || KIT_HEADROOM_CREATED=1
KIT_HEADROOM_ACTIVATION_STARTED=1
"$KIT_HEADROOM_PYTHON" -I -B "$ROOT/headroom/runtime.py" install || kit_die "Persistent Headroom installation failed."
if [ "$(uname -s)" = Linux ]; then
  if ! command -v loginctl >/dev/null 2>&1 ||
      [ "$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null || true)" != yes ]; then
    echo "Note: user systemd is ready, but SSH-logout/reboot persistence needs linger. Ask your administrator or run: loginctl enable-linger $(id -un)"
  fi
fi


if [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS:-0}" != 1 ]; then install_opencode_configuration; fi

kit_write_tooling_state "installed" "$GRAPHIFY_STATE" "$HEADROOM_STATE" "installed" \
  "$GRAPHIFY_VERSION" "$HEADROOM_VERSION" "$TOOL_BIN_DIR"
echo "Installed Graphify, Headroom MCP, process-local launchers and the host persistent proxy."

}
