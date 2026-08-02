#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

EXPECTED_GRAPHIFY_VERSION="0.9.32"
EXPECTED_HEADROOM_VERSION="0.33.0"
TOOLING_STATE_FILE="$HOME/.universal-research-agent-kit/tooling.state"
read_tooling_state() {
  sed -n "s/^$1=//p" "$TOOLING_STATE_FILE" | sed -n '1p'
}

tooling_status_for_prompt=""
if [ -f "$TOOLING_STATE_FILE" ] && [ ! -L "$TOOLING_STATE_FILE" ]; then
  tooling_status_for_prompt="$(read_tooling_state status)"
fi

case ":$PATH:" in
  *":$HOME/.universal-research-agent-kit/tooling/bin:"*) ;;
  *) PATH="$HOME/.universal-research-agent-kit/tooling/bin:$PATH"; export PATH ;;
esac

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

bash "$ROOT/scripts/validate_harness.sh"

missing=0
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

  normalized="$(mktemp "${TMPDIR:-/tmp}/claude-prompt.XXXXXX")"
  awk '$0 == "# graphify" { exit } { print }' "$installed" > "$normalized"
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
    ! grep -Fqx -- 'For codebase, architecture, file-relationship, or project-content questions, use the installed Graphify skill and query the graph before reading the repository broadly. Prefer `graphify query "<question>"` and use the skill'"'"'s scoped query/path/explain workflow.' "$installed" ||
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
    if [ -z "$name" ] || [ ! -e "$source_dir/$name" ]; then
      echo "Unexpected manifest entry in $manifest: $name"
      missing=1
    fi
  done < "$manifest"
}
check_file "$HOME/.claude/CLAUDE.md"
check_dir "$HOME/.claude/agents"
check_dir "$HOME/.claude/skills"

check_file "$HOME/.codex/AGENTS.md"
check_dir "$HOME/.codex/agents"
check_dir "$HOME/.agents/skills"

for source in "$ROOT/claude-code/agents"/*.md; do
  check_same_file "$source" "$HOME/.claude/agents/${source##*/}"
done

for source in "$ROOT/codex/agents"/*.toml; do
  check_same_file "$source" "$HOME/.codex/agents/${source##*/}"
done

for source in "$ROOT/claude-code/skills"/*; do
  [ -d "$source" ] || continue
  check_same_dir "$source" "$HOME/.claude/skills/${source##*/}"
done
for source in "$ROOT/codex/skills"/*; do
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
check_manifest "$ROOT/claude-code/skills" "" "$HOME/.universal-research-agent-kit/manifests/claude-skills"
check_manifest "$ROOT/codex/skills" "" "$HOME/.universal-research-agent-kit/manifests/codex-skills"

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
  local command_name="$1"
  local expected_version="$2"
  local candidate
  local output

  output="$("$command_name" --version 2>&1 || true)"
  while IFS= read -r candidate; do
    if [ "$candidate" = "$expected_version" ]; then
      echo "OK version: $command_name $expected_version"
      return
    fi
  done <<EOF
$(printf '%s\n' "$output" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z]+)*' || true)
EOF
  echo "Wrong version for $command_name; expected $expected_version"
  missing=1
}

check_graphify_skill_layout() {
  local skill_root="$1"

  check_regular_file "$skill_root/SKILL.md"
  check_nonempty_file "$skill_root/SKILL.md"
  check_contains_fixed "$skill_root/SKILL.md" "graphify"
  check_exact_file "$skill_root/.graphify_version" "$EXPECTED_GRAPHIFY_VERSION"
  check_nonempty_dir "$skill_root/references"
}

if [ ! -f "$TOOLING_STATE_FILE" ] || [ -L "$TOOLING_STATE_FILE" ]; then
  echo "No tooling state recorded (pre-tooling install)."
else
  tooling_status="$(read_tooling_state status)"
  case "$tooling_status" in
    installed)
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
      [ "$graphify_version" = "$EXPECTED_GRAPHIFY_VERSION" ] || {
        echo "Unexpected Graphify state version: $graphify_version"
        missing=1
      }
      [ "$headroom_version" = "$EXPECTED_HEADROOM_VERSION" ] || {
        echo "Unexpected Headroom state version: $headroom_version"
        missing=1
      }
      [ "$tool_bin_dir" = "$HOME/.universal-research-agent-kit/tooling/bin" ] || {
        echo "Unexpected tooling bin directory: $tool_bin_dir"
        missing=1
      }
      check_tool_command graphify
      check_tool_command headroom
      check_tool_version graphify "$graphify_version"
      check_tool_version headroom "$headroom_version"
      check_graphify_skill_layout "$HOME/.claude/skills/graphify"
      check_graphify_skill_layout "$HOME/.codex/skills/graphify"
      check_same_file "$ROOT/headroom/auto-wrap.sh" "$HOME/.config/headroom/auto-wrap.sh"
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
      echo "Skipped Graphify and Headroom verification by explicit environment setting."
      ;;
    *)
      echo "Unknown tooling state: $tooling_status"
      missing=1
      ;;
  esac
fi

# Integration checks follow the per-host states the installer recorded, so a
# preserved user-owned Ponytail or a disabled legacy LazyCodex verifies as
# the intended outcome rather than as a missing kit install.
STATE_FILE="$HOME/.universal-research-agent-kit/integrations.state"
KIT_MARKETPLACE_ROOT="$HOME/.universal-research-agent-kit/marketplaces"
KIT_PONYTAIL_PATH="$KIT_MARKETPLACE_ROOT/ponytail-bc9ee949d5f439e8b9f3bb92c6d6d3d1e6ebd324/ponytail"

read_state() {
  sed -n "s/^$1=//p" "$STATE_FILE" | sed -n '1p'
}

codex_usable() { command -v codex >/dev/null 2>&1 && command -v node >/dev/null 2>&1; }
claude_usable() { command -v claude >/dev/null 2>&1 && command -v node >/dev/null 2>&1; }

codex_ponytail_kit_enabled() {
  codex plugin list --json | EXPECTED_PONYTAIL_PATH="$KIT_PONYTAIL_PATH" node -e '
    const plugins = JSON.parse(require("fs").readFileSync(0, "utf8")).installed || [];
    const ponytail = plugins.find((item) => item.pluginId === "ponytail@ponytail");
    const valid = ponytail && ponytail.version === "4.8.4" &&
      ponytail.installed === true && ponytail.enabled === true &&
      ponytail.source?.source === "local" &&
      ponytail.source.path === process.env.EXPECTED_PONYTAIL_PATH;
    process.exit(valid ? 0 : 1);
  '
}

codex_ponytail_kit_owned_present() {
  codex plugin list --json | KIT_MARKETPLACE_ROOT="$KIT_MARKETPLACE_ROOT" node -e '
    const plugins = JSON.parse(require("fs").readFileSync(0, "utf8")).installed || [];
    const ponytail = plugins.find((item) => item.pluginId === "ponytail@ponytail");
    const owned = ponytail && ponytail.installed === true &&
      ponytail.source?.source === "local" &&
      typeof ponytail.source.path === "string" &&
      ponytail.source.path.startsWith(process.env.KIT_MARKETPLACE_ROOT + "/");
    process.exit(owned ? 0 : 1);
  '
}

codex_lazycodex_pinned_enabled() {
  codex plugin list --json | node -e '
    const plugins = JSON.parse(require("fs").readFileSync(0, "utf8")).installed || [];
    const lazy = plugins.find((item) => item.pluginId === "omo@sisyphuslabs");
    process.exit(lazy && lazy.version === "4.17.0" && lazy.installed === true &&
      lazy.enabled === true ? 0 : 1);
  '
}

# Outside the ultra profile any enabled LazyCodex version conflicts with the
# harness review budget, so the check is version-agnostic.
codex_lazycodex_enabled() {
  codex plugin list --json | node -e '
    const plugins = JSON.parse(require("fs").readFileSync(0, "utf8")).installed || [];
    const lazy = plugins.find((item) => item.pluginId === "omo@sisyphuslabs");
    process.exit(lazy && lazy.installed === true && lazy.enabled === true ? 0 : 1);
  '
}

claude_ponytail_kit_enabled() {
  claude plugin list --json | node -e '
    const plugins = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const ponytail = plugins.find((item) =>
      item.id === "ponytail@ponytail" && item.scope === "user");
    process.exit(ponytail && ponytail.version === "4.8.4" &&
      ponytail.enabled === true ? 0 : 1);
  '
}

# Claude plugin listings expose no source path, so ownership uses the same
# heuristic as LazyCodex: only the kit-pinned version counts as a kit remnant.
claude_ponytail_pinned_installed() {
  claude plugin list --json | node -e '
    const plugins = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const ponytail = plugins.find((item) =>
      item.id === "ponytail@ponytail" && item.scope === "user");
    process.exit(ponytail && ponytail.version === "4.8.4" ? 0 : 1);
  '
}

claude_ponytail_installed() {
  claude plugin list --json | node -e '
    const plugins = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const ponytail = plugins.find((item) =>
      item.id === "ponytail@ponytail" && item.scope === "user");
    process.exit(ponytail ? 0 : 1);
  '
}

if [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS:-0}" = "1" ]; then
  echo "Skipped integration verification by explicit environment setting."
elif [ ! -f "$STATE_FILE" ] || [ -L "$STATE_FILE" ]; then
  echo "No integrations state recorded (pre-migration install)."
  if codex_usable; then
    if codex_lazycodex_enabled; then
      echo "LazyCodex is still enabled; run 'sh install.sh' to migrate."
      missing=1
    else
      echo "OK integrations: no enabled LazyCodex detected"
    fi
  else
    echo "Integrations unverified: Codex CLI or Node.js unavailable."
  fi
else
  requested_profile="$(read_state requested_profile)"
  echo "Integrations profile: ${requested_profile:-unknown}"

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
      echo "OK Codex integration: user-owned Ponytail preserved"
      ;;
    removed_legacy|not_requested)
      if codex_usable && codex_ponytail_kit_owned_present; then
        echo "Kit-owned Codex Ponytail is still installed despite state '$codex_ponytail_state'."
        missing=1
      else
        echo "OK Codex integration: Ponytail $codex_ponytail_state"
      fi
      ;;
    host_unavailable|skipped_env)
      echo "Codex Ponytail: $codex_ponytail_state"
      ;;
    unverified_no_node)
      echo "Warning: Codex Ponytail state is unverified (Node.js was unavailable at install time)."
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
      echo "OK Claude integration: user-owned Ponytail preserved"
      ;;
    removed_legacy|not_requested)
      if claude_usable && claude_ponytail_pinned_installed; then
        echo "Kit-pinned Claude Ponytail 4.8.4 is installed despite state '$claude_ponytail_state'; run 'sh install.sh' to reconcile."
        missing=1
      elif claude_usable && claude_ponytail_installed; then
        echo "OK Claude integration: non-pinned user-owned Ponytail detected and preserved (state '$claude_ponytail_state')."
      else
        echo "OK Claude integration: Ponytail $claude_ponytail_state"
      fi
      ;;
    host_unavailable|skipped_env)
      echo "Claude Ponytail: $claude_ponytail_state"
      ;;
    unverified_no_node)
      echo "Warning: Claude Ponytail state is unverified (Node.js was unavailable at install time)."
      ;;
    *)
      echo "Unknown Claude Ponytail state: $claude_ponytail_state"
      missing=1
      ;;
  esac

  codex_lazycodex_state="$(read_state codex_lazycodex)"
  case "$codex_lazycodex_state" in
    installed_kit_owned)
      if codex_usable && codex_lazycodex_pinned_enabled; then
        echo "OK Codex integration: LazyCodex (ultra profile)"
      else
        echo "Missing Codex integration: LazyCodex"
        missing=1
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
    host_unavailable|skipped_env)
      echo "Codex LazyCodex: $codex_lazycodex_state"
      ;;
    unverified_no_node)
      echo "Warning: Codex LazyCodex state is unverified (Node.js was unavailable at install time)."
      ;;
    *)
      echo "Unknown Codex LazyCodex state: $codex_lazycodex_state"
      missing=1
      ;;
  esac

  codex_seqthink_state="$(read_state codex_sequential_thinking)"
  case "$codex_seqthink_state" in
    registered_kit|preexisting)
      if command -v codex >/dev/null 2>&1 && ! (cd "$HOME" && codex mcp get sequential_thinking >/dev/null 2>&1); then
        echo "Missing Codex MCP: sequential_thinking (state '$codex_seqthink_state')"
        missing=1
      else
        echo "OK Codex MCP: sequential_thinking ($codex_seqthink_state)"
      fi
      ;;
    host_unavailable|skipped_env|unverified_no_node|"")
      echo "Codex sequential_thinking MCP: ${codex_seqthink_state:-not_recorded}"
      ;;
    *)
      echo "Unknown Codex sequential_thinking state: $codex_seqthink_state"
      missing=1
      ;;
  esac

  claude_seqthink_state="$(read_state claude_sequential_thinking)"
  case "$claude_seqthink_state" in
    registered_kit|preexisting)
      if command -v claude >/dev/null 2>&1 && ! claude mcp get sequential-thinking >/dev/null 2>&1; then
        echo "Missing Claude MCP: sequential-thinking (state '$claude_seqthink_state')"
        missing=1
      else
        echo "OK Claude MCP: sequential-thinking ($claude_seqthink_state)"
      fi
      ;;
    host_unavailable|skipped_env|unverified_no_node|"")
      echo "Claude sequential-thinking MCP: ${claude_seqthink_state:-not_recorded}"
      ;;
    *)
      echo "Unknown Claude sequential-thinking state: $claude_seqthink_state"
      missing=1
      ;;
  esac

  # LazyCodex installs raise agents.max_threads far above the harness
  # ceiling; outside ultra the installer caps it at 6.
  if [ "$requested_profile" != "ultra" ] && command -v codex >/dev/null 2>&1 &&
     [ -f "$HOME/.codex/config.toml" ] && [ ! -L "$HOME/.codex/config.toml" ]; then
    agents_max_threads="$(awk '$0 == "[agents]" { s = 1; next } /^\[/ { s = 0 } s && /^max_threads[ \t]*=/ { sub(/^max_threads[ \t]*=[ \t]*/, ""); print; exit }' "$HOME/.codex/config.toml")"
    case "$agents_max_threads" in
      ''|*[!0-9]*)
        echo "OK Codex config: no numeric agents.max_threads override"
        ;;
      *)
        if [ "$agents_max_threads" -gt 6 ]; then
          echo "Codex agents.max_threads is $agents_max_threads (harness ceiling is 6); run 'sh install.sh' to cap it."
          missing=1
        else
          echo "OK Codex config: agents.max_threads = $agents_max_threads"
        fi
        ;;
    esac
  fi
fi

if [ "$missing" -ne 0 ]; then
  echo "Install verification failed."
  exit 1
fi

echo "Install verification passed. Restart Claude Code and Codex sessions."
