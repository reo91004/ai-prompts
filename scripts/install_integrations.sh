#!/usr/bin/env bash
# Sourced by install.sh.

SEQUENTIAL_THINKING_PACKAGE="@modelcontextprotocol/server-sequential-thinking@latest"
PONYTAIL_REMOTE="https://github.com/DietrichGebert/ponytail.git"
PONYTAIL_SOURCE_ROOT="$HOME/.universal-research-agent-kit/sources"
PONYTAIL_MARKETPLACE_ROOT="$HOME/.universal-research-agent-kit/marketplaces"
# Resolved from the remote's current HEAD by prepare_ponytail_source, so an
# install always lands on the latest Ponytail. Every path and version check
# below is keyed on the resolved revision, never on a constant in this file.
PONYTAIL_REVISION=""
PONYTAIL_VERSION=""
PONYTAIL_SOURCE=""
PONYTAIL_MARKETPLACE=""


# Sequential Thinking MCP is add-or-repin: a registration under the kit's own
# name is replaced when it does not carry the kit's @latest package spec, so
# install alone converges a registration frozen at an older version. A
# registration under any other name is never inspected, replaced, or removed.
mcp_package_matches() {
  local description pattern
  description="$(cat)"
  pattern="$(printf '%s' "$SEQUENTIAL_THINKING_PACKAGE" | sed 's/\./\\./g')"
  printf '%s\n' "$description" | grep -Eq "(^|[^[:alnum:]_/@.-])$pattern([^[:alnum:]_/@.-]|$)" &&
    printf '%s\n' "$description" | grep -Fq "$HOME/.universal-research-agent-kit/cli/bin/kit-npx"
}

ensure_codex_sequential_thinking() {
  local current
  if current="$(cd "$HOME" && codex mcp get sequential_thinking 2>/dev/null)"; then
    if printf '%s\n' "$current" | mcp_package_matches; then
      echo "Codex sequential_thinking MCP already has the package and host-local launcher; leaving it unchanged."
      CODEX_SEQTHINK_STATE="preexisting"
      return
    fi
    echo "Re-registering the Codex sequential_thinking MCP against the latest package."
    (cd "$HOME" && codex mcp remove sequential_thinking)
    (cd "$HOME" && codex mcp add sequential_thinking -- "$HOME/.universal-research-agent-kit/cli/bin/kit-npx" -y "$SEQUENTIAL_THINKING_PACKAGE")
    (cd "$HOME" && codex mcp get sequential_thinking >/dev/null 2>&1) ||
      kit_die "Failed to re-register the Codex sequential_thinking MCP."
    CODEX_SEQTHINK_STATE="repinned_kit"
    return
  fi
  echo "Registering the Sequential Thinking MCP (latest) for Codex."
  (cd "$HOME" && codex mcp add sequential_thinking -- "$HOME/.universal-research-agent-kit/cli/bin/kit-npx" -y "$SEQUENTIAL_THINKING_PACKAGE")
  (cd "$HOME" && codex mcp get sequential_thinking >/dev/null 2>&1) ||
    kit_die "Failed to register the Codex sequential_thinking MCP."
  CODEX_SEQTHINK_STATE="registered_kit"
}

ensure_claude_sequential_thinking() {
  local current
  if current="$(claude mcp get sequential-thinking 2>/dev/null)"; then
    if printf '%s\n' "$current" | mcp_package_matches; then
      echo "Claude sequential-thinking MCP already has the package and host-local launcher; leaving it unchanged."
      CLAUDE_SEQTHINK_STATE="preexisting"
      return
    fi
    echo "Re-registering the Claude sequential-thinking MCP against the latest package."
    claude mcp remove sequential-thinking -s user
    claude mcp add -s user sequential-thinking -- "$HOME/.universal-research-agent-kit/cli/bin/kit-npx" -y "$SEQUENTIAL_THINKING_PACKAGE"
    claude mcp get sequential-thinking >/dev/null 2>&1 ||
      kit_die "Failed to re-register the Claude sequential-thinking MCP."
    CLAUDE_SEQTHINK_STATE="repinned_kit"
    return
  fi
  echo "Registering the Sequential Thinking MCP (latest) for Claude Code."
  claude mcp add -s user sequential-thinking -- "$HOME/.universal-research-agent-kit/cli/bin/kit-npx" -y "$SEQUENTIAL_THINKING_PACKAGE"
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
    const exact = plugin && (!process.argv[2] || plugin.version === process.argv[2]) &&
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
    process.exit(plugin && (!process.argv[1] || plugin.version === process.argv[1]) && plugin.enabled === true ? 0 : 1);
  ' "${1-$PONYTAIL_VERSION}"
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
    echo "Error: git is required to install the latest Ponytail release." >&2
    exit 1
  }
  kit_require_real_dir "$PONYTAIL_SOURCE_ROOT"

  PONYTAIL_REVISION="$(git ls-remote "$PONYTAIL_REMOTE" HEAD | awk 'NR == 1 { print $1 }')"
  case "$PONYTAIL_REVISION" in
    [0-9a-f][0-9a-f]*) ;;
    *) kit_die "Failed to resolve the latest Ponytail revision from $PONYTAIL_REMOTE" ;;
  esac
  PONYTAIL_SOURCE="$PONYTAIL_SOURCE_ROOT/ponytail-$PONYTAIL_REVISION"
  PONYTAIL_MARKETPLACE="$PONYTAIL_MARKETPLACE_ROOT/ponytail-$PONYTAIL_REVISION"

  if [ -e "$PONYTAIL_SOURCE" ]; then
    kit_require_real_dir "$PONYTAIL_SOURCE"
    kit_require_real_dir "$PONYTAIL_SOURCE/.git"
  else
    temp="$(mktemp -d "$PONYTAIL_SOURCE_ROOT/.ponytail.tmp.XXXXXX")"
    if ! git -C "$temp" init -q ||
       ! git -C "$temp" remote add origin "$PONYTAIL_REMOTE" ||
       ! git -C "$temp" fetch -q --depth=1 origin "$PONYTAIL_REVISION" ||
       ! git -C "$temp" checkout -q --detach FETCH_HEAD; then
      rm -rf -- "$temp"
      echo "Error: failed to fetch the latest Ponytail release." >&2
      exit 1
    fi
    mv "$temp" "$PONYTAIL_SOURCE"
  fi

  revision="$(git -C "$PONYTAIL_SOURCE" rev-parse HEAD)"
  [ "$revision" = "$PONYTAIL_REVISION" ] ||
    kit_die "Ponytail checkout has unexpected revision: $revision"
  [ -z "$(git -C "$PONYTAIL_SOURCE" status --porcelain --untracked-files=all)" ] ||
    kit_die "Ponytail checkout contains local modifications."

  # The version to verify after install comes from the checkout, so tracking
  # HEAD cannot leave a stale expected version behind in this script.
  PONYTAIL_VERSION="$(node -e '
    const fs = require("fs");
    const manifest = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    process.stdout.write(manifest.version || "");
  ' "$PONYTAIL_SOURCE/.claude-plugin/plugin.json")"
  [ -n "$PONYTAIL_VERSION" ] ||
    kit_die "Ponytail checkout $PONYTAIL_REVISION declares no plugin version."
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

# Runs after verification: the rollback journal does not restore removed revisions.
prune_old_ponytail_revisions() {
  local root entry name

  [ -n "$PONYTAIL_REVISION" ] || return 0
  for root in "$PONYTAIL_SOURCE_ROOT" "$PONYTAIL_MARKETPLACE_ROOT"; do
    for entry in "$root"/ponytail-*; do
      [ -d "$entry" ] || continue
      name="${entry##*/}"
      if [ "$name" != "ponytail-$PONYTAIL_REVISION" ]; then
        kit_remove_owned_entry "$root" "$name"
        echo "Removed superseded Ponytail revision directory: $entry"
      fi
    done
  done
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


ensure_user_codex_ponytail() {
    if ! codex_plugin_installed ponytail@ponytail; then
      codex plugin add ponytail@ponytail
    fi
    codex_plugin_exact_enabled ponytail@ponytail "" ||
      kit_die "User-owned Codex Ponytail is not enabled. Enable ponytail@ponytail in Codex plugin settings, then rerun; this CLI has no plugin-enable command. Its source was preserved."
}

# Parse outside a predicate: malformed CLI JSON must fail, not resemble absence.
validate_plugin_listings() {
  local host
  for host in codex claude; do
    "$host" plugin list --json | node -e 'JSON.parse(require("fs").readFileSync(0,"utf8"))'
    "$host" plugin marketplace list --json | node -e 'JSON.parse(require("fs").readFileSync(0,"utf8"))'
  done
}

install_integrations() {
  if [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_TOOLING:-0}" != 1 ]; then
    prepare_sequential_thinking
  else
    echo "Scoped integration: Sequential Thinking runtime update skipped with tooling."
    SEQUENTIAL_THINKING_STATE=skipped_env
  fi
  kit_require_real_dir "$HOME/.codex"
  kit_require_real_dir "$HOME/.codex/plugins"
  kit_require_regular_or_absent "$HOME/.codex/config.toml"
  kit_backup_path "$HOME/.codex/config.toml" "integrations/codex-config.toml"
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
  validate_plugin_listings

if [ "$PROFILE" != "none" ]; then
  prepare_ponytail_source
  prepare_ponytail_marketplace
fi

  if [ "$PROFILE" = "none" ]; then
    reconcile_codex_ponytail_none
  elif codex_plugin_installed ponytail@ponytail && ! codex_plugin_kit_owned ponytail@ponytail; then
    ensure_user_codex_ponytail
    CODEX_PONYTAIL_STATE="preserved_user_owned"
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
    ensure_user_codex_ponytail
    CODEX_PONYTAIL_STATE="preserved_user_owned"
  fi


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
    if ! claude_plugin_installed; then
      claude plugin install ponytail@ponytail -s user
    fi
    if ! claude_plugin_exact_enabled ""; then
      claude plugin enable ponytail@ponytail -s user
    fi
    claude_plugin_exact_enabled "" || kit_die "User-owned Claude Ponytail is not installed and enabled; check its marketplace and rerun. Its source was preserved."
    CLAUDE_PONYTAIL_STATE="preserved_user_owned"
  fi


ensure_codex_sequential_thinking
ensure_claude_sequential_thinking

kit_write_integrations_state "$PROFILE" "$CODEX_PONYTAIL_STATE" "$CLAUDE_PONYTAIL_STATE" "$CODEX_SEQTHINK_STATE" "$CLAUDE_SEQTHINK_STATE"
echo "Recorded integrations state (profile: $PROFILE)."

}
