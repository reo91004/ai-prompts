#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v node >/dev/null 2>&1 || { echo "node is required for the migration tests" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/harness-migration.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

PONYTAIL_REVISION="0a4dd63ad4541f4f655c4108a295916f3c1d8fda"
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
  "plugin remove ponytail@ponytail" | "plugin remove omo@sisyphuslabs")
    node -e '
      const fs = require("fs");
      const path = process.argv[1] + "/plugins.json";
      const target = process.argv[2];
      const data = JSON.parse(fs.readFileSync(path, "utf8"));
      data.installed = (data.installed || []).filter((p) => p.pluginId !== target);
      fs.writeFileSync(path, JSON.stringify(data));
    ' "$STATE" "${cmd##* }"
    ;;
  "plugin marketplace remove sisyphuslabs")
    node -e '
      const fs = require("fs");
      const path = process.argv[1] + "/marketplaces.json";
      const data = JSON.parse(fs.readFileSync(path, "utf8"));
      fs.writeFileSync(path, JSON.stringify(data.filter((m) => m.name !== "sisyphuslabs")));
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
  "mcp list")
    config="$HOME/.codex/config.toml"
    [ ! -f "$config" ] || [ "$(grep -Fxc '[mcp_servers.headroom]' "$config" || true)" -le 1 ]
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
          version: "4.9.0",
          installed: true,
          enabled: true,
          source: { source: "local", path: pluginPath },
        },
      ],
    };
    if (withLazy === "1") {
      plugins.installed.push({
        pluginId: "omo@sisyphuslabs",
        version: "4.19.4",
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
      { id: "ponytail@ponytail", scope: "user", version: "4.9.0", enabled: true },
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
    UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_TOOLING=1 \
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

grep -Fqx 'codex plugin remove omo@sisyphuslabs' "$A_CODEX/calls.log" || {
  echo "legacy LazyCodex was not removed" >&2; exit 1; }
grep -Fqx 'codex plugin remove ponytail@ponytail' "$A_CODEX/calls.log" || {
  echo "kit-owned Codex Ponytail plugin was not removed" >&2; exit 1; }
grep -Fqx 'codex plugin marketplace remove ponytail' "$A_CODEX/calls.log" || {
  echo "kit-owned Codex ponytail marketplace was not removed" >&2; exit 1; }
grep -Fqx 'claude plugin uninstall ponytail@ponytail -s user' "$A_CLAUDE/calls.log" || {
  echo "kit-owned Claude Ponytail plugin was not removed" >&2; exit 1; }
[ "$(state_value "$A_HOME" requested_profile)" = "none" ]
[ "$(state_value "$A_HOME" codex_lazycodex)" = "removed_legacy" ]
[ "$(state_value "$A_HOME" codex_ponytail)" = "removed_legacy" ]
[ "$(state_value "$A_HOME" claude_ponytail)" = "removed_legacy" ]
[ "$(state_value "$A_HOME" codex_sequential_thinking)" = "registered_kit" ]
[ "$(state_value "$A_HOME" claude_sequential_thinking)" = "registered_kit" ]

echo "Scenario A repeat: converged state stays converged and verifies"
run_kit "$A_HOME" "$A_CODEX" "$A_CLAUDE" bash "$ROOT/install_all.sh" --integrations none >/dev/null
# Removal converges to absence: the second run finds nothing to remove.
[ "$(state_value "$A_HOME" codex_lazycodex)" = "not_requested" ]
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

echo "Scenario D: any-version LazyCodex is removed and max_threads is capped"
D_HOME="$WORK/home-d"
D_CODEX="$WORK/mock-d-codex"
D_CLAUDE="$WORK/mock-d-claude"
mkdir -p "$D_HOME/.codex/plugins" "$D_HOME/.claude/plugins"
printf '%s\n' \
  '[agents]' \
  'max_threads = 1000' \
  '' \
  '[agents.lazycodex-worker-high]' \
  'config_file = "/home/u/.codex/agents/lazycodex-worker-high.toml"' \
  '' \
  '[agents.lazycodex-worker-high.env]' \
  'FOO = "bar"' \
  '' \
  '[agents.metis]' \
  'config_file = "/home/u/.codex/agents/metis.toml"' \
  '' \
  '[agents.my-own-agent]' \
  'config_file = "/home/u/.codex/agents/my-own-agent.toml"' \
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
# LazyCodex copies loose agent TOMLs into ~/.codex/agents and records them in
# its own manifest. Codex reads that directory whether or not the plugin is
# registered, so removing the plugin alone leaves the roles dispatchable.
D_AGENTS="$D_HOME/.codex/agents"
D_OMO_DATA="$D_HOME/.codex/plugins/data/omo-sisyphuslabs/bootstrap/agents-stage"
mkdir -p "$D_AGENTS" "$D_OMO_DATA"
for planted in lazycodex-worker-high lazycodex-code-reviewer explorer metis; do
  printf 'name = "%s"\n' "$planted" > "$D_AGENTS/$planted.toml"
done
printf 'name = "lazycodex-executor"\n' > "$D_AGENTS/lazycodex-executor.toml"
printf 'name = "my-own-agent"\n' > "$D_AGENTS/my-own-agent.toml"
node -e '
  const fs = require("fs");
  const [file, dir] = process.argv.slice(1);
  fs.writeFileSync(file, JSON.stringify({
    agents: ["lazycodex-worker-high", "lazycodex-code-reviewer", "explorer", "metis"]
      .map((n) => dir + "/" + n + ".toml"),
  }));
' "$D_OMO_DATA/.installed-agents.json" "$D_AGENTS"
run_kit "$D_HOME" "$D_CODEX" "$D_CLAUDE" bash "$ROOT/install_all.sh" --integrations none >/dev/null

for gone in lazycodex-worker-high lazycodex-code-reviewer lazycodex-executor explorer metis; do
  [ ! -e "$D_AGENTS/$gone.toml" ] || {
    echo "LazyCodex-planted agent survived removal: $gone" >&2; exit 1; }
done
[ -f "$D_AGENTS/my-own-agent.toml" ] || {
  echo "a user-owned Codex agent was deleted" >&2; exit 1; }
# A registration pointing at a deleted file makes Codex warn on every start.
for stale in '[agents.lazycodex-worker-high]' '[agents.lazycodex-worker-high.env]' '[agents.metis]'; do
  grep -Fqx "$stale" "$D_HOME/.codex/config.toml" && {
    echo "stale Codex agent registration survived: $stale" >&2; exit 1; }
done
grep -Fqx '[agents.my-own-agent]' "$D_HOME/.codex/config.toml" || {
  echo "a user-owned Codex agent registration was deleted" >&2; exit 1; }
grep -Fqx 'FOO = "bar"' "$D_HOME/.codex/config.toml" && {
  echo "a dropped agent subsection left its body behind" >&2; exit 1; }
d_threads_check="$(grep -A1 '^\[agents\]$' "$D_HOME/.codex/config.toml" | sed -n '2p')"
[ "$d_threads_check" = "max_threads = 6" ] || {
  echo "the [agents] table was damaged by the registration cleanup" >&2; exit 1; }

[ "$(state_value "$D_HOME" codex_lazycodex)" = "removed_legacy" ]
[ "$(state_value "$D_HOME" codex_ponytail)" = "not_requested" ]
grep -Fqx 'codex plugin remove omo@sisyphuslabs' "$D_CODEX/calls.log" || {
  echo "non-pinned LazyCodex was not removed" >&2; exit 1; }
node -e '
  const fs = require("fs");
  const data = JSON.parse(fs.readFileSync(process.argv[1] + "/plugins.json", "utf8"));
  process.exit((data.installed || []).some((p) => p.pluginId === "omo@sisyphuslabs") ? 1 : 0);
' "$D_CODEX" || { echo "LazyCodex is still installed after removal" >&2; exit 1; }
d_threads_line="$(grep -A1 '^\[agents\]$' "$D_HOME/.codex/config.toml" | sed -n '2p')"
[ "$d_threads_line" = "max_threads = 6" ] || {
  echo "agents.max_threads was not capped to 6" >&2; exit 1; }

echo "Scenario E: duplicate Headroom MCP sections are repaired before Codex CLI use"
E_HOME="$WORK/home-e"
E_CODEX="$WORK/mock-e-codex"
E_CLAUDE="$WORK/mock-e-claude"
mkdir -p "$E_HOME/.codex/plugins" "$E_HOME/.claude/plugins"
seed_codex_mock_state "$E_CODEX" "$E_HOME" empty
seed_claude_mock_state "$E_CLAUDE" "$E_HOME" empty
printf '%s\n' \
  'model = "gpt-5.6-sol"' \
  '' \
  '# --- Headroom MCP server ---' \
  '[mcp_servers.headroom]' \
  'command = "/old/headroom"' \
  'args = ["mcp", "serve"]' \
  '# --- end Headroom MCP server ---' \
  '' \
  '[mcp_servers.zotero]' \
  'command = "zotero-mcp"' \
  '' \
  '# --- Headroom MCP server ---' \
  '[mcp_servers.headroom]' \
  'command = "/managed/headroom"' \
  'args = ["mcp", "serve"]' \
  '' \
  '[mcp_servers.headroom.env]' \
  'HEADROOM_PROXY_URL = "http://127.0.0.1:8787"' \
  '# --- end Headroom MCP server ---' > "$E_HOME/.codex/config.toml"
run_kit "$E_HOME" "$E_CODEX" "$E_CLAUDE" bash "$ROOT/install_all.sh" --integrations none >/dev/null

[ "$(grep -Fxc '[mcp_servers.headroom]' "$E_HOME/.codex/config.toml" || true)" -eq 0 ]
grep -Fqx 'model = "gpt-5.6-sol"' "$E_HOME/.codex/config.toml"
grep -Fqx '[mcp_servers.zotero]' "$E_HOME/.codex/config.toml"
grep -Fqx 'command = "zotero-mcp"' "$E_HOME/.codex/config.toml"

echo "Scenario F: a stale Headroom-managed command is removed for canonical re-registration"
F_HOME="$WORK/home-f"
F_CODEX="$WORK/mock-f-codex"
F_CLAUDE="$WORK/mock-f-claude"
mkdir -p "$F_HOME/.codex/plugins" "$F_HOME/.claude/plugins"
seed_codex_mock_state "$F_CODEX" "$F_HOME" empty
seed_claude_mock_state "$F_CLAUDE" "$F_HOME" empty
printf '%s\n' \
  'model = "gpt-5.6-sol"' \
  '' \
  '# --- Headroom MCP server ---' \
  '[mcp_servers.headroom]' \
  'command = "/home/reo/.local/bin/headroom"' \
  'args = ["mcp", "serve"]' \
  '# --- end Headroom MCP server ---' > "$F_HOME/.codex/config.toml"
run_kit "$F_HOME" "$F_CODEX" "$F_CLAUDE" bash "$ROOT/install_all.sh" --integrations none >/dev/null

[ "$(grep -Fxc '[mcp_servers.headroom]' "$F_HOME/.codex/config.toml" || true)" -eq 0 ]
grep -Fqx 'model = "gpt-5.6-sol"' "$F_HOME/.codex/config.toml"

echo "Integration migration tests passed."
