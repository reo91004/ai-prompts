#!/usr/bin/env bash
# Sourced by install.sh.

verify_platform_additions() {
  local source target entry name instructions verify_dir config_result
  KIT_OPENCODE_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
  check_file "$KIT_OPENCODE_CONFIG_DIR/AGENTS.md"
  instructions="$(awk '$0 == "# BEGIN UNIVERSAL RESEARCH AGENT KIT" {copy=1; next} $0 == "# END UNIVERSAL RESEARCH AGENT KIT" {copy=0; next} copy' "$KIT_OPENCODE_CONFIG_DIR/AGENTS.md" 2>/dev/null)"
  [ "$instructions" = "$(cat "$ROOT/opencode/AGENTS.md")" ] || { echo "OpenCode instructions differ from the managed block."; missing=1; }
  for source in "$ROOT/opencode/agents"/*.md; do
    check_same_file "$source" "$KIT_OPENCODE_CONFIG_DIR/agents/${source##*/}"
  done
  check_same_dir "$ROOT/opencode/plugins/research-context" "$KIT_OPENCODE_CONFIG_DIR/research-agent-kit/context"
  check_same_dir "$ROOT/opencode/plugins/openai-websocket" "$KIT_OPENCODE_CONFIG_DIR/research-agent-kit/openai-websocket"
  if [ -n "${HUMANIZER_REVISION:-}" ] && [ "$HUMANIZER_REVISION" != - ]; then
    verify_humanizer_source "$HUMANIZER_REVISION" "$HUMANIZER_CONTENT_SHA256" "$HUMANIZER_SOURCE" || { echo "Humanizer source provenance failed."; missing=1; }
    for target in "$HOME/.agents/skills/humanizer" "$HOME/.claude/skills/humanizer"; do
      verify_humanizer_skill "$target" "$HUMANIZER_CONTENT_SHA256" || { echo "Humanizer content differs: $target"; missing=1; }
    done
  elif [ -f "$STATE_FILE" ] && [ "$(read_state codex_sequential_thinking)" != skipped_env ]; then
    echo "Humanizer installation/provenance is missing."; missing=1
  else
    echo "Scoped verification: Humanizer was skipped with integrations."; scoped=1
  fi
  for target in "$HOME/.agents/skills" "$HOME/.claude/skills"; do
    for entry in "$target"/* "$target"/.[!.]* "$target"/..?*; do
      [ -e "$entry" ] || [ -L "$entry" ] || continue
      name="${entry##*/}"
      [ "$name" != .DS_Store ] || continue
      if [ -d "$ROOT/skills/$name" ]; then continue; fi
      if [ "$name" = humanizer ] && [ -n "${HUMANIZER_REVISION:-}" ] && [ "$HUMANIZER_REVISION" != - ]; then continue; fi
      if [ "$name" = graphify ] && [ "$target" = "$HOME/.claude/skills" ] && [ "$tooling_status_for_prompt" = installed ]; then continue; fi
      echo "Unexpected global user-skill entry: $entry"; missing=1
    done
  done
  if [ "$tooling_status_for_prompt" = installed ] && [ -f "$STATE_FILE" ] &&
      [ "$(read_state codex_sequential_thinking)" != skipped_env ]; then
    if [ ! -f "$KIT_STATE_ROOT/opencode-config.json" ]; then
      echo "OpenCode configuration ownership state is missing."; missing=1
    else
      verify_dir="$(mktemp -d "${TMPDIR:-/tmp}/kit-opencode-verify.XXXXXX")"
      if prepare_opencode_fragments "$verify_dir"; then
        if config_result="$(opencode_config_run check)"; then
          printf '%s\n' "$config_result"
          if printf '%s' "$config_result" | node -e 'const fs=require("fs");process.exit(JSON.parse(fs.readFileSync(0,"utf8")).overrides.includes("opencode.jsonc:plugins:"+process.argv[1])?0:1)' "$KIT_OPENCODE_CONFIG_DIR/research-agent-kit/openai-websocket"; then
            echo "Missing or overridden OpenCode integration: OpenAI WebSocket rotation"; missing=1
          fi
          if [ "$(read_state requested_profile)" = ponytail ] &&
              printf '%s' "$config_result" | node -e 'const fs=require("fs");process.exit(JSON.parse(fs.readFileSync(0,"utf8")).overrides.includes("opencode.jsonc:plugins:@dietrichgebert/ponytail")?0:1)'; then
            echo "Missing or overridden OpenCode integration: Ponytail"; missing=1
          fi
          if printf '%s' "$config_result" | node -e 'const fs=require("fs");process.exit(JSON.parse(fs.readFileSync(0,"utf8")).status==="customized"?0:1)'; then
            echo "Scoped verification: preserved OpenCode user overrides differ from kit defaults."; scoped=1
          fi
        else missing=1; fi
        node "$ROOT/opencode/plugins/btw-plus-compat/patch.mjs" --check "$KIT_STATE_ROOT/tooling/opencode-btw-plus" "$KIT_OPENCODE_VERSION" || missing=1
      else missing=1; fi
      rm -rf -- "$verify_dir"
      unset KIT_HEADROOM_FRAGMENT KIT_OPENCODE_CLI_FRAGMENT
      node "$ROOT/scripts/opencode_config.mjs" effective --config-dir "$KIT_OPENCODE_CONFIG_DIR" \
        --parser "$KIT_STATE_ROOT/tooling/opencode-config/node_modules/jsonc-parser/lib/umd/main.js" |
        "${KIT_HEADROOM_PYTHON:-$HOME/.universal-research-agent-kit/tooling/uv-tools/headroom-ai/bin/python}" -I -B "$ROOT/headroom/runtime.py" check-opencode-config || missing=1
    fi
  else
    echo "Scoped verification: OpenCode runtime configuration was skipped with integrations/tooling."; scoped=1
  fi
}

verify_install() {
KIT_STATE_ROOT="$HOME/.universal-research-agent-kit"
TOOLING_STATE_FILE="$HOME/.universal-research-agent-kit/tooling.state"
read_tooling_state() {
  sed -n "s/^$1=//p" "$TOOLING_STATE_FILE" | sed -n '1p'
}

tooling_status_for_prompt=""
if [ -f "$TOOLING_STATE_FILE" ] && [ ! -L "$TOOLING_STATE_FILE" ]; then
  tooling_status_for_prompt="$(read_tooling_state status)"
  recorded_node_dir="$(read_tooling_state node_dir)"
  case "$recorded_node_dir" in /*) PATH="$recorded_node_dir:$PATH"; export PATH ;; esac
  KIT_CODEX_VERSION="$(read_tooling_state codex_version)"
  KIT_CLAUDE_VERSION="$(read_tooling_state claude_version)"
  KIT_OPENCODE_VERSION="$(read_tooling_state opencode_version)"
  HUMANIZER_SOURCE="$(read_tooling_state humanizer_source)"
  HUMANIZER_REVISION="$(read_tooling_state humanizer_revision)"
  HUMANIZER_CONTENT_SHA256="$(read_tooling_state humanizer_content_sha256)"
  SEQUENTIAL_THINKING_VERSION="$(read_tooling_state sequential_thinking_version)"
  [ "$KIT_CODEX_VERSION" != - ] || KIT_CODEX_VERSION=""
  [ "$KIT_CLAUDE_VERSION" != - ] || KIT_CLAUDE_VERSION=""
  [ "$KIT_OPENCODE_VERSION" != - ] || KIT_OPENCODE_VERSION=""
  if [ -n "$SEQUENTIAL_THINKING_VERSION" ] && [ "$SEQUENTIAL_THINKING_VERSION" != - ]; then
    SEQUENTIAL_THINKING_PACKAGE="@modelcontextprotocol/server-sequential-thinking@$SEQUENTIAL_THINKING_VERSION"
  fi
fi

if command -v uv >/dev/null 2>&1; then
  uv_tool_bin="$(uv tool dir --bin 2>/dev/null || true)"
  case "$uv_tool_bin" in
    /*) PATH="$uv_tool_bin:$PATH"; export PATH ;;
  esac
fi
if command -v python3 >/dev/null 2>&1; then
  python_tool_bin="$(python3 -c 'import site; print(site.getuserbase() + "/bin")' 2>/dev/null || true)"
  case "$python_tool_bin" in
    /*) PATH="$python_tool_bin:$PATH"; export PATH ;;
  esac
fi
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) PATH="$HOME/.local/bin:$PATH"; export PATH ;;
esac
# The managed bin goes on last so it wins. The three directories above can each
# hold an older same-named tool, and verifying one of those would report the
# wrong version for a correct install.
PATH="$HOME/.universal-research-agent-kit/tooling/bin:$HOME/.universal-research-agent-kit/cli/bin:$PATH"
export PATH
hash -r 2>/dev/null || true

bash "$ROOT/scripts/validate_harness.sh"

missing=0
scoped=0
check_file() {
  if [ ! -f "$1" ]; then
    echo "Missing: $1"
    missing=1
  else
    echo "OK: $1"
  fi
}
check_regular_file() {
  if [ ! -f "$1" ] || [ -L "$1" ]; then
    echo "Missing or unsafe regular file: $1"
    missing=1
  else
    echo "OK regular file: $1"
  fi
}
check_nonempty_file() {
  if [ ! -s "$1" ] || [ -L "$1" ]; then
    echo "Missing, empty, or unsafe file: $1"
    missing=1
  else
    echo "OK nonempty file: $1"
  fi
}
check_nonempty_dir() {
  local path="$1"
  if [ ! -d "$path" ] || [ -L "$path" ]; then
    echo "Missing or unsafe directory: $path"
    missing=1
  elif ! find "$path" -type f -print -quit | grep -q .; then
    echo "Empty directory: $path"
    missing=1
  else
    echo "OK nonempty directory: $path"
  fi
}
check_exact_file() {
  local path="$1"
  local expected="$2"
  local actual
  if [ ! -f "$path" ] || [ -L "$path" ]; then
    echo "Unexpected file content: $path"
    missing=1
  else
    actual="$(cat "$path")"
    if [ "$actual" != "$expected" ]; then
      echo "Unexpected file content: $path"
      missing=1
    else
      echo "OK exact file: $path"
    fi
  fi
}
check_dir() {
  if [ ! -d "$1" ]; then
    echo "Missing: $1"
    missing=1
  else
    echo "OK: $1"
  fi
}
check_executable() {
  if [ ! -x "$1" ]; then
    echo "Missing executable: $1"
    missing=1
  else
    echo "OK executable: $1"
  fi
}
check_contains() {
  local path="$1"
  local pattern="$2"
  if ! grep -q "$pattern" "$path"; then
    echo "Missing pattern in $path: $pattern"
    missing=1
  else
    echo "OK pattern in $path: $pattern"
  fi
}

check_contains_fixed() {
  local path="$1"
  local pattern="$2"
  if ! grep -Fq -- "$pattern" "$path"; then
    echo "Missing fixed pattern in $path: $pattern"
    missing=1
  else
    echo "OK fixed pattern in $path: $pattern"
  fi
}

check_same_file() {
  local source="$1"
  local installed="$2"
  if ! cmp -s "$source" "$installed"; then
    echo "Content mismatch: $installed"
    missing=1
  else
    echo "OK content: $installed"
  fi
}

check_claude_prompt() {
  local source="$1"
  local installed="$2"
  local require_graphify="${3:-}"
  local normalized

  if [ "$require_graphify" != "installed" ] && cmp -s "$source" "$installed"; then
    echo "OK content: $installed"
    return
  fi
  if [ ! -f "$installed" ]; then
    echo "Content mismatch: $installed"
    missing=1
    return
  fi

  if ! grep -Fqx -- '# graphify' "$installed" ||
    ! grep -Fqx -- '- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`' "$installed" ||
    ! grep -Fqx -- 'When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.' "$installed"; then
    echo "Missing or invalid Graphify registration: $installed"
    missing=1
    return
  fi

  # The kit text comes first; Graphify owns what it appends after it.
  normalized="$(mktemp "${TMPDIR:-/tmp}/claude-prompt.XXXXXX")"
  head -c "$(($(wc -c < "$source")))" "$installed" > "$normalized"
  if cmp -s "$source" "$normalized"; then
    echo "OK content with Graphify section: $installed"
  else
    echo "Content mismatch: $installed"
    missing=1
  fi
  rm -f "$normalized"
}

check_codex_agents() {
  local source="$1"
  local installed="$2"
  local require_graphify="${3:-}"
  local normalized

  if [ "$require_graphify" != "installed" ] && cmp -s "$source" "$installed"; then
    echo "OK content: $installed"
    return
  fi
  if [ ! -f "$installed" ]; then
    echo "Content mismatch: $installed"
    missing=1
    return
  fi

  if [ "$(grep -Fxc '# BEGIN UNIVERSAL RESEARCH AGENT KIT GRAPHIFY' "$installed" || true)" -ne 1 ] ||
    [ "$(grep -Fxc '# END UNIVERSAL RESEARCH AGENT KIT GRAPHIFY' "$installed" || true)" -ne 1 ] ||
    ! grep -Fqx -- '## Graphify' "$installed" ||
    ! grep -Fqx -- 'For an explicit graph request or an existing useful project graph, use the installed Graphify skill and its scoped query/path/explain workflow. Do not build or query a graph as a prerequisite for ordinary code reading.' "$installed" ||
    ! grep -Fqx -- 'The global Graphify skill is installed at `~/.codex/skills/graphify/SKILL.md`.' "$installed"; then
    echo "Missing or invalid Graphify Codex registration: $installed"
    missing=1
    return
  fi

  normalized="$(mktemp "${TMPDIR:-/tmp}/codex-agents.XXXXXX")"
  awk '
    { lines[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        if (lines[i] == "# BEGIN UNIVERSAL RESEARCH AGENT KIT GRAPHIFY" && start == 0) start = i
        if (lines[i] == "# END UNIVERSAL RESEARCH AGENT KIT GRAPHIFY" && start != 0) { stop = i; break }
      }
      for (i = 1; i <= NR; i++) {
        if (i >= start && i <= stop) continue
        if (i == start - 1 && lines[i] == "") continue
        print lines[i]
      }
    }
  ' "$installed" > "$normalized"
  if cmp -s "$source" "$normalized"; then
    echo "OK content with Graphify section: $installed"
  else
    echo "Content mismatch: $installed"
    missing=1
  fi
  rm -f "$normalized"
}

check_same_dir() {
  local source="$1"
  local installed="$2"
  if ! diff -qr "$source" "$installed" >/dev/null 2>&1; then
    echo "Directory content mismatch: $installed"
    missing=1
  else
    echo "OK directory content: $installed"
  fi
}

check_manifest() {
  local source_dir="$1"
  local suffix="$2"
  local manifest="$3"
  local checksum_file="$manifest.cksum"
  local expected_checksum actual_checksum
  local source name

  if [ ! -f "$manifest" ]; then
    echo "Missing ownership manifest: $manifest"
    missing=1
    return
  fi

  if [ -L "$manifest" ]; then
    echo "Unsafe ownership manifest: $manifest"
    missing=1
    return
  fi

  if [ ! -f "$checksum_file" ] || [ -L "$checksum_file" ]; then
    echo "Missing or unsafe manifest checksum: $checksum_file"
    missing=1
  else
    expected_checksum="$(cat "$checksum_file")"
    actual_checksum="$(cksum "$manifest" | awk '{ print $1 ":" $2 }')"
    if [ "$expected_checksum" != "$actual_checksum" ]; then
      echo "Manifest checksum mismatch: $manifest"
      missing=1
    fi
  fi

  for source in "$source_dir"/*"$suffix"; do
    [ -e "$source" ] || continue
    name="${source##*/}"
    if ! grep -Fqx "$name" "$manifest"; then
      echo "Missing manifest entry in $manifest: $name"
      missing=1
    fi
  done

  while IFS= read -r name || [ -n "$name" ]; do
    if [ "$name" = humanizer ] && [ "$source_dir" = "$ROOT/skills" ] &&
        [ -n "${HUMANIZER_REVISION:-}" ] && [ "$HUMANIZER_REVISION" != - ]; then continue; fi
    if [ -z "$name" ] || [ ! -e "$source_dir/$name" ]; then
      echo "Unexpected manifest entry in $manifest: $name"
      missing=1
    fi
  done < "$manifest"
}
check_file "$HOME/.claude/CLAUDE.md"
check_dir "$HOME/.claude/agents"
check_dir "$HOME/.claude/skills"

if [ "$tooling_status_for_prompt" = installed ]; then
  kit_context_run check || { echo "Codex context defaults differ from the requested 1M/800k policy."; missing=1; }
else
if ! awk '
  /^\[/ { section = ($0 == "[features.context_management]") }
  section && /^[[:space:]]*experimental_mode[[:space:]]*=[[:space:]]*true([[:space:]]*(#.*)?)$/ { found++ }
  END { exit found != 1 }
' "$HOME/.codex/config.toml"; then
  echo "Missing or disabled context_management.experimental_mode"
  missing=1
fi
fi
check_file "$HOME/.codex/AGENTS.md"
check_dir "$HOME/.codex/agents"
check_dir "$HOME/.agents/skills"

if [ "${WITH_STATUSLINE:-1}" -eq 0 ]; then
  echo "Scoped verification: statuslines explicitly skipped by --without-statusline."
  scoped=1
else
  check_file "$HOME/.universal-research-agent-kit/statusline.state"
  check_file "$HOME/.claude/settings.json"
  check_file "$HOME/.claude/statusline.sh"
  if [ ! -f "$HOME/.universal-research-agent-kit/statusline.state" ] ||
      ! grep -Fxq 'enabled=1' "$HOME/.universal-research-agent-kit/statusline.state" ||
      ! command -v jq >/dev/null 2>&1 || ! kit_statusline_run check; then
    echo "Statusline verification failed (configuration, executable script or jq)."
    missing=1
  fi
fi

for source in "$ROOT/claude-code/agents"/*.md; do
  check_same_file "$source" "$HOME/.claude/agents/${source##*/}"
done

for source in "$ROOT/codex/agents"/*.toml; do
  check_same_file "$source" "$HOME/.codex/agents/${source##*/}"
done

for source in "$ROOT/skills"/*; do
  [ -d "$source" ] || continue
  check_same_dir "$source" "$HOME/.claude/skills/${source##*/}"
done
for source in "$ROOT/skills"/*; do
  [ -d "$source" ] || continue
  check_same_dir "$source" "$HOME/.agents/skills/${source##*/}"
done

check_executable "$HOME/.claude/skills/resource-aware-orchestration/scripts/detect_resources.sh"
check_executable "$HOME/.agents/skills/resource-aware-orchestration/scripts/detect_resources.sh"
check_executable "$HOME/.claude/skills/resource-aware-orchestration/scripts/run_codex_agent.sh"
check_executable "$HOME/.agents/skills/resource-aware-orchestration/scripts/run_codex_agent.sh"

check_claude_prompt "$ROOT/claude-code/CLAUDE.md" "$HOME/.claude/CLAUDE.md" "$tooling_status_for_prompt"
check_codex_agents "$ROOT/codex/AGENTS.md" "$HOME/.codex/AGENTS.md" "$tooling_status_for_prompt"

check_manifest "$ROOT/claude-code/agents" ".md" "$HOME/.universal-research-agent-kit/manifests/claude-agents"
check_manifest "$ROOT/codex/agents" ".toml" "$HOME/.universal-research-agent-kit/manifests/codex-agents"
check_manifest "$ROOT/skills" "" "$HOME/.universal-research-agent-kit/manifests/claude-skills"
check_manifest "$ROOT/skills" "" "$HOME/.universal-research-agent-kit/manifests/codex-skills"

check_file "$HOME/.config/git/ignore"
check_contains "$HOME/.config/git/ignore" "BEGIN UNIVERSAL RESEARCH AGENT KIT"
check_contains "$HOME/.config/git/ignore" "END UNIVERSAL RESEARCH AGENT KIT"

check_tool_command() {
  local command_name="$1"
  local command_path

  command_path="$(command -v "$command_name" 2>/dev/null || true)"
  if [ -n "$command_path" ]; then
    echo "OK command: $command_name ($command_path)"
  elif [ -x "$HOME/.universal-research-agent-kit/tooling/bin/$command_name" ]; then
    echo "OK command: $command_name ($HOME/.universal-research-agent-kit/tooling/bin/$command_name)"
  elif [ -x "$HOME/.local/bin/$command_name" ]; then
    echo "OK command: $command_name ($HOME/.local/bin/$command_name)"
  else
    echo "Missing command: $command_name"
    missing=1
  fi
}

check_tool_version() {
  tool_version_matches "$1" "$2" || { echo "Wrong version for $1; expected $2"; missing=1; }
}

check_graphify_skill_layout() {
  local skill_root="$1"

  check_regular_file "$skill_root/SKILL.md"
  check_nonempty_file "$skill_root/SKILL.md"
  check_contains_fixed "$skill_root/SKILL.md" "graphify"
  check_exact_file "$skill_root/.graphify_version" "$graphify_version"
  check_nonempty_dir "$skill_root/references"
}

if [ ! -f "$TOOLING_STATE_FILE" ] || [ -L "$TOOLING_STATE_FILE" ]; then
  echo "Missing tooling state; run sh install.sh."
  missing=1
elif [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_TOOLING:-0}" = 1 ]; then
  echo "Scoped verification: tooling explicitly skipped by environment."
  scoped=1
else
  tooling_status="$(read_tooling_state status)"
  case "$tooling_status" in
    installed)
  "$HOME/.universal-research-agent-kit/tooling/uv-tools/headroom-ai/bin/python" -I -B "$ROOT/skills/crucible/scripts/engine.py" check || missing=1
      graphify_state="$(read_tooling_state graphify)"
      headroom_state="$(read_tooling_state headroom)"
      wrapper_state="$(read_tooling_state headroom_wrapper)"
      case "$graphify_state" in
        present|installed) echo "Graphify: $graphify_state" ;;
        *) echo "Unknown Graphify state: $graphify_state"; missing=1 ;;
      esac
      case "$headroom_state" in
        present|installed) echo "Headroom: $headroom_state" ;;
        *) echo "Unknown Headroom state: $headroom_state"; missing=1 ;;
      esac
      [ "$wrapper_state" = "installed" ] || {
        echo "Unknown Headroom wrapper state: $wrapper_state"
        missing=1
      }
      graphify_version="$(read_tooling_state graphify_version)"
      headroom_version="$(read_tooling_state headroom_version)"
      tool_bin_dir="$(read_tooling_state tool_bin_dir)"
      [ "$tool_bin_dir" = "$HOME/.universal-research-agent-kit/tooling/bin" ] || {
        echo "Unexpected tooling bin directory: $tool_bin_dir"
        missing=1
      }
      check_tool_command graphify
      check_tool_command headroom
      check_tool_version graphify "$graphify_version"
      check_tool_version headroom "$headroom_version"
      "$HOME/.universal-research-agent-kit/tooling/uv-tools/graphifyy/bin/python" -I -B \
        "$ROOT/headroom/runtime.py" environment graphifyy "$graphify_version" || missing=1
      check_graphify_skill_layout "$HOME/.claude/skills/graphify"
      check_graphify_skill_layout "$HOME/.codex/skills/graphify"
      check_same_file "$ROOT/headroom/auto-wrap.sh" "$HOME/.config/headroom/auto-wrap.sh"
      check_same_file "$ROOT/headroom/runtime.py" "$HOME/.config/headroom/runtime.py"
      runtime_python="$HOME/.universal-research-agent-kit/tooling/uv-tools/headroom-ai/bin/python"
      if [ -x "$runtime_python" ]; then
        "$runtime_python" -I -B "$ROOT/headroom/runtime.py" dependencies "$headroom_version" || missing=1
        "$runtime_python" -I -B "$ROOT/headroom/runtime.py" check || missing=1
      else
        echo "Missing kit Headroom interpreter: $runtime_python"; missing=1
      fi
      check_file "$HOME/.zshrc"
      check_file "$HOME/.bashrc"
      if [ -f "$HOME/.zshrc" ]; then
        check_contains_fixed "$HOME/.zshrc" '*:"$HOME/.universal-research-agent-kit/tooling/bin":*) ;;'
        check_contains_fixed "$HOME/.zshrc" '[ -f "$HOME/.config/headroom/auto-wrap.sh" ] && source "$HOME/.config/headroom/auto-wrap.sh"'
      fi
      if [ -f "$HOME/.bashrc" ]; then
        check_contains_fixed "$HOME/.bashrc" '*:"$HOME/.universal-research-agent-kit/tooling/bin":*) ;;'
        check_contains_fixed "$HOME/.bashrc" '[ -f "$HOME/.config/headroom/auto-wrap.sh" ] && source "$HOME/.config/headroom/auto-wrap.sh"'
      fi
      ;;
    skipped_env)
      echo "Scoped verification: Graphify and Headroom were explicitly skipped."
      scoped=1
      ;;
    *)
      echo "Unknown tooling state: $tooling_status"
      missing=1
      ;;
  esac
fi

# Verify each host against its recorded installation or preservation outcome.
STATE_FILE="$HOME/.universal-research-agent-kit/integrations.state"
KIT_MARKETPLACE_ROOT="$HOME/.universal-research-agent-kit/marketplaces"

# Kit-owned Ponytail requires the installed marketplace manifest's path and version.
KIT_PONYTAIL_MANIFEST=""
KIT_PONYTAIL_PATH=""
KIT_PONYTAIL_VERSION=""
for ponytail_manifest in "$KIT_MARKETPLACE_ROOT"/ponytail-*/ponytail/.claude-plugin/plugin.json; do
  [ -f "$ponytail_manifest" ] || continue
  if [ -z "$KIT_PONYTAIL_MANIFEST" ] || [ "$ponytail_manifest" -nt "$KIT_PONYTAIL_MANIFEST" ]; then
    KIT_PONYTAIL_MANIFEST="$ponytail_manifest"
  fi
done
if [ -n "$KIT_PONYTAIL_MANIFEST" ]; then
  KIT_PONYTAIL_PATH="${KIT_PONYTAIL_MANIFEST%/.claude-plugin/plugin.json}"
  if command -v node >/dev/null 2>&1; then
    KIT_PONYTAIL_VERSION="$(node -e '
      const fs = require("fs");
      const manifest = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      process.stdout.write(manifest.version || "");
    ' "$KIT_PONYTAIL_MANIFEST")"
  fi
fi

read_state() {
  sed -n "s/^$1=//p" "$STATE_FILE" | sed -n '1p'
}

codex_usable() { command -v codex >/dev/null 2>&1 && command -v node >/dev/null 2>&1; }
claude_usable() { command -v claude >/dev/null 2>&1 && command -v node >/dev/null 2>&1; }

PONYTAIL_MARKETPLACE_ROOT="$KIT_MARKETPLACE_ROOT"
PONYTAIL_VERSION="$KIT_PONYTAIL_VERSION"
codex_ponytail_kit_enabled() {
  [ -n "$KIT_PONYTAIL_VERSION" ] && [ -n "$KIT_PONYTAIL_PATH" ] &&
    codex_plugin_exact_enabled ponytail@ponytail "$KIT_PONYTAIL_VERSION" 1 "$KIT_PONYTAIL_PATH"
}
codex_ponytail_kit_owned_present() { codex_plugin_installed ponytail@ponytail && codex_plugin_kit_owned ponytail@ponytail; }
codex_lazycodex_installed() { codex_plugin_installed omo@sisyphuslabs; }
codex_lazycodex_enabled() { case "$(codex_plugin_status omo@sisyphuslabs)" in *' enabled') return 0;; *) return 1;; esac; }
claude_ponytail_kit_enabled() { [ -n "$KIT_PONYTAIL_VERSION" ] && claude_plugin_exact_enabled; }
claude_ponytail_pinned_installed() { claude_plugin_installed && claude_ponytail_marketplace_ownership; }
claude_ponytail_installed() { claude_plugin_installed; }

if [ ! -f "$STATE_FILE" ] || [ -L "$STATE_FILE" ]; then
  echo "Missing integrations state; run sh install.sh."
  missing=1
elif [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS:-0}" = "1" ]; then
  echo "Scoped verification: integrations explicitly skipped by environment."
  scoped=1
else
  requested_profile="$(read_state requested_profile)"
  if ! verify_native_clis; then
    echo "Official native CLI installation or kit launcher is missing/broken; rerun sh install.sh."
    missing=1
  fi
  echo "Integrations profile: ${requested_profile:-unknown}"
  case "$requested_profile" in none|ponytail) ;; *) echo "Unknown requested integration profile"; missing=1 ;; esac

  if [ "$(read_state codex_ponytail)" != skipped_env ] || [ "$(read_state claude_ponytail)" != skipped_env ]; then
    if codex_usable && claude_usable; then
      validate_plugin_listings
    else
      echo "Required integration verification CLI unavailable (Codex, Claude or Node.js)"
      missing=1
    fi
  fi
  codex_ponytail_state="$(read_state codex_ponytail)"
  case "$codex_ponytail_state" in
    installed_kit_owned)
      if codex_usable && codex_ponytail_kit_enabled; then
        echo "OK Codex integration: Ponytail (kit-owned)"
      else
        echo "Missing Codex integration: Ponytail"
        missing=1
      fi
      ;;
    preserved_user_owned)
      if [ "$requested_profile" = ponytail ]; then
        codex_usable && codex_plugin_exact_enabled ponytail@ponytail "" || {
          echo "Required user-owned Codex Ponytail is missing or disabled"; missing=1;
        }
      fi
      echo "Codex integration: user-owned Ponytail source preserved"
      ;;
    removed_legacy|not_requested)
      [ "$requested_profile" != ponytail ] || { echo "Required Codex Ponytail was not installed"; missing=1; }
      if codex_usable && codex_ponytail_kit_owned_present; then
        echo "Kit-owned Codex Ponytail is still installed despite state '$codex_ponytail_state'."
        missing=1
      else
        echo "OK Codex integration: Ponytail $codex_ponytail_state"
      fi
      ;;
    skipped_env)
      scoped=1
      echo "Codex Ponytail: $codex_ponytail_state"
      ;;
    unverified_no_node)
      echo "Codex Ponytail state is unverified"; missing=1
      ;;
    *)
      echo "Unknown Codex Ponytail state: $codex_ponytail_state"
      missing=1
      ;;
  esac

  claude_ponytail_state="$(read_state claude_ponytail)"
  case "$claude_ponytail_state" in
    installed_kit_owned)
      if claude_usable && claude_ponytail_kit_enabled; then
        echo "OK Claude integration: Ponytail (kit-owned)"
      else
        echo "Missing Claude integration: Ponytail"
        missing=1
      fi
      ;;
    preserved_user_owned)
      if [ "$requested_profile" = ponytail ]; then
        claude_usable && claude_plugin_exact_enabled "" || {
          echo "Required user-owned Claude Ponytail is missing or disabled"; missing=1;
        }
      fi
      echo "Claude integration: user-owned Ponytail source preserved"
      ;;
    removed_legacy|not_requested)
      [ "$requested_profile" != ponytail ] || { echo "Required Claude Ponytail was not installed"; missing=1; }
      if claude_usable && claude_ponytail_pinned_installed; then
        echo "Kit-installed Claude Ponytail $KIT_PONYTAIL_VERSION is present despite state '$claude_ponytail_state'; run 'sh install.sh' to reconcile."
        missing=1
      elif claude_usable && claude_ponytail_installed; then
        echo "OK Claude integration: non-pinned user-owned Ponytail detected and preserved (state '$claude_ponytail_state')."
      else
        echo "OK Claude integration: Ponytail $claude_ponytail_state"
      fi
      ;;
    skipped_env)
      scoped=1
      echo "Claude Ponytail: $claude_ponytail_state"
      ;;
    unverified_no_node)
      echo "Claude Ponytail state is unverified"; missing=1
      ;;
    *)
      echo "Unknown Claude Ponytail state: $claude_ponytail_state"
      missing=1
      ;;
  esac

  codex_lazycodex_state="$(read_state codex_lazycodex)"
  case "$codex_lazycodex_state" in
    installed_kit_owned)
      echo "State records a kit-installed LazyCodex, which this kit no longer installs; run 'sh install.sh' to remove it."
      missing=1
      ;;
    removed_legacy)
      if codex_usable && codex_lazycodex_installed; then
        echo "LazyCodex is still installed but the profile is '$requested_profile'; run 'sh install.sh' to migrate."
        missing=1
      else
        echo "OK Codex integration: LazyCodex removed"
      fi
      ;;
    disabled_legacy|not_requested|user_owned_warned)
      if codex_usable && codex_lazycodex_enabled; then
        echo "LazyCodex is enabled but the profile is '$requested_profile'; run 'sh install.sh' to migrate."
        missing=1
      else
        echo "OK Codex integration: LazyCodex $codex_lazycodex_state"
      fi
      ;;
    skipped_env)
      scoped=1
      echo "Codex LazyCodex: $codex_lazycodex_state"
      ;;
    unverified_no_node)
      echo "Codex LazyCodex state is unverified"; missing=1
      ;;
    *)
      echo "Unknown Codex LazyCodex state: $codex_lazycodex_state"
      missing=1
      ;;
  esac

  codex_seqthink_state="$(read_state codex_sequential_thinking)"
  case "$codex_seqthink_state" in
    registered_kit|repinned_kit|preexisting)
      if ! command -v codex >/dev/null 2>&1 || ! (cd "$HOME" && codex mcp get sequential_thinking) | mcp_package_matches; then
        echo "Missing Codex MCP: sequential_thinking (state '$codex_seqthink_state')"
        missing=1
      else
        echo "OK Codex MCP: sequential_thinking ($codex_seqthink_state)"
      fi
      ;;
    skipped_env)
      scoped=1
      echo "Codex sequential_thinking MCP: ${codex_seqthink_state:-not_recorded}"
      ;;
    *)
      echo "Unknown Codex sequential_thinking state: $codex_seqthink_state"
      missing=1
      ;;
  esac

  claude_seqthink_state="$(read_state claude_sequential_thinking)"
  case "$claude_seqthink_state" in
    registered_kit|repinned_kit|preexisting)
      if ! command -v claude >/dev/null 2>&1 || ! claude mcp get sequential-thinking | mcp_package_matches; then
        echo "Missing Claude MCP: sequential-thinking (state '$claude_seqthink_state')"
        missing=1
      else
        echo "OK Claude MCP: sequential-thinking ($claude_seqthink_state)"
      fi
      ;;
    skipped_env)
      scoped=1
      echo "Claude sequential-thinking MCP: ${claude_seqthink_state:-not_recorded}"
      ;;
    *)
      echo "Unknown Claude sequential-thinking state: $claude_seqthink_state"
      missing=1
      ;;
  esac


fi

verify_platform_additions
if [ "$missing" -ne 0 ]; then
  echo "Install verification failed."
  exit 1
fi

if [ "$scoped" -eq 1 ]; then
  echo "Scoped verification passed; explicitly skipped components are not verified."
else
  echo "Full install verification passed. Restart Claude Code, Codex and OpenCode sessions."
fi

}
