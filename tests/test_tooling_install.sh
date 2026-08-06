#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/tooling-install.XXXXXX")"
TMP_HOME="$TMP_ROOT/home"
MOCK_BIN="$TMP_ROOT/mock-bin"
CALLS="$TMP_ROOT/calls.log"
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

mkdir -p "$TMP_HOME" "$MOCK_BIN"
printf '%s\n' '# user-owned zshrc content' > "$TMP_HOME/.zshrc"
printf '%s\n' '# user-owned bashrc content' > "$TMP_HOME/.bashrc"
mkdir -p "$TMP_HOME/.claude"
printf '%s\n' 'user-owned Claude prompt content' > "$TMP_HOME/.claude/CLAUDE.md"

cat > "$MOCK_BIN/uv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'uv %s\n' "$*" >> "$TOOLING_TEST_CALLS"
[ "${TOOLING_TEST_UV_FAIL:-0}" != "1" ] || exit 42
MOCK_TOOL_BIN="${XDG_BIN_HOME:-$UV_TOOL_BIN_DIR}"
mkdir -p "$MOCK_TOOL_BIN"
case "$*" in
  'tool dir --bin')
    printf '%s\n' "$UV_TOOL_BIN_DIR"
    ;;
  *graphifyy*)
    printf '%s\n' \
      '#!/usr/bin/env bash' \
      'set -euo pipefail' \
      'if [ "${1:-}" = "--version" ]; then printf "%s\\n" "graphify 0.9.32"; exit 0; fi' \
      'printf "graphify %s\\n" "$*" >> "$TOOLING_TEST_CALLS"' \
      '[ "${TOOLING_TEST_GRAPHIFY_FAIL:-}" != "${3:-}" ] || exit 42' \
      'case "${3:-}" in' \
      '  claude)' \
      '    mkdir -p "$HOME/.claude/skills/graphify"' \
      '    mkdir -p "$HOME/.claude/skills/graphify/references"' \
      '    printf "%s\\n" "# graphify" > "$HOME/.claude/skills/graphify/SKILL.md"' \
      '    printf "%s\\n" "0.9.32" > "$HOME/.claude/skills/graphify/.graphify_version"' \
      '    printf "%s\\n" "reference" > "$HOME/.claude/skills/graphify/references/README.md"' \
      '    printf "%s\\n" "# graphify" "- **graphify** (\`~/.claude/skills/graphify/SKILL.md\`) - any input to knowledge graph. Trigger: \`/graphify\`" "When the user types \`/graphify\`, use the installed graphify skill or instructions before doing anything else." >> "$HOME/.claude/CLAUDE.md"' \
      '    if [ -f "$HOME/.config/opencode/skills/graphify/SKILL.md" ]; then printf "%s\\n" "0.9.32" > "$HOME/.config/opencode/skills/graphify/.graphify_version"; fi' \
      '    if [ -f "$HOME/.gemini/config/skills/graphify/SKILL.md" ]; then printf "%s\\n" "0.9.32" > "$HOME/.gemini/config/skills/graphify/.graphify_version"; fi' \
      '    ;;' \
      '  codex)' \
      '    mkdir -p "$HOME/.codex/skills/graphify"' \
      '    mkdir -p "$HOME/.codex/skills/graphify/references"' \
      '    printf "%s\\n" "# graphify" > "$HOME/.codex/skills/graphify/SKILL.md"' \
      '    printf "%s\\n" "0.9.32" > "$HOME/.codex/skills/graphify/.graphify_version"' \
      '    printf "%s\\n" "reference" > "$HOME/.codex/skills/graphify/references/README.md"' \
      '    ;;' \
      '  *) exit 1 ;;' \
      'esac' > "$MOCK_TOOL_BIN/graphify"
    chmod +x "$MOCK_TOOL_BIN/graphify"
    ;;
  *headroom-ai*)
    printf '%s\n' '#!/usr/bin/env bash' 'if [ "${1:-}" = "--version" ]; then printf "%s\\n" "headroom 0.34.0"; exit 0; fi' 'printf "headroom %s\\n" "$*" >> "$TOOLING_TEST_CALLS"' 'printf "headroom-resolved %s\\n" "$(command -v headroom)" >> "$TOOLING_TEST_CALLS"' > "$MOCK_TOOL_BIN/headroom"
    chmod +x "$MOCK_TOOL_BIN/headroom"
    ;;
esac
EOF
cat > "$MOCK_BIN/claude" <<'EOF'
#!/usr/bin/env bash
printf 'claude %s\n' "$*" >> "$TOOLING_TEST_CALLS"
EOF
cat > "$MOCK_BIN/codex" <<'EOF'
#!/usr/bin/env bash
printf 'codex %s\n' "$*" >> "$TOOLING_TEST_CALLS"
EOF
chmod +x "$MOCK_BIN/uv" "$MOCK_BIN/claude" "$MOCK_BIN/codex"

run_tooling() {
  HOME="$TMP_HOME" PATH="$MOCK_BIN:$UV_TOOL_BIN_DIR:/usr/bin:/bin" \
    UV_TOOL_BIN_DIR="$UV_TOOL_BIN_DIR" TOOLING_TEST_CALLS="$CALLS" \
    bash "$ROOT/install_tooling.sh"
}

UV_TOOL_BIN_DIR="$TMP_ROOT/tool-bin"
run_tooling

grep -Fqx 'uv tool install --upgrade graphifyy==0.9.32' "$CALLS"
grep -Fqx 'uv tool install --python 3.13 --upgrade headroom-ai[all]==0.34.0' "$CALLS"
grep -Fqx 'graphify install --platform claude' "$CALLS"
grep -Fqx 'graphify install --platform codex' "$CALLS"
grep -Fqx 'status=installed' "$TMP_HOME/.universal-research-agent-kit/tooling.state"
grep -Fqx 'graphify=installed' "$TMP_HOME/.universal-research-agent-kit/tooling.state"
grep -Fqx 'headroom=installed' "$TMP_HOME/.universal-research-agent-kit/tooling.state"
grep -Fqx 'headroom_wrapper=installed' "$TMP_HOME/.universal-research-agent-kit/tooling.state"
grep -Fqx 'graphify_version=0.9.32' "$TMP_HOME/.universal-research-agent-kit/tooling.state"
grep -Fqx 'headroom_version=0.34.0' "$TMP_HOME/.universal-research-agent-kit/tooling.state"
grep -Fqx "tool_bin_dir=$TMP_HOME/.universal-research-agent-kit/tooling/bin" "$TMP_HOME/.universal-research-agent-kit/tooling.state"
[ -f "$TMP_HOME/.claude/skills/graphify/SKILL.md" ]
[ -f "$TMP_HOME/.codex/skills/graphify/SKILL.md" ]
grep -Fqx '# BEGIN UNIVERSAL RESEARCH AGENT KIT GRAPHIFY' "$TMP_HOME/.codex/AGENTS.md"
grep -Fqx '# END UNIVERSAL RESEARCH AGENT KIT GRAPHIFY' "$TMP_HOME/.codex/AGENTS.md"
grep -Fqx '# user-owned zshrc content' "$TMP_HOME/.zshrc"
grep -Fqx '# user-owned bashrc content' "$TMP_HOME/.bashrc"
grep -Fqx 'user-owned Claude prompt content' "$TMP_HOME/.claude/CLAUDE.md"

for shell_file in "$TMP_HOME/.zshrc" "$TMP_HOME/.bashrc"; do
  [ "$(grep -Fxc '# BEGIN UNIVERSAL RESEARCH AGENT KIT HEADROOM' "$shell_file")" -eq 1 ]
  [ "$(grep -Fxc '# END UNIVERSAL RESEARCH AGENT KIT HEADROOM' "$shell_file")" -eq 1 ]
  [ "$(grep -Fxc '[ -f "$HOME/.config/headroom/auto-wrap.sh" ] && source "$HOME/.config/headroom/auto-wrap.sh"' "$shell_file")" -eq 1 ]
done

HOME="$TMP_HOME" PATH="$MOCK_BIN:$UV_TOOL_BIN_DIR:/usr/bin:/bin" TOOLING_TEST_CALLS="$CALLS" bash -c '
  source "$HOME/.zshrc"
  claude prompt
  codex prompt
  claude_raw prompt
  codex_raw prompt
'
grep -Fqx 'headroom wrap claude -- prompt' "$CALLS"
grep -Fqx 'headroom wrap codex -- prompt' "$CALLS"
grep -Fqx 'claude prompt' "$CALLS"
grep -Fqx 'codex prompt' "$CALLS"

SHADOW_BIN="$TMP_ROOT/shadow-bin"
mkdir -p "$SHADOW_BIN"
printf '%s\n' '#!/usr/bin/env bash' 'printf "shadow headroom %s\\n" "$*" >> "$TOOLING_TEST_CALLS"' > "$SHADOW_BIN/headroom"
chmod +x "$SHADOW_BIN/headroom"
HOME="$TMP_HOME" PATH="$SHADOW_BIN:$MOCK_BIN:$UV_TOOL_BIN_DIR:/usr/bin:/bin" TOOLING_TEST_CALLS="$CALLS" bash -c '
  source "$HOME/.config/headroom/auto-wrap.sh"
  codex shadowed
'
grep -Fqx 'headroom wrap codex -- shadowed' "$CALLS"
grep -Fqx "headroom-resolved $TMP_HOME/.universal-research-agent-kit/tooling/bin/headroom" "$CALLS"
! grep -Fq 'shadow headroom' "$CALLS"

HOME="$TMP_HOME" PATH="$MOCK_BIN:$UV_TOOL_BIN_DIR:/usr/bin:/bin" TOOLING_TEST_CALLS="$CALLS" zsh -fc '
  source "$HOME/.zshrc"
  claude zsh-prompt
  codex zsh-prompt
'
grep -Fqx 'headroom wrap claude -- zsh-prompt' "$CALLS"
grep -Fqx 'headroom wrap codex -- zsh-prompt' "$CALLS"

run_tooling
[ "$(grep -Fc 'uv tool install' "$CALLS")" -eq 2 ]
[ "$(grep -Fc 'graphify install --platform claude' "$CALLS")" -eq 2 ]
[ "$(grep -Fc 'graphify install --platform codex' "$CALLS")" -eq 2 ]
[ "$(grep -Fxc '# BEGIN UNIVERSAL RESEARCH AGENT KIT HEADROOM' "$TMP_HOME/.zshrc")" -eq 1 ]
[ "$(grep -Fxc '# END UNIVERSAL RESEARCH AGENT KIT HEADROOM' "$TMP_HOME/.zshrc")" -eq 1 ]

BAD_VERSION_HOME="$TMP_ROOT/bad-version-home"
BAD_VERSION_BIN="$TMP_ROOT/bad-version-bin"
mkdir -p "$BAD_VERSION_HOME" "$BAD_VERSION_BIN"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" "graphify 0.9.320"' > "$BAD_VERSION_BIN/graphify"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" "headroom, version 10.34.0-dev"' > "$BAD_VERSION_BIN/headroom"
chmod +x "$BAD_VERSION_BIN/graphify" "$BAD_VERSION_BIN/headroom"
HOME="$BAD_VERSION_HOME" PATH="$BAD_VERSION_BIN:$MOCK_BIN:$UV_TOOL_BIN_DIR:/usr/bin:/bin" \
  UV_TOOL_BIN_DIR="$UV_TOOL_BIN_DIR" TOOLING_TEST_CALLS="$CALLS" \
  bash "$ROOT/install_tooling.sh" >/dev/null
grep -Fqx 'graphify=installed' "$BAD_VERSION_HOME/.universal-research-agent-kit/tooling.state"
grep -Fqx 'headroom=installed' "$BAD_VERSION_HOME/.universal-research-agent-kit/tooling.state"
[ "$(grep -Fc 'uv tool install' "$CALLS")" -eq 4 ]

FULL_HOME="$TMP_ROOT/full-home"
mkdir -p "$FULL_HOME"
HOME="$FULL_HOME" PATH="$MOCK_BIN:$UV_TOOL_BIN_DIR:/usr/bin:/bin" \
  UV_TOOL_BIN_DIR="$UV_TOOL_BIN_DIR" TOOLING_TEST_CALLS="$CALLS" \
  UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS=1 \
  bash "$ROOT/install_all.sh" >"$TMP_ROOT/full-install.out" 2>&1 || {
    cat "$TMP_ROOT/full-install.out" >&2
    exit 1
  }
grep -Fqx 'status=installed' "$FULL_HOME/.universal-research-agent-kit/tooling.state"
grep -Fqx 'graphify_version=0.9.32' "$FULL_HOME/.universal-research-agent-kit/tooling.state"
grep -Fqx 'headroom_version=0.34.0' "$FULL_HOME/.universal-research-agent-kit/tooling.state"
[ -f "$FULL_HOME/.claude/skills/graphify/SKILL.md" ]
[ -f "$FULL_HOME/.codex/skills/graphify/SKILL.md" ]
[ -f "$FULL_HOME/.config/headroom/auto-wrap.sh" ]

GRAPHIFY_FAIL_HOME="$TMP_ROOT/graphify-fail-home"
mkdir -p "$GRAPHIFY_FAIL_HOME"
mkdir -p "$GRAPHIFY_FAIL_HOME/.config/opencode/skills/graphify"
printf '%s\n' '# existing opencode skill' > "$GRAPHIFY_FAIL_HOME/.config/opencode/skills/graphify/SKILL.md"
printf '%s\n' 'old-version' > "$GRAPHIFY_FAIL_HOME/.config/opencode/skills/graphify/.graphify_version"
mkdir -p "$GRAPHIFY_FAIL_HOME/.gemini/config/skills/graphify"
printf '%s\n' '# existing antigravity skill' > "$GRAPHIFY_FAIL_HOME/.gemini/config/skills/graphify/SKILL.md"
printf '%s\n' 'old-antigravity-version' > "$GRAPHIFY_FAIL_HOME/.gemini/config/skills/graphify/.graphify_version"
set +e
HOME="$GRAPHIFY_FAIL_HOME" PATH="$MOCK_BIN:$UV_TOOL_BIN_DIR:/usr/bin:/bin" \
  UV_TOOL_BIN_DIR="$UV_TOOL_BIN_DIR" TOOLING_TEST_CALLS="$CALLS" \
  TOOLING_TEST_GRAPHIFY_FAIL=codex bash "$ROOT/install_tooling.sh" >"$TMP_ROOT/graphify-failure.out" 2>&1
graphify_failure_rc=$?
set -e
[ "$graphify_failure_rc" -ne 0 ]
grep -Fq 'Graphify Codex global installation failed.' "$TMP_ROOT/graphify-failure.out"
for unexpected in \
  "$GRAPHIFY_FAIL_HOME/.claude/CLAUDE.md" \
  "$GRAPHIFY_FAIL_HOME/.claude/skills/graphify" \
  "$GRAPHIFY_FAIL_HOME/.codex/skills/graphify" \
  "$GRAPHIFY_FAIL_HOME/.codex/AGENTS.md" \
  "$GRAPHIFY_FAIL_HOME/.config/headroom/auto-wrap.sh" \
  "$GRAPHIFY_FAIL_HOME/.zshrc" \
  "$GRAPHIFY_FAIL_HOME/.bashrc" \
  "$GRAPHIFY_FAIL_HOME/.universal-research-agent-kit/tooling.state" \
  "$GRAPHIFY_FAIL_HOME/.universal-research-agent-kit/tooling"; do
  [ ! -e "$unexpected" ] || {
    find "$GRAPHIFY_FAIL_HOME" -maxdepth 5 -print >&2
    exit 1
  }
done
grep -Fqx '# existing opencode skill' "$GRAPHIFY_FAIL_HOME/.config/opencode/skills/graphify/SKILL.md"
grep -Fqx 'old-version' "$GRAPHIFY_FAIL_HOME/.config/opencode/skills/graphify/.graphify_version"
grep -Fqx '# existing antigravity skill' "$GRAPHIFY_FAIL_HOME/.gemini/config/skills/graphify/SKILL.md"
grep -Fqx 'old-antigravity-version' "$GRAPHIFY_FAIL_HOME/.gemini/config/skills/graphify/.graphify_version"

FAIL_HOME="$TMP_ROOT/fail-home"
mkdir -p "$FAIL_HOME"
set +e
HOME="$FAIL_HOME" PATH="$MOCK_BIN:/usr/bin:/bin" UV_TOOL_BIN_DIR="$TMP_ROOT/fail-bin" \
  TOOLING_TEST_CALLS="$CALLS" TOOLING_TEST_UV_FAIL=1 bash "$ROOT/install_tooling.sh" >"$TMP_ROOT/failure.out" 2>&1
failure_rc=$?
set -e
[ "$failure_rc" -ne 0 ]
grep -Fq 'Failed to install graphify with uv.' "$TMP_ROOT/failure.out"
[ ! -f "$FAIL_HOME/.universal-research-agent-kit/tooling.state" ]

CONFIG_DIR_HOME="$TMP_ROOT/config-dir-home"
mkdir -p "$CONFIG_DIR_HOME"
set +e
HOME="$CONFIG_DIR_HOME" CLAUDE_CONFIG_DIR="$CONFIG_DIR_HOME/custom-claude" \
  PATH="$MOCK_BIN:/usr/bin:/bin" UV_TOOL_BIN_DIR="$TMP_ROOT/config-dir-bin" \
  TOOLING_TEST_CALLS="$CALLS" bash "$ROOT/install_tooling.sh" >"$TMP_ROOT/config-dir-failure.out" 2>&1
config_dir_rc=$?
set -e
[ "$config_dir_rc" -ne 0 ]
grep -Fq 'CLAUDE_CONFIG_DIR is not supported' "$TMP_ROOT/config-dir-failure.out"
[ ! -e "$CONFIG_DIR_HOME/.universal-research-agent-kit" ]

echo "Tooling installation tests passed."
