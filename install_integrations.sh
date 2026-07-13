#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/lib/install_common.sh"

PROFILE="${1:-}"
case "$PROFILE" in
  ponytail|ultra) ;;
  *)
    echo "usage: install_integrations.sh ponytail|ultra" >&2
    echo "Integrations are opt-in; the core installer never runs this script by default." >&2
    exit 2
    ;;
esac

kit_init_state
kit_enable_rollback

LAZYCODEX_VERSION="4.17.0"
PONYTAIL_VERSION="4.8.4"
PONYTAIL_REVISION="bc9ee949d5f439e8b9f3bb92c6d6d3d1e6ebd324"
PONYTAIL_SOURCE_ROOT="$KIT_STATE_ROOT/sources"
PONYTAIL_SOURCE="$PONYTAIL_SOURCE_ROOT/ponytail-$PONYTAIL_REVISION"
PONYTAIL_MARKETPLACE_ROOT="$KIT_STATE_ROOT/marketplaces"
PONYTAIL_MARKETPLACE="$PONYTAIL_MARKETPLACE_ROOT/ponytail-$PONYTAIL_REVISION"

codex_plugin_installed() {
  local selector="$1"
  codex plugin list --json | node -e '
    const data = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const plugin = (data.installed || []).find((item) => item.pluginId === process.argv[1]);
    process.exit(plugin && plugin.installed === true ? 0 : 1);
  ' "$selector"
}

codex_plugin_kit_owned() {
  local selector="$1"
  codex plugin list --json | node -e '
    const data = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const plugin = (data.installed || []).find((item) => item.pluginId === process.argv[1]);
    const owned = plugin && plugin.source?.source === "local" &&
      typeof plugin.source.path === "string" &&
      plugin.source.path.startsWith(process.argv[2] + "/");
    process.exit(owned ? 0 : 1);
  ' "$selector" "$PONYTAIL_MARKETPLACE_ROOT"
}

codex_plugin_exact_enabled() {
  local selector="$1"
  local version="$2"
  local require_local="${3:-0}"
  local expected_path="${4:-}"
  codex plugin list --json | node -e '
    const data = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const plugin = (data.installed || []).find((item) => item.pluginId === process.argv[1]);
    const requireLocal = process.argv[3] === "1";
    const expectedPath = process.argv[4];
    const exact = plugin && plugin.version === process.argv[2] &&
      plugin.installed === true && plugin.enabled === true;
    const local = plugin && plugin.source?.source === "local" &&
      (!expectedPath || plugin.source.path === expectedPath);
    process.exit(exact && (!requireLocal || local) ? 0 : 1);
  ' "$selector" "$version" "$require_local" "$expected_path"
}

claude_plugin_installed() {
  claude plugin list --json | node -e '
    const plugins = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const plugin = plugins.find((item) =>
      item.id === "ponytail@ponytail" && item.scope === "user");
    process.exit(plugin ? 0 : 1);
  '
}

claude_plugin_exact_enabled() {
  claude plugin list --json | node -e '
    const plugins = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const plugin = plugins.find((item) =>
      item.id === "ponytail@ponytail" && item.scope === "user");
    process.exit(plugin && plugin.version === process.argv[1] && plugin.enabled === true ? 0 : 1);
  ' "$PONYTAIL_VERSION"
}

prepare_ponytail_source() {
  local temp
  local revision

  command -v git >/dev/null 2>&1 || {
    echo "Error: git is required to install the pinned Ponytail release." >&2
    exit 1
  }
  kit_require_real_dir "$PONYTAIL_SOURCE_ROOT"

  if [ -e "$PONYTAIL_SOURCE" ]; then
    kit_require_real_dir "$PONYTAIL_SOURCE"
    kit_require_real_dir "$PONYTAIL_SOURCE/.git"
  else
    temp="$(mktemp -d "$PONYTAIL_SOURCE_ROOT/.ponytail.tmp.XXXXXX")"
    if ! git -C "$temp" init -q ||
       ! git -C "$temp" remote add origin https://github.com/DietrichGebert/ponytail.git ||
       ! git -C "$temp" fetch -q --depth=1 origin "$PONYTAIL_REVISION" ||
       ! git -C "$temp" checkout -q --detach FETCH_HEAD; then
      rm -rf -- "$temp"
      echo "Error: failed to fetch the pinned Ponytail release." >&2
      exit 1
    fi
    mv "$temp" "$PONYTAIL_SOURCE"
  fi

  revision="$(git -C "$PONYTAIL_SOURCE" rev-parse HEAD)"
  [ "$revision" = "$PONYTAIL_REVISION" ] ||
    kit_die "Pinned Ponytail checkout has unexpected revision: $revision"
  [ -z "$(git -C "$PONYTAIL_SOURCE" status --porcelain --untracked-files=all)" ] ||
    kit_die "Pinned Ponytail checkout contains local modifications."
}

prepare_ponytail_marketplace() {
  local temp
  local name

  kit_require_real_dir "$PONYTAIL_MARKETPLACE_ROOT"
  temp="$(mktemp -d "$PONYTAIL_MARKETPLACE_ROOT/.ponytail-market.tmp.XXXXXX")"
  mkdir -p "$temp/.agents/plugins" "$temp/.claude-plugin" "$temp/ponytail"
  if ! git -C "$PONYTAIL_SOURCE" archive HEAD | tar -xf - -C "$temp/ponytail"; then
    rm -rf -- "$temp"
    kit_die "Failed to materialize the pinned Ponytail marketplace."
  fi

  cat > "$temp/.agents/plugins/marketplace.json" <<'JSON'
{
  "name": "ponytail",
  "interface": { "displayName": "Ponytail" },
  "plugins": [
    {
      "name": "ponytail",
      "source": { "source": "local", "path": "./ponytail" },
      "policy": { "installation": "AVAILABLE", "authentication": "ON_INSTALL" },
      "category": "Productivity"
    }
  ]
}
JSON
  cat > "$temp/.claude-plugin/marketplace.json" <<'JSON'
{
  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "ponytail",
  "description": "Pinned Ponytail marketplace for this kit.",
  "owner": { "name": "Dietrich Gebert", "url": "https://github.com/DietrichGebert" },
  "plugins": [
    {
      "name": "ponytail",
      "description": "Forces the smallest solution that works.",
      "source": "./ponytail",
      "category": "productivity"
    }
  ]
}
JSON

  name="${PONYTAIL_MARKETPLACE##*/}"
  kit_remove_owned_entry "$PONYTAIL_MARKETPLACE_ROOT" "$name"
  mv "$temp" "$PONYTAIL_MARKETPLACE"
}

# Only a marketplace registration that points into the kit state directory is
# kit-owned. A ponytail marketplace registered by the user is preserved and
# the kit skips its own Ponytail management for that host.
configure_codex_marketplace() {
  local marketplaces
  marketplaces="$(codex plugin marketplace list --json)"
  if printf '%s\n' "$marketplaces" |
     grep -Eq '"name"[[:space:]]*:[[:space:]]*"ponytail"' &&
     ! printf '%s\n' "$marketplaces" | grep -Fq "$PONYTAIL_MARKETPLACE"; then
    if printf '%s\n' "$marketplaces" | grep -Fq "$PONYTAIL_MARKETPLACE_ROOT/"; then
      codex plugin marketplace remove ponytail
    else
      echo "Preserving user-owned ponytail marketplace in Codex; skipping kit Ponytail management."
      return 1
    fi
  fi
  marketplaces="$(codex plugin marketplace list --json)"
  if ! printf '%s\n' "$marketplaces" | grep -Fq "$PONYTAIL_MARKETPLACE"; then
    codex plugin marketplace add "$PONYTAIL_MARKETPLACE"
  fi
}

configure_claude_marketplace() {
  local marketplaces
  marketplaces="$(claude plugin marketplace list --json)"
  if printf '%s\n' "$marketplaces" |
     grep -Eq '"name"[[:space:]]*:[[:space:]]*"ponytail"' &&
     ! printf '%s\n' "$marketplaces" | grep -Fq "$PONYTAIL_MARKETPLACE"; then
    if printf '%s\n' "$marketplaces" | grep -Fq "$PONYTAIL_MARKETPLACE_ROOT/"; then
      claude plugin marketplace remove ponytail
    else
      echo "Preserving user-owned ponytail marketplace in Claude Code; skipping kit Ponytail management."
      return 1
    fi
  fi
  marketplaces="$(claude plugin marketplace list --json)"
  if ! printf '%s\n' "$marketplaces" | grep -Fq "$PONYTAIL_MARKETPLACE"; then
    claude plugin marketplace add "$PONYTAIL_MARKETPLACE"
  fi
}

codex_available=0
claude_available=0
command -v codex >/dev/null 2>&1 && codex_available=1
command -v claude >/dev/null 2>&1 && claude_available=1

if [ "$codex_available" -eq 1 ]; then
  kit_require_real_dir "$HOME/.codex"
  kit_require_real_dir "$HOME/.codex/plugins"
  kit_require_regular_or_absent "$HOME/.codex/config.toml"
  kit_backup_path "$HOME/.codex/config.toml" "integrations/codex-config.toml"
fi
if [ "$claude_available" -eq 1 ]; then
  kit_require_real_dir "$HOME/.claude"
  kit_require_real_dir "$HOME/.claude/plugins"
  kit_require_regular_or_absent "$HOME/.claude.json"
  kit_require_regular_or_absent "$HOME/.claude/settings.json"
  kit_require_regular_or_absent "$HOME/.claude/plugins/known_marketplaces.json"
  kit_require_regular_or_absent "$HOME/.claude/plugins/installed_plugins.json"
  kit_backup_path "$HOME/.claude.json" "integrations/claude.json"
  kit_backup_path "$HOME/.claude/settings.json" "integrations/claude-settings.json"
  kit_backup_path "$HOME/.claude/plugins/known_marketplaces.json" "integrations/claude-known-marketplaces.json"
  kit_backup_path "$HOME/.claude/plugins/installed_plugins.json" "integrations/claude-installed-plugins.json"
fi

if [ "$codex_available" -eq 1 ] || [ "$claude_available" -eq 1 ]; then
  prepare_ponytail_source
  prepare_ponytail_marketplace
fi

if [ "$codex_available" -eq 1 ]; then
  command -v node >/dev/null 2>&1 || kit_die "Node.js is required for Codex integrations."

  if [ "$PROFILE" = "ultra" ]; then
    if ! codex_plugin_exact_enabled "omo@sisyphuslabs" "$LAZYCODEX_VERSION"; then
      command -v npx >/dev/null 2>&1 || kit_die "npx is required to install LazyCodex."
      npx --yes "lazycodex-ai@$LAZYCODEX_VERSION" install --no-tui --no-codex-autonomous
    else
      echo "LazyCodex is already installed; keeping the existing installation."
    fi
    codex_plugin_exact_enabled "omo@sisyphuslabs" "$LAZYCODEX_VERSION" ||
      kit_die "LazyCodex $LAZYCODEX_VERSION is not installed and enabled."
  fi

  if configure_codex_marketplace; then
    if codex_plugin_installed "ponytail@ponytail" &&
       ! codex_plugin_exact_enabled "ponytail@ponytail" "$PONYTAIL_VERSION" 1 "$PONYTAIL_MARKETPLACE/ponytail"; then
      if codex_plugin_kit_owned "ponytail@ponytail"; then
        codex plugin remove ponytail@ponytail
      else
        kit_die "Existing Codex ponytail plugin is not kit-owned; remove it manually or keep it and skip integrations."
      fi
    fi
    if ! codex_plugin_exact_enabled "ponytail@ponytail" "$PONYTAIL_VERSION" 1 "$PONYTAIL_MARKETPLACE/ponytail"; then
      codex plugin add ponytail@ponytail
    else
      echo "Ponytail for Codex is already installed and enabled."
    fi
    codex_plugin_exact_enabled "ponytail@ponytail" "$PONYTAIL_VERSION" 1 "$PONYTAIL_MARKETPLACE/ponytail" ||
      kit_die "Codex Ponytail $PONYTAIL_VERSION is not installed and enabled."
  fi
else
  echo "Codex CLI not found; skipped Codex integrations."
fi

if [ "$claude_available" -eq 1 ]; then
  command -v node >/dev/null 2>&1 || kit_die "Node.js is required for Claude Code integrations."
  if configure_claude_marketplace; then
    if claude_plugin_installed && ! claude_plugin_exact_enabled; then
      claude plugin uninstall ponytail@ponytail -s user
      claude plugin install ponytail@ponytail -s user
    elif ! claude_plugin_installed; then
      claude plugin install ponytail@ponytail -s user
    else
      echo "Ponytail for Claude Code is already installed and enabled."
    fi
    claude_plugin_exact_enabled ||
      kit_die "Claude Ponytail $PONYTAIL_VERSION is not installed and enabled."
  fi
else
  echo "Claude Code CLI not found; skipped Claude Code integrations."
fi
