#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v node >/dev/null 2>&1 || { echo "node is required for the migration tests" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/harness-migration.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

PONYTAIL_REVISION="bc9ee949d5f439e8b9f3bb92c6d6d3d1e6ebd324"
MOCK_BIN="$WORK/bin"
mkdir -p "$MOCK_BIN"

# Mock CLIs replay plugin/marketplace state from JSON files and record every
# invocation, so reconciliation logic is testable without real CLIs, network,
# or a real plugin cache. Unhandled subcommands fail loudly.
cat > "$MOCK_BIN/codex" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
STATE="${CODEX_MOCK_STATE:?}"
cmd="$*"
printf 'codex %s\n' "$cmd" >> "$STATE/calls.log"
case "$cmd" in
  "plugin list --json")
    # Like the real CLI, the enabled flag is overlaid from the
    # [plugins."<id>"] sections of ~/.codex/config.toml.
    node -e '
      const fs = require("fs");
      const data = JSON.parse(fs.readFileSync(process.argv[1] + "/plugins.json", "utf8"));
      const config = process.env.HOME + "/.codex/config.toml";
      if (fs.existsSync(config)) {
        const text = fs.readFileSync(config, "utf8");
        for (const p of data.installed || []) {
          const header = "[plugins.\"" + p.pluginId + "\"]";
          const start = text.indexOf(header);
          if (start < 0) continue;
          const rest = text.slice(start + header.length);
          const end = rest.search(/\n\[/);
          const section = end >= 0 ? rest.slice(0, end) : rest;
          const flag = section.match(/^enabled[ \t]*=[ \t]*(true|false)/m);
          if (flag) p.enabled = flag[1] === "true";
        }
      }
      console.log(JSON.stringify(data));
    ' "$STATE"
    ;;
  "plugin marketplace list --json")
    cat "$STATE/marketplaces.json"
    ;;
  "plugin remove ponytail@ponytail")
    node -e '
      const fs = require("fs");
      const path = process.argv[1] + "/plugins.json";
      const data = JSON.parse(fs.readFileSync(path, "utf8"));
      data.installed = (data.installed || []).filter((p) => p.pluginId !== "ponytail@ponytail");
      fs.writeFileSync(path, JSON.stringify(data));
    ' "$STATE"
    ;;
  "plugin marketplace remove ponytail")
    node -e '
      const fs = require("fs");
      const path = process.argv[1] + "/marketplaces.json";
      const data = JSON.parse(fs.readFileSync(path, "utf8"));
      fs.writeFileSync(path, JSON.stringify(data.filter((m) => m.name !== "ponytail")));
    ' "$STATE"
    ;;
  "mcp get sequential_thinking")
    [ -f "$STATE/mcp_sequential" ]
    ;;
  "mcp add sequential_thinking -- npx -y @modelcontextprotocol/server-sequential-thinking@2026.7.4")
    : > "$STATE/mcp_sequential"
    ;;
  *)
    echo "codex mock: unhandled command: $cmd" >&2
    exit 1
    ;;
esac
MOCK
cat > "$MOCK_BIN/claude" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
STATE="${CLAUDE_MOCK_STATE:?}"
cmd="$*"
printf 'claude %s\n' "$cmd" >> "$STATE/calls.log"
case "$cmd" in
  "plugin list --json")
    cat "$STATE/plugins.json"
    ;;
  "plugin marketplace list --json")
    cat "$STATE/marketplaces.json"
    ;;
  "plugin uninstall ponytail@ponytail -s user")
    node -e '
      const fs = require("fs");
      const path = process.argv[1] + "/plugins.json";
      const data = JSON.parse(fs.readFileSync(path, "utf8"));
      fs.writeFileSync(path, JSON.stringify(data.filter((p) => p.id !== "ponytail@ponytail")));
    ' "$STATE"
    ;;
  "plugin marketplace remove ponytail")
    node -e '
      const fs = require("fs");
      const path = process.argv[1] + "/marketplaces.json";
      const data = JSON.parse(fs.readFileSync(path, "utf8"));
      fs.writeFileSync(path, JSON.stringify(data.filter((m) => m.name !== "ponytail")));
    ' "$STATE"
    ;;
  "mcp get sequential-thinking")
    [ -f "$STATE/mcp_sequential" ]
    ;;
  "mcp add -s user sequential-thinking -- npx -y @modelcontextprotocol/server-sequential-thinking@2026.7.4")
    : > "$STATE/mcp_sequential"
    ;;
  *)
    echo "claude mock: unhandled command: $cmd" >&2
    exit 1
    ;;
esac
MOCK
chmod +x "$MOCK_BIN/codex" "$MOCK_BIN/claude"

state_value() {
  sed -n "s/^$2=//p" "$1/.universal-research-agent-kit/integrations.state" | sed -n '1p'
}

seed_codex_mock_state() {
  local state_dir="$1"
  local home="$2"
  local ownership="$3"
  local kit_plugin_path="$home/.universal-research-agent-kit/marketplaces/ponytail-$PONYTAIL_REVISION/ponytail"
  local market_path="$kit_plugin_path"

  mkdir -p "$state_dir"
  : > "$state_dir/calls.log"
  if [ "$ownership" = "user" ]; then
    kit_plugin_path="/opt/user-plugins/ponytail"
    market_path="/opt/user-marketplace/ponytail"
  fi
  if [ "$ownership" = "empty" ]; then
    printf '%s\n' '{"installed":[]}' > "$state_dir/plugins.json"
    printf '%s\n' '[]' > "$state_dir/marketplaces.json"
    return
  fi
  node -e '
    const fs = require("fs");
    const [dir, pluginPath, marketPath, withLazy] = process.argv.slice(1);
    const plugins = {
      installed: [
        {
          pluginId: "ponytail@ponytail",
          version: "4.8.4",
          installed: true,
          enabled: true,
          source: { source: "local", path: pluginPath },
        },
      ],
    };
    if (withLazy === "1") {
      plugins.installed.push({
        pluginId: "omo@sisyphuslabs",
        version: "4.17.0",
        installed: true,
        enabled: true,
        source: { source: "npm" },
      });
    }
    fs.writeFileSync(dir + "/plugins.json", JSON.stringify(plugins));
    fs.writeFileSync(dir + "/marketplaces.json", JSON.stringify([{ name: "ponytail", path: marketPath }]));
  ' "$state_dir" "$kit_plugin_path" "$market_path" "$([ "$ownership" = "kit" ] && echo 1 || echo 0)"
}

seed_claude_mock_state() {
  local state_dir="$1"
  local home="$2"
  local ownership="$3"
  local market_path="$home/.universal-research-agent-kit/marketplaces/ponytail-$PONYTAIL_REVISION/ponytail"

  mkdir -p "$state_dir"
  : > "$state_dir/calls.log"
  if [ "$ownership" = "user" ]; then
    market_path="/opt/user-marketplace/ponytail"
  fi
  if [ "$ownership" = "empty" ]; then
    printf '%s\n' '[]' > "$state_dir/plugins.json"
    printf '%s\n' '[]' > "$state_dir/marketplaces.json"
    return
  fi
  node -e '
    const fs = require("fs");
    const [dir, marketPath] = process.argv.slice(1);
    fs.writeFileSync(dir + "/plugins.json", JSON.stringify([
      { id: "ponytail@ponytail", scope: "user", version: "4.8.4", enabled: true },
    ]));
    fs.writeFileSync(dir + "/marketplaces.json", JSON.stringify([{ name: "ponytail", path: marketPath }]));
  ' "$state_dir" "$market_path"
}

run_kit() {
  local home="$1"
  local codex_state="$2"
  local claude_state="$3"
  shift 3
  HOME="$home" PATH="$MOCK_BIN:$PATH" \
    CODEX_MOCK_STATE="$codex_state" CLAUDE_MOCK_STATE="$claude_state" \
    "$@"
}

echo "Scenario A: legacy kit integrations reconcile to profile none"
A_HOME="$WORK/home-a"
A_CODEX="$WORK/mock-a-codex"
A_CLAUDE="$WORK/mock-a-claude"
mkdir -p "$A_HOME/.codex/plugins" "$A_HOME/.claude/plugins"
seed_codex_mock_state "$A_CODEX" "$A_HOME" kit
seed_claude_mock_state "$A_CLAUDE" "$A_HOME" kit
run_kit "$A_HOME" "$A_CODEX" "$A_CLAUDE" bash "$ROOT/install_all.sh" --integrations none >/dev/null

disabled_line="$(grep -A1 '^\[plugins."omo@sisyphuslabs"\]$' "$A_HOME/.codex/config.toml" | sed -n '2p')"
[ "$disabled_line" = "enabled = false" ] || {
  echo "legacy LazyCodex was not disabled in config.toml" >&2; exit 1; }
grep -Fqx 'codex plugin remove ponytail@ponytail' "$A_CODEX/calls.log" || {
  echo "kit-owned Codex Ponytail plugin was not removed" >&2; exit 1; }
grep -Fqx 'codex plugin marketplace remove ponytail' "$A_CODEX/calls.log" || {
  echo "kit-owned Codex ponytail marketplace was not removed" >&2; exit 1; }
grep -Fqx 'claude plugin uninstall ponytail@ponytail -s user' "$A_CLAUDE/calls.log" || {
  echo "kit-owned Claude Ponytail plugin was not removed" >&2; exit 1; }
[ "$(state_value "$A_HOME" requested_profile)" = "none" ]
[ "$(state_value "$A_HOME" codex_lazycodex)" = "disabled_legacy" ]
[ "$(state_value "$A_HOME" codex_ponytail)" = "removed_legacy" ]
[ "$(state_value "$A_HOME" claude_ponytail)" = "removed_legacy" ]
[ "$(state_value "$A_HOME" codex_sequential_thinking)" = "registered_kit" ]
[ "$(state_value "$A_HOME" claude_sequential_thinking)" = "registered_kit" ]

echo "Scenario A repeat: converged state stays converged and verifies"
run_kit "$A_HOME" "$A_CODEX" "$A_CLAUDE" bash "$ROOT/install_all.sh" --integrations none >/dev/null
[ "$(state_value "$A_HOME" codex_lazycodex)" = "disabled_legacy" ]
[ "$(state_value "$A_HOME" codex_sequential_thinking)" = "preexisting" ]
[ "$(state_value "$A_HOME" claude_sequential_thinking)" = "preexisting" ]
run_kit "$A_HOME" "$A_CODEX" "$A_CLAUDE" bash "$ROOT/verify_install.sh" >/dev/null

echo "Scenario B: default profile is ponytail and user-owned Ponytail is preserved"
B_HOME="$WORK/home-b"
B_CODEX="$WORK/mock-b-codex"
B_CLAUDE="$WORK/mock-b-claude"
mkdir -p "$B_HOME/.codex/plugins" "$B_HOME/.claude/plugins" "$B_HOME/.universal-research-agent-kit/sources/ponytail-$PONYTAIL_REVISION/.git"
seed_codex_mock_state "$B_CODEX" "$B_HOME" user
seed_claude_mock_state "$B_CLAUDE" "$B_HOME" user
cat > "$MOCK_BIN/git" <<MOCK
#!/usr/bin/env bash
set -euo pipefail
cmd="\$*"
case "\$cmd" in
  *"rev-parse HEAD") echo "$PONYTAIL_REVISION" ;;
  *"status --porcelain"*) : ;;
  *"archive HEAD") tar -cf - -T /dev/null ;;
  *) echo "git mock: unhandled command: \$cmd" >&2; exit 1 ;;
esac
MOCK
chmod +x "$MOCK_BIN/git"
run_kit "$B_HOME" "$B_CODEX" "$B_CLAUDE" bash "$ROOT/install_all.sh" >/dev/null
rm -f "$MOCK_BIN/git"

if grep -Eq 'remove|uninstall|disable' "$B_CODEX/calls.log" "$B_CLAUDE/calls.log"; then
  echo "user-owned integrations were modified" >&2
  exit 1
fi
[ "$(state_value "$B_HOME" requested_profile)" = "ponytail" ]
[ "$(state_value "$B_HOME" codex_ponytail)" = "preserved_user_owned" ]
[ "$(state_value "$B_HOME" claude_ponytail)" = "preserved_user_owned" ]
[ "$(state_value "$B_HOME" codex_lazycodex)" = "not_requested" ]
run_kit "$B_HOME" "$B_CODEX" "$B_CLAUDE" bash "$ROOT/verify_install.sh" >/dev/null

echo "Scenario A follow-up: a user-installed non-pinned Ponytail after removal still verifies"
node -e '
  const fs = require("fs");
  const dir = process.argv[1];
  fs.writeFileSync(dir + "/plugins.json", JSON.stringify([
    { id: "ponytail@ponytail", scope: "user", version: "9.9.9", enabled: true },
  ]));
  fs.writeFileSync(dir + "/marketplaces.json", JSON.stringify([
    { name: "ponytail", path: "/opt/user-marketplace/ponytail" },
  ]));
' "$A_CLAUDE"
run_kit "$A_HOME" "$A_CODEX" "$A_CLAUDE" bash "$ROOT/verify_install.sh" >/dev/null || {
  echo "verify failed after the user installed their own non-pinned Ponytail" >&2
  exit 1
}

echo "Scenario C: standalone install_integrations.sh records state"
C_HOME="$WORK/home-c"
C_CODEX="$WORK/mock-c-codex"
C_CLAUDE="$WORK/mock-c-claude"
mkdir -p "$C_HOME/.codex/plugins" "$C_HOME/.claude/plugins"
seed_codex_mock_state "$C_CODEX" "$C_HOME" empty
seed_claude_mock_state "$C_CLAUDE" "$C_HOME" empty
run_kit "$C_HOME" "$C_CODEX" "$C_CLAUDE" bash "$ROOT/install_integrations.sh" none >/dev/null
[ "$(state_value "$C_HOME" requested_profile)" = "none" ]
[ "$(state_value "$C_HOME" codex_ponytail)" = "not_requested" ]
[ "$(state_value "$C_HOME" codex_lazycodex)" = "not_requested" ]
[ "$(state_value "$C_HOME" claude_ponytail)" = "not_requested" ]
[ "$(state_value "$C_HOME" codex_sequential_thinking)" = "registered_kit" ]
[ "$(state_value "$C_HOME" claude_sequential_thinking)" = "registered_kit" ]

echo "Scenario D: any-version LazyCodex is disabled and max_threads is capped"
D_HOME="$WORK/home-d"
D_CODEX="$WORK/mock-d-codex"
D_CLAUDE="$WORK/mock-d-claude"
mkdir -p "$D_HOME/.codex/plugins" "$D_HOME/.claude/plugins"
printf '%s\n' \
  '[agents]' \
  'max_threads = 1000' \
  '' \
  '[plugins."omo@sisyphuslabs"]' \
  'enabled = true' > "$D_HOME/.codex/config.toml"
mkdir -p "$D_CODEX" "$D_CLAUDE"
: > "$D_CODEX/calls.log"
: > "$D_CLAUDE/calls.log"
node -e '
  const fs = require("fs");
  const dir = process.argv[1];
  fs.writeFileSync(dir + "/plugins.json", JSON.stringify({
    installed: [{
      pluginId: "omo@sisyphuslabs",
      version: "4.16.1",
      installed: true,
      enabled: true,
      source: { source: "npm" },
    }],
  }));
  fs.writeFileSync(dir + "/marketplaces.json", "[]");
' "$D_CODEX"
printf '%s\n' '[]' > "$D_CLAUDE/plugins.json"
printf '%s\n' '[]' > "$D_CLAUDE/marketplaces.json"
run_kit "$D_HOME" "$D_CODEX" "$D_CLAUDE" bash "$ROOT/install_all.sh" --integrations none >/dev/null

[ "$(state_value "$D_HOME" codex_lazycodex)" = "disabled_legacy" ]
[ "$(state_value "$D_HOME" codex_ponytail)" = "not_requested" ]
d_disabled_line="$(grep -A1 '^\[plugins."omo@sisyphuslabs"\]$' "$D_HOME/.codex/config.toml" | sed -n '2p')"
[ "$d_disabled_line" = "enabled = false" ] || {
  echo "non-pinned LazyCodex was not disabled" >&2; exit 1; }
d_threads_line="$(grep -A1 '^\[agents\]$' "$D_HOME/.codex/config.toml" | sed -n '2p')"
[ "$d_threads_line" = "max_threads = 6" ] || {
  echo "agents.max_threads was not capped to 6" >&2; exit 1; }

echo "Integration migration tests passed."
