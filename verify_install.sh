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

# Integration checks follow the profile the installer recorded. The default
# core install manages no plugins and never inspects or removes user MCPs.
integrations_profile="none"
profile_file="$HOME/.universal-research-agent-kit/integrations.profile"
if [ -f "$profile_file" ] && [ ! -L "$profile_file" ]; then
  integrations_profile="$(sed -n '1p' "$profile_file")"
fi
if [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS:-0}" = "1" ]; then
  integrations_profile="none"
fi

case "$integrations_profile" in
  ponytail|ultra)
    if command -v codex >/dev/null 2>&1; then
      if ! codex plugin list --json | EXPECTED_PONYTAIL_PATH="$HOME/.universal-research-agent-kit/marketplaces/ponytail-bc9ee949d5f439e8b9f3bb92c6d6d3d1e6ebd324/ponytail" node -e '
        const plugins = JSON.parse(require("fs").readFileSync(0, "utf8")).installed || [];
        const ponytail = plugins.find((item) => item.pluginId === "ponytail@ponytail");
        const valid = ponytail && ponytail.version === "4.8.4" &&
          ponytail.installed === true && ponytail.enabled === true &&
          ponytail.source?.source === "local" &&
          ponytail.source.path === process.env.EXPECTED_PONYTAIL_PATH;
        process.exit(valid ? 0 : 1);
      '; then
        echo "Missing Codex integration: Ponytail"
        missing=1
      else
        echo "OK Codex integration: Ponytail"
      fi
      if [ "$integrations_profile" = "ultra" ]; then
        if ! codex plugin list --json | node -e '
          const plugins = JSON.parse(require("fs").readFileSync(0, "utf8")).installed || [];
          const lazy = plugins.find((item) => item.pluginId === "omo@sisyphuslabs");
          process.exit(lazy && lazy.version === "4.17.0" && lazy.installed === true &&
            lazy.enabled === true ? 0 : 1);
        '; then
          echo "Missing Codex integration: LazyCodex"
          missing=1
        else
          echo "OK Codex integration: LazyCodex"
        fi
      fi
    fi

    if command -v claude >/dev/null 2>&1; then
      if ! claude plugin list --json | node -e '
        const plugins = JSON.parse(require("fs").readFileSync(0, "utf8"));
        const ponytail = plugins.find((item) =>
          item.id === "ponytail@ponytail" && item.scope === "user");
        process.exit(ponytail && ponytail.version === "4.8.4" &&
          ponytail.enabled === true ? 0 : 1);
      '; then
        echo "Missing Claude integration: Ponytail"
        missing=1
      else
        echo "OK Claude integration: Ponytail"
      fi
    fi
    ;;
  none)
    echo "OK integrations: none selected (core-only install)"
    ;;
  *)
    echo "Unknown integrations profile: $integrations_profile"
    missing=1
    ;;
esac

if [ "$missing" -ne 0 ]; then
  echo "Install verification failed."
  exit 1
fi

echo "Install verification passed. Restart Claude Code and Codex sessions."
