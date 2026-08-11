#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/lib/install_common.sh"

GRAPHIFY_VERSION="0.9.39"
HEADROOM_VERSION="0.34.0"
GRAPHIFY_PACKAGE="graphifyy==$GRAPHIFY_VERSION"
HEADROOM_PACKAGE="headroom-ai[all]==$HEADROOM_VERSION"

# Graphify 0.9.39 still writes Claude's global registration to ~/.claude even
# when CLAUDE_CONFIG_DIR points elsewhere. Reject that ambiguous layout before
# creating the shared state or changing any user files.
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
  kit_die "CLAUDE_CONFIG_DIR is not supported by this installer; unset it and rerun."
fi

kit_init_state
kit_enable_rollback

TOOL_ROOT="$KIT_STATE_ROOT/tooling"
TOOL_BIN_DIR="$TOOL_ROOT/bin"
TOOL_UV_DIR="$TOOL_ROOT/uv-tools"
TOOL_ROOT_PREPARED=0

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

  kit_backup_path "$TOOL_ROOT" "tooling/environment"
  kit_require_real_dir "$TOOL_ROOT"
  kit_require_real_dir "$TOOL_BIN_DIR"
  kit_require_real_dir "$TOOL_UV_DIR"
  TOOL_ROOT_PREPARED=1
}

tool_version_matches() {
  local command_name="$1"
  local expected_version="$2"
  local candidate
  local output

  output="$("$command_name" --version 2>&1 || true)"
  while IFS= read -r candidate; do
    [ "$candidate" = "$expected_version" ] && return 0
  done <<EOF
$(printf '%s\n' "$output" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z]+)*' || true)
EOF
  return 1
}

ensure_tool() {
  local command_name="$1"
  local package="$2"
  local expected_version="$3"
  local install_state_var="$4"
  local uv_python="${5:-}"
  local command_path
  local venv_dir

  command_path="$(command -v "$command_name" 2>/dev/null || true)"
  if [ -n "$command_path" ] && tool_version_matches "$command_name" "$expected_version"; then
    printf -v "$install_state_var" '%s' 'present'
    return
  fi

  prepare_managed_tool_root
  if [ -n "$command_path" ]; then
    echo "$command_name is not version $expected_version; installing the pinned managed copy."
  fi

  if command -v uv >/dev/null 2>&1; then
    echo "Installing $command_name with uv in $TOOL_ROOT."
    if [ -n "$uv_python" ]; then
      UV_TOOL_DIR="$TOOL_UV_DIR" XDG_BIN_HOME="$TOOL_BIN_DIR" \
        uv tool install --python "$uv_python" --upgrade "$package" \
        || kit_die "Failed to install $command_name with uv."
    else
      UV_TOOL_DIR="$TOOL_UV_DIR" XDG_BIN_HOME="$TOOL_BIN_DIR" \
        uv tool install --upgrade "$package" \
        || kit_die "Failed to install $command_name with uv."
    fi
  elif command -v python3 >/dev/null 2>&1; then
    echo "Installing $command_name with python3 -m pip in $TOOL_ROOT."
    venv_dir="$TOOL_ROOT/python-venv"
    validate_tool_path "$venv_dir"
    if [ ! -x "$venv_dir/bin/python" ]; then
      python3 -m venv "$venv_dir" || kit_die "Failed to create the managed Python environment for $command_name."
    fi
    "$venv_dir/bin/python" -m pip install --upgrade "$package" \
      || kit_die "Failed to install $command_name with python3 -m pip."
    [ -x "$venv_dir/bin/$command_name" ] ||
      kit_die "The managed Python environment did not provide the $command_name command."
    kit_remove_owned_entry "$TOOL_BIN_DIR" "$command_name"
    ln -s "$venv_dir/bin/$command_name" "$TOOL_BIN_DIR/$command_name"
  else
    kit_die "Cannot install $command_name: neither uv nor python3 is available."
  fi

  command_path="$(command -v "$command_name" 2>/dev/null || true)"
  if [ -z "$command_path" ] || ! tool_version_matches "$command_name" "$expected_version"; then
    kit_die "$command_name installation completed but did not provide version $expected_version on PATH."
  fi
  printf -v "$install_state_var" '%s' 'installed'
}

case ":$PATH:" in
  *":$TOOL_BIN_DIR:"*) ;;
  *) PATH="$TOOL_BIN_DIR:$PATH" ;;
esac
export PATH

GRAPHIFY_STATE=""
HEADROOM_STATE=""
ensure_tool graphify "$GRAPHIFY_PACKAGE" "$GRAPHIFY_VERSION" GRAPHIFY_STATE
GRAPHIFY_BIN="$(command -v graphify 2>/dev/null || true)"
[ -n "$GRAPHIFY_BIN" ] || kit_die "Graphify installation completed but its command is not on PATH: $TOOL_BIN_DIR"

ensure_tool headroom "$HEADROOM_PACKAGE" "$HEADROOM_VERSION" HEADROOM_STATE 3.13
HEADROOM_BIN="$(command -v headroom 2>/dev/null || true)"
[ -n "$HEADROOM_BIN" ] || kit_die "Headroom installation completed but its command is not on PATH: $TOOL_BIN_DIR"

HEADROOM_WRAPPER="$HOME/.config/headroom/auto-wrap.sh"
kit_require_regular_or_absent "$HEADROOM_WRAPPER"
kit_backup_path "$HEADROOM_WRAPPER" "tooling/headroom-auto-wrap.sh"
kit_replace_file "$ROOT/headroom/auto-wrap.sh" "$HEADROOM_WRAPPER" || kit_die "Failed to install the Headroom wrapper."

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

CODEX_AGENTS="$HOME/.codex/AGENTS.md"
CODEX_GRAPHIFY_BLOCK="$KIT_BACKUP_DIR/graphify-codex-agents-block"
cat > "$CODEX_GRAPHIFY_BLOCK" <<'EOF'
# BEGIN UNIVERSAL RESEARCH AGENT KIT GRAPHIFY
## Graphify

For codebase, architecture, file-relationship, or project-content questions, use the installed Graphify skill and query the graph before reading the repository broadly. Prefer `graphify query "<question>"` and use the skill's scoped query/path/explain workflow.

The global Graphify skill is installed at `~/.codex/skills/graphify/SKILL.md`.
# END UNIVERSAL RESEARCH AGENT KIT GRAPHIFY
EOF
kit_replace_managed_block "$CODEX_AGENTS" "$CODEX_GRAPHIFY_BLOCK" "tooling/graphify-codex-agents" '# BEGIN UNIVERSAL RESEARCH AGENT KIT GRAPHIFY' '# END UNIVERSAL RESEARCH AGENT KIT GRAPHIFY'

# Graphify refreshes .graphify_version in every previously installed platform
# skill directory. Back up those directories too, otherwise a later failure
# could leave an unrelated platform's version stamp changed.
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
  [ ! -L "$graphify_existing_skill" ] || kit_die "Refusing a symlinked Graphify skill: $graphify_existing_skill"
  if [ -e "$graphify_existing_skill" ] && [ ! -d "$graphify_existing_skill" ]; then
    kit_die "Graphify skill path is not a directory: $graphify_existing_skill"
  fi
  if [ -e "$graphify_existing_skill" ]; then
    kit_backup_path "$graphify_existing_skill" "tooling/graphify-existing-$GRAPHIFY_EXISTING_INDEX"
    GRAPHIFY_EXISTING_INDEX=$((GRAPHIFY_EXISTING_INDEX + 1))
  fi
done

SHELL_BLOCK="$KIT_BACKUP_DIR/headroom-shell-block"
cat > "$SHELL_BLOCK" <<'EOF'
# BEGIN UNIVERSAL RESEARCH AGENT KIT HEADROOM
case ":$PATH:" in
  *:"$HOME/.local/bin":*) ;;
  *) PATH="$HOME/.local/bin:$PATH" ; export PATH ;;
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

kit_write_tooling_state "installed" "$GRAPHIFY_STATE" "$HEADROOM_STATE" "installed" \
  "$GRAPHIFY_VERSION" "$HEADROOM_VERSION" "$TOOL_BIN_DIR"
echo "Installed Graphify global wiring and Headroom shell wrappers."
