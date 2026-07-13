#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

check_same_file "$ROOT/claude-code/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
check_same_file "$ROOT/codex/AGENTS.md" "$HOME/.codex/AGENTS.md"

check_manifest "$ROOT/claude-code/agents" ".md" "$HOME/.universal-research-agent-kit/manifests/claude-agents"
check_manifest "$ROOT/codex/agents" ".toml" "$HOME/.universal-research-agent-kit/manifests/codex-agents"
check_manifest "$ROOT/claude-code/skills" "" "$HOME/.universal-research-agent-kit/manifests/claude-skills"
check_manifest "$ROOT/codex/skills" "" "$HOME/.universal-research-agent-kit/manifests/codex-skills"

check_file "$HOME/.config/git/ignore"
check_contains "$HOME/.config/git/ignore" "BEGIN UNIVERSAL RESEARCH AGENT KIT"
check_contains "$HOME/.config/git/ignore" "END UNIVERSAL RESEARCH AGENT KIT"

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
