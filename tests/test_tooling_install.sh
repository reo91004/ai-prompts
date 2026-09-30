#!/usr/bin/env bash
set -euo pipefail
export UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS=1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export KIT_TEST_PYTHON="$(python3 -c 'import sys; print(sys.executable)')"
export KIT_TEST_MOCK_RUNTIME="$ROOT/tests/mock_runtime.py"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/tooling-install.XXXXXX")"
TMP_HOME="$TMP_ROOT/home"
MOCK_BIN="$TMP_ROOT/mock-bin"
CALLS="$TMP_ROOT/calls.log"
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

mkdir -p "$TMP_HOME" "$MOCK_BIN"
# This fixture does not inspect or mutate the real host's running tools.
printf '%s\n' '#!/bin/sh' 'echo "42 /usr/bin/idle-fixture"' > "$MOCK_BIN/ps"
chmod +x "$MOCK_BIN/ps"
cat > "$MOCK_BIN/python3" <<'EOF'
#!/bin/sh
case "$*" in
  *'/headroom/maintenance.py '*) exec "$KIT_TEST_PYTHON" "$KIT_TEST_MOCK_RUNTIME" "$@" ;;
esac
exec "$KIT_TEST_PYTHON" "$@"
EOF
chmod +x "$MOCK_BIN/python3"
ln -s "$(command -v jq)" "$MOCK_BIN/jq"
printf '%s\n' '#!/bin/sh' 'echo "Unexpected test network download" >&2; exit 22' > "$MOCK_BIN/curl"
chmod +x "$MOCK_BIN/curl"
printf '%s\n' '# user-owned zshrc content' > "$TMP_HOME/.zshrc"
printf '%s\n' '# user-owned bashrc content' > "$TMP_HOME/.bashrc"
mkdir -p "$TMP_HOME/.claude"
printf '%s\n' 'user-owned Claude prompt content' > "$TMP_HOME/.claude/CLAUDE.md"

cat > "$MOCK_BIN/uv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'uv %s\n' "$*" >> "$TOOLING_TEST_CALLS"
[ "${1:-}" != "--version" ] || { echo "uv 0.12.10"; exit 0; }
[ "${TOOLING_TEST_UV_FAIL:-0}" != "1" ] || exit 42
MOCK_TOOL_BIN="${XDG_BIN_HOME:-$UV_TOOL_BIN_DIR}"
mkdir -p "$MOCK_TOOL_BIN"
case "$*" in
  --version) echo 'uv 0.12.10' ;;
  *'python install'*) : ;;
  '--no-config pip check --python '*)
    [ "${TOOLING_TEST_PIP_FAIL:-0}" != 1 ] || exit 44
    [ ! -f "$(dirname "$5")/dependency-conflict" ] || exit 43
    ;;
  'tool dir --bin')
    printf '%s\n' "$UV_TOOL_BIN_DIR"
    ;;
  *graphifyy*)
    printf '%s\n' \
      '#!/usr/bin/env bash' \
      'set -euo pipefail' \
      'if [ "${1:-}" = "--version" ]; then printf "%s\\n" "graphify 0.9.39"; exit 0; fi' \
      'printf "graphify %s\\n" "$*" >> "$TOOLING_TEST_CALLS"' \
      '[ "${TOOLING_TEST_GRAPHIFY_FAIL:-}" != "${3:-}" ] || exit 42' \
      'case "${3:-}" in' \
      '  claude)' \
      '    mkdir -p "$HOME/.claude/skills/graphify"' \
      '    mkdir -p "$HOME/.claude/skills/graphify/references"' \
      '    printf "%s\\n" "# graphify" > "$HOME/.claude/skills/graphify/SKILL.md"' \
      '    printf "%s\\n" "0.9.39" > "$HOME/.claude/skills/graphify/.graphify_version"' \
      '    printf "%s\\n" "reference" > "$HOME/.claude/skills/graphify/references/README.md"' \
      '    printf "%s\\n" "# graphify" "- **graphify** (\`~/.claude/skills/graphify/SKILL.md\`) - any input to knowledge graph. Trigger: \`/graphify\`" "When the user types \`/graphify\`, use the installed graphify skill or instructions before doing anything else." >> "$HOME/.claude/CLAUDE.md"' \
      '    if [ -f "$HOME/.config/opencode/skills/graphify/SKILL.md" ]; then printf "%s\\n" "0.9.39" > "$HOME/.config/opencode/skills/graphify/.graphify_version"; fi' \
      '    if [ -f "$HOME/.gemini/config/skills/graphify/SKILL.md" ]; then printf "%s\\n" "0.9.39" > "$HOME/.gemini/config/skills/graphify/.graphify_version"; fi' \
      '    ;;' \
      '  codex)' \
      '    mkdir -p "$HOME/.codex/skills/graphify"' \
      '    mkdir -p "$HOME/.codex/skills/graphify/references"' \
      '    printf "%s\\n" "# graphify" > "$HOME/.codex/skills/graphify/SKILL.md"' \
      '    printf "%s\\n" "0.9.39" > "$HOME/.codex/skills/graphify/.graphify_version"' \
      '    printf "%s\\n" "reference" > "$HOME/.codex/skills/graphify/references/README.md"' \
      '    ;;' \
      '  *) exit 1 ;;' \
      'esac' > "$MOCK_TOOL_BIN/graphify"
    chmod +x "$MOCK_TOOL_BIN/graphify"
    mkdir -p "$UV_TOOL_DIR/graphifyy/bin"
    printf '%s\n' '#!/bin/sh' 'exec "$KIT_TEST_PYTHON" "$KIT_TEST_MOCK_RUNTIME" "$@"' > "$UV_TOOL_DIR/graphifyy/bin/python"
    chmod +x "$UV_TOOL_DIR/graphifyy/bin/python"
    ;;
  *headroom-ai*)
    printf '%s\n' '#!/usr/bin/env bash' 'if [ "${1:-}" = "--version" ]; then printf "%s\\n" "headroom 0.34.0"; exit 0; fi' 'printf "headroom %s\\n" "$*" >> "$TOOLING_TEST_CALLS"' 'printf "headroom-resolved %s\\n" "$(command -v headroom)" >> "$TOOLING_TEST_CALLS"' > "$MOCK_TOOL_BIN/headroom"
    chmod +x "$MOCK_TOOL_BIN/headroom"
    mkdir -p "$UV_TOOL_DIR/headroom-ai/bin"
    printf '%s\n' '#!/bin/sh' 'exec "$KIT_TEST_PYTHON" "$KIT_TEST_MOCK_RUNTIME" "$@"' > "$UV_TOOL_DIR/headroom-ai/bin/python"
    chmod +x "$UV_TOOL_DIR/headroom-ai/bin/python"
    rm -f "$HOME/.broken-headroom"
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
    bash "$ROOT/install.sh"
}

UV_TOOL_BIN_DIR="$TMP_ROOT/tool-bin"
run_tooling

grep -Fqx 'uv --no-config tool install --managed-python --python 3.13 --reinstall graphifyy==0.9.39' "$CALLS"
grep -Fqx 'uv --no-config tool install --managed-python --python 3.13 --reinstall headroom-ai[all]==0.34.0' "$CALLS"
grep -Fqx 'graphify install --platform claude' "$CALLS"
grep -Fqx 'graphify install --platform codex' "$CALLS"
grep -Fqx 'status=installed' "$TMP_HOME/.universal-research-agent-kit/tooling.state"
grep -Fqx 'graphify=installed' "$TMP_HOME/.universal-research-agent-kit/tooling.state"
grep -Fqx 'headroom=installed' "$TMP_HOME/.universal-research-agent-kit/tooling.state"
grep -Fqx 'headroom_wrapper=installed' "$TMP_HOME/.universal-research-agent-kit/tooling.state"
grep -Fqx 'graphify_version=0.9.39' "$TMP_HOME/.universal-research-agent-kit/tooling.state"
grep -Fqx 'headroom_version=0.34.0' "$TMP_HOME/.universal-research-agent-kit/tooling.state"
grep -Fqx "tool_bin_dir=$TMP_HOME/.universal-research-agent-kit/tooling/bin" "$TMP_HOME/.universal-research-agent-kit/tooling.state"
[ -f "$TMP_HOME/.claude/skills/graphify/SKILL.md" ]
[ -f "$TMP_HOME/.codex/skills/graphify/SKILL.md" ]
grep -Fqx '# BEGIN UNIVERSAL RESEARCH AGENT KIT GRAPHIFY' "$TMP_HOME/.codex/AGENTS.md"
grep -Fqx '# END UNIVERSAL RESEARCH AGENT KIT GRAPHIFY' "$TMP_HOME/.codex/AGENTS.md"
grep -Fqx '# user-owned zshrc content' "$TMP_HOME/.zshrc"
grep -Fqx '# user-owned bashrc content' "$TMP_HOME/.bashrc"
grep -Fqx 'user-owned Claude prompt content' "$TMP_HOME/.universal-research-agent-kit/backups/"run.*/claude/CLAUDE.md

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
grep -Fqx 'runtime launch claude prompt' "$CALLS"
grep -Fqx 'runtime launch codex prompt' "$CALLS"
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
grep -Fqx 'runtime launch codex shadowed' "$CALLS"
! grep -Fq "shadow headroom" "$CALLS"
! grep -Fq 'shadow headroom' "$CALLS"

HOME="$TMP_HOME" PATH="$MOCK_BIN:$UV_TOOL_BIN_DIR:/usr/bin:/bin" TOOLING_TEST_CALLS="$CALLS" zsh -fc '
  source "$HOME/.zshrc"
  claude zsh-prompt
  codex zsh-prompt
'
grep -Fqx 'runtime launch claude zsh-prompt' "$CALLS"
grep -Fqx 'runtime launch codex zsh-prompt' "$CALLS"

run_tooling
[ "$(grep -Fc 'tool install --managed-python' "$CALLS")" -eq 2 ]
[ "$(grep -Fc 'graphify install --platform claude' "$CALLS")" -eq 2 ]
[ "$(grep -Fc 'graphify install --platform codex' "$CALLS")" -eq 2 ]
[ "$(grep -Fxc '# BEGIN UNIVERSAL RESEARCH AGENT KIT HEADROOM' "$TMP_HOME/.zshrc")" -eq 1 ]
[ "$(grep -Fxc '# END UNIVERSAL RESEARCH AGENT KIT HEADROOM' "$TMP_HOME/.zshrc")" -eq 1 ]

BAD_VERSION_HOME="$TMP_ROOT/bad-version-home"
BAD_VERSION_BIN="$TMP_ROOT/bad-version-bin"
mkdir -p "$BAD_VERSION_HOME" "$BAD_VERSION_BIN"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" "graphify 0.9.390"' > "$BAD_VERSION_BIN/graphify"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" "headroom, version 10.34.0-dev"' > "$BAD_VERSION_BIN/headroom"
chmod +x "$BAD_VERSION_BIN/graphify" "$BAD_VERSION_BIN/headroom"
HOME="$BAD_VERSION_HOME" PATH="$BAD_VERSION_BIN:$MOCK_BIN:$UV_TOOL_BIN_DIR:/usr/bin:/bin" \
  UV_TOOL_BIN_DIR="$UV_TOOL_BIN_DIR" TOOLING_TEST_CALLS="$CALLS" \
  bash "$ROOT/install.sh" >/dev/null
grep -Fqx 'graphify=installed' "$BAD_VERSION_HOME/.universal-research-agent-kit/tooling.state"
grep -Fqx 'headroom=installed' "$BAD_VERSION_HOME/.universal-research-agent-kit/tooling.state"
[ "$(grep -Fc 'tool install --managed-python' "$CALLS")" -eq 4 ]

# A repeat install on a machine whose rc already exports the managed bin, with a
# stale same-named binary ahead of it (Ubuntu's ~/.profile prepends ~/.local/bin).
# The installer must verify the copy it just wrote, not whatever PATH resolves to.
SHADOW_HOME="$TMP_ROOT/shadow-home"
SHADOW_LOCAL_BIN="$SHADOW_HOME/.local/bin"
SHADOW_TOOL_BIN="$SHADOW_HOME/.universal-research-agent-kit/tooling/bin"
mkdir -p "$SHADOW_LOCAL_BIN" "$SHADOW_TOOL_BIN"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" "graphify 0.9.32"' > "$SHADOW_LOCAL_BIN/graphify"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" "headroom 0.33.0"' > "$SHADOW_LOCAL_BIN/headroom"
chmod +x "$SHADOW_LOCAL_BIN/graphify" "$SHADOW_LOCAL_BIN/headroom"
HOME="$SHADOW_HOME" PATH="$SHADOW_LOCAL_BIN:$MOCK_BIN:$SHADOW_TOOL_BIN:$UV_TOOL_BIN_DIR:/usr/bin:/bin" \
  UV_TOOL_BIN_DIR="$UV_TOOL_BIN_DIR" TOOLING_TEST_CALLS="$CALLS" \
  bash "$ROOT/install.sh" >"$TMP_ROOT/shadow-install.out" 2>&1 || {
    cat "$TMP_ROOT/shadow-install.out" >&2
    echo "a stale binary earlier in PATH must not fail the install" >&2
    exit 1
  }
grep -Fqx 'graphify=installed' "$SHADOW_HOME/.universal-research-agent-kit/tooling.state"
grep -Fqx 'graphify_version=0.9.39' "$SHADOW_HOME/.universal-research-agent-kit/tooling.state"
grep -Fqx 'headroom=installed' "$SHADOW_HOME/.universal-research-agent-kit/tooling.state"

FULL_HOME="$TMP_ROOT/full-home"
mkdir -p "$FULL_HOME"
HOME="$FULL_HOME" PATH="$MOCK_BIN:$UV_TOOL_BIN_DIR:/usr/bin:/bin" \
  UV_TOOL_BIN_DIR="$UV_TOOL_BIN_DIR" TOOLING_TEST_CALLS="$CALLS" \
  UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS=1 \
  bash "$ROOT/install.sh" >"$TMP_ROOT/full-install.out" 2>&1 || {
    cat "$TMP_ROOT/full-install.out" >&2
    exit 1
  }
grep -Fqx 'status=installed' "$FULL_HOME/.universal-research-agent-kit/tooling.state"
grep -Fqx 'graphify_version=0.9.39' "$FULL_HOME/.universal-research-agent-kit/tooling.state"
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
  TOOLING_TEST_GRAPHIFY_FAIL=codex bash "$ROOT/install.sh" >"$TMP_ROOT/graphify-failure.out" 2>&1
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
  TOOLING_TEST_CALLS="$CALLS" TOOLING_TEST_UV_FAIL=1 bash "$ROOT/install.sh" >"$TMP_ROOT/failure.out" 2>&1
failure_rc=$?
set -e
[ "$failure_rc" -ne 0 ]
grep -Fq 'Failed to provision kit Python 3.13.' "$TMP_ROOT/failure.out"
[ ! -f "$FAIL_HOME/.universal-research-agent-kit/tooling.state" ]

CONFIG_DIR_HOME="$TMP_ROOT/config-dir-home"
mkdir -p "$CONFIG_DIR_HOME"
set +e
HOME="$CONFIG_DIR_HOME" CLAUDE_CONFIG_DIR="$CONFIG_DIR_HOME/custom-claude" \
  PATH="$MOCK_BIN:/usr/bin:/bin" UV_TOOL_BIN_DIR="$TMP_ROOT/config-dir-bin" \
  TOOLING_TEST_CALLS="$CALLS" bash "$ROOT/install.sh" >"$TMP_ROOT/config-dir-failure.out" 2>&1
config_dir_rc=$?
set -e
[ "$config_dir_rc" -ne 0 ]
grep -Fq 'CLAUDE_CONFIG_DIR is not supported' "$TMP_ROOT/config-dir-failure.out"
[ ! -e "$CONFIG_DIR_HOME/.universal-research-agent-kit" ]

# Reuse a healthy environment, but replace its whole managed tree when a
# runtime, package manager, import or dependency check fails. Keep user data
# outside that tree and retain the old tree in the completed backup.
MANAGED_ROOT="$TMP_HOME/.universal-research-agent-kit/tooling"
mkdir -p "$TMP_HOME/.local/bin" "$TMP_HOME/custom-venv/bin" "$TMP_HOME/.codex" "$TMP_HOME/.claude"
printf 'external Python\n' > "$TMP_HOME/custom-venv/bin/python"
printf 'external Headroom\n' > "$TMP_HOME/.local/bin/headroom"
printf '{"fixture_token":"keep-codex"}\n' > "$TMP_HOME/.codex/auth.json"
printf '{"fixture_token":"keep-claude"}\n' > "$TMP_HOME/.claude/.credentials.json"
printf 'healthy marker\n' > "$MANAGED_ROOT/keep-if-healthy"
before_tools="$(grep -Fc 'tool install --managed-python' "$CALLS")"
run_tooling > "$TMP_ROOT/healthy-repeat.out" 2>&1
[ "$(grep -Fc 'tool install --managed-python' "$CALLS")" -eq "$before_tools" ]
[ -f "$MANAGED_ROOT/keep-if-healthy" ]

for corruption in uv python imports dependencies; do
  mkdir -p "$MANAGED_ROOT/python-venv/bin"
  printf 'old shared environment: %s\n' "$corruption" > "$MANAGED_ROOT/python-venv/bin/old-tool"
  case "$corruption" in
    uv) printf '%s\n' '#!/bin/sh' 'echo "uv 0.0.1"' > "$MANAGED_ROOT/uv-bin/uv" ;;
    python)
      rm "$MANAGED_ROOT/uv-tools/headroom-ai/bin/python"
      ln -s /missing-kit-python "$MANAGED_ROOT/uv-tools/headroom-ai/bin/python"
      ;;
    imports) touch "$TMP_HOME/.broken-headroom" ;;
    dependencies) touch "$MANAGED_ROOT/uv-tools/headroom-ai/bin/dependency-conflict" ;;
  esac
  before_tools="$(grep -Fc 'tool install --managed-python' "$CALLS")"
  run_tooling > "$TMP_ROOT/rebuild-$corruption.out" 2>&1 || {
    cat "$TMP_ROOT/rebuild-$corruption.out" >&2
    exit 1
  }
  grep -Fq 'rebuilding from an empty directory' "$TMP_ROOT/rebuild-$corruption.out"
  [ "$(grep -Fc 'tool install --managed-python' "$CALLS")" -eq "$((before_tools + 2))" ]
  [ ! -e "$MANAGED_ROOT/python-venv" ]
  [ ! -e "$MANAGED_ROOT/keep-if-healthy" ]
  grep -Fqx "old shared environment: $corruption" "$TMP_HOME/.universal-research-agent-kit/backups/"run.*/tooling/environment/python-venv/bin/old-tool
  grep -Fqx 'external Python' "$TMP_HOME/custom-venv/bin/python"
  grep -Fqx 'external Headroom' "$TMP_HOME/.local/bin/headroom"
  grep -Fqx '{"fixture_token":"keep-codex"}' "$TMP_HOME/.codex/auth.json"
  grep -Fqx '{"fixture_token":"keep-claude"}' "$TMP_HOME/.claude/.credentials.json"
done

# A failed fresh build must restore the complete old environment instead of
# leaving a half-installed replacement at the active path.
for failure in provision verification; do
  printf '%s\n' '#!/bin/sh' 'echo "uv 0.0.1"' > "$MANAGED_ROOT/uv-bin/uv"
  printf 'old environment before failed rebuild\n' > "$MANAGED_ROOT/restore-me"
  cp -Rp "$MANAGED_ROOT" "$TMP_ROOT/before-failed-$failure"
  if TOOLING_TEST_UV_FAIL="$([ "$failure" = provision ] && echo 1 || echo 0)" \
      TOOLING_TEST_PIP_FAIL="$([ "$failure" = verification ] && echo 1 || echo 0)" \
      run_tooling > "$TMP_ROOT/rebuild-$failure-failure.out" 2>&1; then
    echo 'a failed fresh build was incorrectly accepted' >&2
    exit 1
  fi
  grep -Fq 'rebuilding from an empty directory' "$TMP_ROOT/rebuild-$failure-failure.out"
  grep -Fq 'Rollback complete.' "$TMP_ROOT/rebuild-$failure-failure.out"
  diff -r "$TMP_ROOT/before-failed-$failure" "$MANAGED_ROOT"
  grep -Fqx '{"fixture_token":"keep-codex"}' "$TMP_HOME/.codex/auth.json"
  grep -Fqx '{"fixture_token":"keep-claude"}' "$TMP_HOME/.claude/.credentials.json"
done

echo "Tooling installation tests passed."
