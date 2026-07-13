#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/lib/install_common.sh"

PROFILE="${1:-}"
case "$PROFILE" in
  none|ponytail|ultra) ;;
  *)
    echo "usage: install_integrations.sh none|ponytail|ultra" >&2
    echo "The selected profile is the target state: 'none' also reconciles away kit-installed legacy plugins." >&2
    exit 2
    ;;
esac

kit_init_state
kit_enable_rollback

LAZYCODEX_VERSION="4.17.0"
PONYTAIL_VERSION="4.8.4"
PONYTAIL_REVISION="bc9ee949d5f439e8b9f3bb92c6d6d3d1e6ebd324"
SEQUENTIAL_THINKING_PACKAGE="@modelcontextprotocol/server-sequential-thinking@2026.7.4"
PONYTAIL_SOURCE_ROOT="$KIT_STATE_ROOT/sources"
PONYTAIL_SOURCE="$PONYTAIL_SOURCE_ROOT/ponytail-$PONYTAIL_REVISION"
PONYTAIL_MARKETPLACE_ROOT="$KIT_STATE_ROOT/marketplaces"
PONYTAIL_MARKETPLACE="$PONYTAIL_MARKETPLACE_ROOT/ponytail-$PONYTAIL_REVISION"

CODEX_PONYTAIL_STATE="host_unavailable"
CLAUDE_PONYTAIL_STATE="host_unavailable"
CODEX_LAZYCODEX_STATE="host_unavailable"
CODEX_SEQTHINK_STATE="host_unavailable"
CLAUDE_SEQTHINK_STATE="host_unavailable"

# Sequential Thinking MCP is add-only: a registration under any existing
# name or version is never inspected further, replaced, or removed.
ensure_codex_sequential_thinking() {
  if (cd "$HOME" && codex mcp get sequential_thinking >/dev/null 2>&1); then
    echo "Codex sequential_thinking MCP is already registered; leaving it unchanged."
    CODEX_SEQTHINK_STATE="preexisting"
    return
  fi
  echo "Registering the pinned Sequential Thinking MCP for Codex."
  (cd "$HOME" && codex mcp add sequential_thinking -- npx -y "$SEQUENTIAL_THINKING_PACKAGE")
  (cd "$HOME" && codex mcp get sequential_thinking >/dev/null 2>&1) ||
    kit_die "Failed to register the Codex sequential_thinking MCP."
  CODEX_SEQTHINK_STATE="registered_kit"
}

ensure_claude_sequential_thinking() {
  if claude mcp get sequential-thinking >/dev/null 2>&1; then
    echo "Claude sequential-thinking MCP is already registered; leaving it unchanged."
    CLAUDE_SEQTHINK_STATE="preexisting"
    return
  fi
  echo "Registering the pinned Sequential Thinking MCP for Claude Code."
  claude mcp add -s user sequential-thinking -- npx -y "$SEQUENTIAL_THINKING_PACKAGE"
  claude mcp get sequential-thinking >/dev/null 2>&1 ||
    kit_die "Failed to register the Claude sequential-thinking MCP."
  CLAUDE_SEQTHINK_STATE="registered_kit"
}

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

# Codex has no plugin enable/disable subcommand: the enabled flag lives in
# ~/.codex/config.toml [plugins."<id>"] sections and `codex plugin list`
# reflects it. Subsections like [plugins."<id>".mcp_servers.*] are untouched.
codex_set_plugin_enabled() {
  local plugin="$1"
  local value="$2"
  local config="$HOME/.codex/config.toml"
  local tmp

  kit_require_regular_or_absent "$config"
  if [ ! -f "$config" ]; then
    printf '' > "$config"
  fi
  tmp="$(mktemp "$config.tmp.XXXXXX")"
  awk -v value="$value" -v header="[plugins.\"$plugin\"]" '
    $0 == header { in_section = 1; found = 1; print; next }
    /^\[/ {
      if (in_section && !wrote) { print "enabled = " value; wrote = 1 }
      in_section = 0
      print
      next
    }
    in_section && /^enabled[[:space:]]*=/ { print "enabled = " value; wrote = 1; next }
    { print }
    END {
      if (in_section && !wrote) print "enabled = " value
      if (!found) {
        print ""
        print header
        print "enabled = " value
      }
    }
  ' "$config" > "$tmp"
  mv "$tmp" "$config"
}

# Prints "<version> enabled|disabled" for an installed plugin, or "absent".
codex_plugin_status() {
  local selector="$1"
  codex plugin list --json | node -e '
    const data = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const plugin = (data.installed || []).find((item) => item.pluginId === process.argv[1]);
    if (!plugin || plugin.installed !== true) { console.log("absent"); process.exit(0); }
    console.log((plugin.version || "unknown") + " " + (plugin.enabled === true ? "enabled" : "disabled"));
  ' "$selector"
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

# Marketplace ownership: kit-owned means the registration path points into
# the kit state directory. Returns 0 kit-owned, 1 absent, 2 user-owned.
codex_ponytail_marketplace_ownership() {
  local marketplaces
  marketplaces="$(codex plugin marketplace list --json)"
  if ! printf '%s\n' "$marketplaces" | grep -Eq '"name"[[:space:]]*:[[:space:]]*"ponytail"'; then
    return 1
  fi
  if printf '%s\n' "$marketplaces" | grep -Fq "$PONYTAIL_MARKETPLACE_ROOT/"; then
    return 0
  fi
  return 2
}

claude_ponytail_marketplace_ownership() {
  local marketplaces
  marketplaces="$(claude plugin marketplace list --json)"
  if ! printf '%s\n' "$marketplaces" | grep -Eq '"name"[[:space:]]*:[[:space:]]*"ponytail"'; then
    return 1
  fi
  if printf '%s\n' "$marketplaces" | grep -Fq "$PONYTAIL_MARKETPLACE_ROOT/"; then
    return 0
  fi
  return 2
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

# Returns 0 when the kit marketplace is registered and usable, 1 when a
# user-owned ponytail marketplace must be preserved (skip kit management).
configure_codex_marketplace() {
  local ownership_rc=0
  codex_ponytail_marketplace_ownership || ownership_rc=$?
  if [ "$ownership_rc" -eq 2 ]; then
    echo "Preserving user-owned ponytail marketplace in Codex; skipping kit Ponytail management."
    return 1
  fi
  if [ "$ownership_rc" -eq 0 ] &&
     ! codex plugin marketplace list --json | grep -Fq "$PONYTAIL_MARKETPLACE"; then
    codex plugin marketplace remove ponytail
  fi
  if ! codex plugin marketplace list --json | grep -Fq "$PONYTAIL_MARKETPLACE"; then
    codex plugin marketplace add "$PONYTAIL_MARKETPLACE"
  fi
}

configure_claude_marketplace() {
  local ownership_rc=0
  claude_ponytail_marketplace_ownership || ownership_rc=$?
  if [ "$ownership_rc" -eq 2 ]; then
    echo "Preserving user-owned ponytail marketplace in Claude Code; skipping kit Ponytail management."
    return 1
  fi
  if [ "$ownership_rc" -eq 0 ] &&
     ! claude plugin marketplace list --json | grep -Fq "$PONYTAIL_MARKETPLACE"; then
    claude plugin marketplace remove ponytail
  fi
  if ! claude plugin marketplace list --json | grep -Fq "$PONYTAIL_MARKETPLACE"; then
    claude plugin marketplace add "$PONYTAIL_MARKETPLACE"
  fi
}

# Legacy LazyCodex reconciliation: only the kit-pinned version counts as
# kit-installed. Any other version is treated as user-owned and preserved.
reconcile_codex_lazycodex() {
  local status version enablement

  status="$(codex_plugin_status "omo@sisyphuslabs")"
  if [ "$status" = "absent" ]; then
    CODEX_LAZYCODEX_STATE="not_requested"
    return
  fi
  version="${status%% *}"
  enablement="${status##* }"
  if [ "$version" != "$LAZYCODEX_VERSION" ]; then
    echo "Warning: LazyCodex $version is not the kit-pinned $LAZYCODEX_VERSION; treating it as user-owned and leaving it unchanged." >&2
    CODEX_LAZYCODEX_STATE="user_owned_warned"
    return
  fi
  if [ "$enablement" = "enabled" ]; then
    echo "Disabling kit-installed legacy LazyCodex $LAZYCODEX_VERSION (profile: $PROFILE). Re-enable by setting enabled = true under [plugins.\"omo@sisyphuslabs\"] in ~/.codex/config.toml"
    codex_set_plugin_enabled "omo@sisyphuslabs" false
    [ "$(codex_plugin_status "omo@sisyphuslabs")" = "$LAZYCODEX_VERSION disabled" ] ||
      kit_die "Failed to disable legacy LazyCodex."
  else
    echo "Kit-installed legacy LazyCodex is already disabled."
  fi
  CODEX_LAZYCODEX_STATE="disabled_legacy"
}

# Profile none removes only kit-owned Ponytail remnants; user-owned
# marketplaces and plugins are never touched.
reconcile_codex_ponytail_none() {
  local ownership_rc=0

  if codex_plugin_installed "ponytail@ponytail"; then
    if codex_plugin_kit_owned "ponytail@ponytail"; then
      echo "Removing kit-installed Ponytail plugin from Codex (profile: none)."
      codex plugin remove ponytail@ponytail
      CODEX_PONYTAIL_STATE="removed_legacy"
    else
      echo "Preserving user-owned Ponytail plugin in Codex."
      CODEX_PONYTAIL_STATE="preserved_user_owned"
      return
    fi
  else
    CODEX_PONYTAIL_STATE="not_requested"
  fi

  codex_ponytail_marketplace_ownership || ownership_rc=$?
  if [ "$ownership_rc" -eq 0 ]; then
    echo "Removing kit-owned ponytail marketplace registration from Codex."
    codex plugin marketplace remove ponytail
    CODEX_PONYTAIL_STATE="removed_legacy"
  fi
}

reconcile_claude_ponytail_none() {
  local ownership_rc=0

  claude_ponytail_marketplace_ownership || ownership_rc=$?
  case "$ownership_rc" in
    0)
      if claude_plugin_installed; then
        echo "Removing kit-installed Ponytail plugin from Claude Code (profile: none)."
        claude plugin uninstall ponytail@ponytail -s user
      fi
      echo "Removing kit-owned ponytail marketplace registration from Claude Code."
      claude plugin marketplace remove ponytail
      CLAUDE_PONYTAIL_STATE="removed_legacy"
      ;;
    1)
      if claude_plugin_installed; then
        echo "Preserving Ponytail plugin in Claude Code (no kit-owned marketplace; treating as user-owned)."
        CLAUDE_PONYTAIL_STATE="preserved_user_owned"
      else
        CLAUDE_PONYTAIL_STATE="not_requested"
      fi
      ;;
    2)
      echo "Preserving user-owned ponytail marketplace in Claude Code."
      CLAUDE_PONYTAIL_STATE="preserved_user_owned"
      ;;
  esac
}

codex_available=0
claude_available=0
command -v codex >/dev/null 2>&1 && codex_available=1
command -v claude >/dev/null 2>&1 && claude_available=1

node_available=0
command -v node >/dev/null 2>&1 && node_available=1

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

if [ "$node_available" -eq 0 ] && { [ "$codex_available" -eq 1 ] || [ "$claude_available" -eq 1 ]; }; then
  if [ "$PROFILE" = "none" ]; then
    echo "Warning: Node.js is unavailable, so legacy integration reconciliation was skipped and is recorded as unverified." >&2
    if [ "$codex_available" -eq 1 ]; then
      CODEX_PONYTAIL_STATE="unverified_no_node"
      CODEX_LAZYCODEX_STATE="unverified_no_node"
      ensure_codex_sequential_thinking
    fi
    if [ "$claude_available" -eq 1 ]; then
      CLAUDE_PONYTAIL_STATE="unverified_no_node"
      ensure_claude_sequential_thinking
    fi
    kit_write_integrations_state "$PROFILE" "$CODEX_PONYTAIL_STATE" "$CLAUDE_PONYTAIL_STATE" "$CODEX_LAZYCODEX_STATE" "$CODEX_SEQTHINK_STATE" "$CLAUDE_SEQTHINK_STATE"
    exit 0
  fi
  kit_die "Node.js is required for the $PROFILE integrations profile."
fi

if [ "$PROFILE" != "none" ] && { [ "$codex_available" -eq 1 ] || [ "$claude_available" -eq 1 ]; }; then
  prepare_ponytail_source
  prepare_ponytail_marketplace
fi

if [ "$codex_available" -eq 1 ]; then
  if [ "$PROFILE" = "ultra" ]; then
    if ! codex_plugin_exact_enabled "omo@sisyphuslabs" "$LAZYCODEX_VERSION"; then
      command -v npx >/dev/null 2>&1 || kit_die "npx is required to install LazyCodex."
      npx --yes "lazycodex-ai@$LAZYCODEX_VERSION" install --no-tui --no-codex-autonomous
    else
      echo "LazyCodex is already installed; keeping the existing installation."
    fi
    codex_plugin_exact_enabled "omo@sisyphuslabs" "$LAZYCODEX_VERSION" ||
      kit_die "LazyCodex $LAZYCODEX_VERSION is not installed and enabled."
    CODEX_LAZYCODEX_STATE="installed_kit_owned"
  else
    reconcile_codex_lazycodex
  fi

  if [ "$PROFILE" = "none" ]; then
    reconcile_codex_ponytail_none
  elif configure_codex_marketplace; then
    if codex_plugin_installed "ponytail@ponytail" &&
       ! codex_plugin_exact_enabled "ponytail@ponytail" "$PONYTAIL_VERSION" 1 "$PONYTAIL_MARKETPLACE/ponytail"; then
      if codex_plugin_kit_owned "ponytail@ponytail"; then
        codex plugin remove ponytail@ponytail
      else
        kit_die "Existing Codex ponytail plugin is not kit-owned; remove it manually or keep it and rerun with --integrations none."
      fi
    fi
    if ! codex_plugin_exact_enabled "ponytail@ponytail" "$PONYTAIL_VERSION" 1 "$PONYTAIL_MARKETPLACE/ponytail"; then
      codex plugin add ponytail@ponytail
    else
      echo "Ponytail for Codex is already installed and enabled."
    fi
    codex_plugin_exact_enabled "ponytail@ponytail" "$PONYTAIL_VERSION" 1 "$PONYTAIL_MARKETPLACE/ponytail" ||
      kit_die "Codex Ponytail $PONYTAIL_VERSION is not installed and enabled."
    CODEX_PONYTAIL_STATE="installed_kit_owned"
  else
    CODEX_PONYTAIL_STATE="preserved_user_owned"
  fi
else
  echo "Codex CLI not found; skipped Codex integrations."
fi

if [ "$claude_available" -eq 1 ]; then
  if [ "$PROFILE" = "none" ]; then
    reconcile_claude_ponytail_none
  elif configure_claude_marketplace; then
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
    CLAUDE_PONYTAIL_STATE="installed_kit_owned"
  else
    CLAUDE_PONYTAIL_STATE="preserved_user_owned"
  fi
else
  echo "Claude Code CLI not found; skipped Claude Code integrations."
fi

if [ "$codex_available" -eq 1 ]; then
  ensure_codex_sequential_thinking
fi
if [ "$claude_available" -eq 1 ]; then
  ensure_claude_sequential_thinking
fi

kit_write_integrations_state "$PROFILE" "$CODEX_PONYTAIL_STATE" "$CLAUDE_PONYTAIL_STATE" "$CODEX_LAZYCODEX_STATE" "$CODEX_SEQTHINK_STATE" "$CLAUDE_SEQTHINK_STATE"
echo "Recorded integrations state (profile: $PROFILE)."
