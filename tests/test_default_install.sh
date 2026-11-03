#!/usr/bin/env bash
set -Eeuo pipefail
trap 'printf "Default installer test failed at %s:%s\n" "${BASH_SOURCE[0]}" "$LINENO" >&2' ERR
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export KIT_TEST_PYTHON="$(python3 -c 'import sys; print(sys.executable)')"
[ -x "$KIT_TEST_PYTHON" ] && "$KIT_TEST_PYTHON" -I -B -c 'import tomllib, tomlkit, mcp' >/dev/null 2>&1 || {
  echo 'SKIP: default installer tests require Python 3.11+ with tomlkit and the MCP SDK.'
  exit 77
}
export KIT_TEST_REAL_NODE="$(command -v node)"
export KIT_TEST_MOCK_RUNTIME="$ROOT/tests/mock_runtime.py"
export KIT_TEST_JSONC_PARSER="${KIT_TEST_JSONC_PARSER:-$ROOT/scripts/opencode-config/node_modules/jsonc-parser}"
[ -f "$KIT_TEST_JSONC_PARSER/lib/umd/main.js" ] || {
  echo 'SKIP: run npm ci --prefix scripts/opencode-config --ignore-scripts before installer orchestration tests.'
  exit 77
}
KIT_TEST_FIXTURES_ONLY=1 source "$ROOT/tests/test_integration_migration.sh"
export KIT_TEST_FIXTURES_ONLY=1
unset UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_TOOLING
export HOME="$WORK/full-home" CODEX_MOCK_STATE="$WORK/codex" CLAUDE_MOCK_STATE="$WORK/claude"
JQ_BIN="$(command -v jq)"
export PATH="$MOCK_BIN:/usr/bin:/bin"
export TOOLING_TEST_CALLS="$WORK/tooling-calls.log" UV_TOOL_BIN_DIR="$HOME/.universal-research-agent-kit/tooling/bin"
mkdir -p "$HOME"
export KIT_TEST_BTW_ADAPTER="$ROOT/tests/fixtures/btw_package.py"
export KIT_TEST_BTW_METADATA="$WORK/btw-release.json"
export KIT_TEST_BTW_ARCHIVE="$WORK/btw-fixture.tgz"
mkdir -p "$WORK/btw-source/package/dist"
printf '%s\n' '{"name":"opencode-btw-plus","version":"0.1.3"}' > "$WORK/btw-source/package/package.json"
printf '%s\n' "export default {id: 'btw-fixture', setup() {}};" > "$WORK/btw-source/package/dist/tui.js"
cp "$ROOT/tests/fixtures/humanizer/LICENSE" "$WORK/btw-source/package/LICENSE"
tar -czf "$KIT_TEST_BTW_ARCHIVE" -C "$WORK/btw-source" package
"$KIT_TEST_PYTHON" - "$KIT_TEST_BTW_ARCHIVE" "$KIT_TEST_BTW_METADATA" <<'PY'
import base64, hashlib, json, pathlib, sys
archive, metadata = map(pathlib.Path, sys.argv[1:])
metadata.write_text(json.dumps({
    "name": "opencode-btw-plus", "version": "0.1.3", "dist": {
        "tarball": "https://registry.npmjs.org/opencode-btw-plus/-/opencode-btw-plus-0.1.3.tgz",
        "integrity": "sha512-" + base64.b64encode(hashlib.sha512(archive.read_bytes()).digest()).decode(),
    },
}))
PY
rm "$MOCK_BIN/node"
cat > "$MOCK_BIN/node" <<'MOCK'
#!/bin/bash
case "${1:-}" in
  */opencode/plugins/btw-plus-compat/patch.mjs)
    shift
    exec "$KIT_TEST_PYTHON" "$KIT_TEST_BTW_ADAPTER" patch "$@"
    ;;
esac
exec "$KIT_TEST_REAL_NODE" "$@"
MOCK
chmod +x "$MOCK_BIN/node"
cat > "$MOCK_BIN/python3" <<'EOF'
#!/bin/sh
case "$*" in
  *'/headroom/maintenance.py '*) exec "$KIT_TEST_PYTHON" "$KIT_TEST_MOCK_RUNTIME" "$@" ;;
esac
exec "$KIT_TEST_PYTHON" "$@"
EOF
chmod +x "$MOCK_BIN/python3"
ln -s "$JQ_BIN" "$MOCK_BIN/jq"
cp "$ROOT/tests/mock_latest_curl.sh" "$MOCK_BIN/curl"
cat > "$MOCK_BIN/uv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'uv %s\n' "$*" >> "$TOOLING_TEST_CALLS"
[ "${1:-}" != "--version" ] || { echo "uv 0.12.24"; exit 0; }
[ "${TOOLING_TEST_UV_FAIL:-0}" != "1" ] || exit 42
MOCK_TOOL_BIN="${XDG_BIN_HOME:-$UV_TOOL_BIN_DIR}"
mkdir -p "$MOCK_TOOL_BIN"
case "$*" in
  --version) echo 'uv 0.12.24' ;;
  *'python install'*) : ;;
  '--no-config pip check --python '*) : ;;
  'tool dir --bin')
    printf '%s\n' "$UV_TOOL_BIN_DIR"
    ;;
  *graphifyy*)
    printf '%s\n' \
      '#!/usr/bin/env bash' \
      'set -euo pipefail' \
      'if [ "${1:-}" = "--version" ]; then printf "%s\\n" "graphify 0.9.82"; exit 0; fi' \
      'printf "graphify %s\\n" "$*" >> "$TOOLING_TEST_CALLS"' \
      '[ "${TOOLING_TEST_GRAPHIFY_FAIL:-}" != "${3:-}" ] || exit 42' \
      'case "${3:-}" in' \
      '  claude)' \
      '    mkdir -p "$HOME/.claude/skills/graphify"' \
      '    mkdir -p "$HOME/.claude/skills/graphify/references"' \
      '    printf "%s\\n" "# graphify" > "$HOME/.claude/skills/graphify/SKILL.md"' \
      '    printf "%s\\n" "0.9.82" > "$HOME/.claude/skills/graphify/.graphify_version"' \
      '    printf "%s\\n" "reference" > "$HOME/.claude/skills/graphify/references/README.md"' \
      '    printf "%s\\n" "" "# graphify" "- **graphify** (\`~/.claude/skills/graphify/SKILL.md\`) - any input to knowledge graph. Trigger: \`/graphify\`" "When the user types \`/graphify\`, use the installed graphify skill or instructions before doing anything else." >> "$HOME/.claude/CLAUDE.md"' \
      '    if [ -f "$HOME/.config/opencode/skills/graphify/SKILL.md" ]; then printf "%s\\n" "0.9.82" > "$HOME/.config/opencode/skills/graphify/.graphify_version"; fi' \
      '    if [ -f "$HOME/.gemini/config/skills/graphify/SKILL.md" ]; then printf "%s\\n" "0.9.82" > "$HOME/.gemini/config/skills/graphify/.graphify_version"; fi' \
      '    ;;' \
      '  codex)' \
      '    mkdir -p "$HOME/.codex/skills/graphify"' \
      '    mkdir -p "$HOME/.codex/skills/graphify/references"' \
      '    printf "%s\\n" "# graphify" > "$HOME/.codex/skills/graphify/SKILL.md"' \
      '    printf "%s\\n" "0.9.82" > "$HOME/.codex/skills/graphify/.graphify_version"' \
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
    printf '%s\n' '#!/usr/bin/env bash' 'if [ "${1:-}" = "--version" ]; then printf "%s\\n" "headroom 0.42.0"; exit 0; fi' 'printf "headroom %s\\n" "$*" >> "$TOOLING_TEST_CALLS"' 'printf "headroom-resolved %s\\n" "$(command -v headroom)" >> "$TOOLING_TEST_CALLS"' > "$MOCK_TOOL_BIN/headroom"
    chmod +x "$MOCK_TOOL_BIN/headroom"
    mkdir -p "$UV_TOOL_DIR/headroom-ai/bin"
    printf '%s\n' '#!/bin/sh' 'exec "$KIT_TEST_PYTHON" "$KIT_TEST_MOCK_RUNTIME" "$@"' > "$UV_TOOL_DIR/headroom-ai/bin/python"
    chmod +x "$UV_TOOL_DIR/headroom-ai/bin/python"
    rm -f "$HOME/.broken-headroom"
    ;;
esac
EOF

chmod +x "$MOCK_BIN/uv"
{
  printf '%s\n' '#!/bin/bash' 'if [ "${1:-}" = --version ]; then echo 10.0.0; exit 0; fi'
  printf '%s\n' '[ "$#" -eq 2 ] && [ "$1" = -y ] && [ "$2" = @modelcontextprotocol/server-sequential-thinking@2.0.0 ] || exit 99'
  printf 'exec %q -I -B %q\n' "$KIT_TEST_PYTHON" "$ROOT/tests/fixtures/sequential_thinking_server.py"
} > "$MOCK_BIN/npx"
chmod +x "$MOCK_BIN/npx"
seed_codex_mock_state "$CODEX_MOCK_STATE" "$HOME" empty
seed_claude_mock_state "$CLAUDE_MOCK_STATE" "$HOME" empty
mv "$MOCK_BIN/codex" "$MOCK_BIN/codex-base"
mv "$MOCK_BIN/claude" "$MOCK_BIN/claude-base"
for host in codex claude; do
  cat > "$MOCK_BIN/$host" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
host="${0##*/}"
if [ "$host" = codex ]; then state="$CODEX_MOCK_STATE"; else state="$CLAUDE_MOCK_STATE"; fi
case "$*" in
  'plugin marketplace add '*)
    node -e 'const fs=require("fs");fs.writeFileSync(process.argv[1]+"/marketplaces.json",JSON.stringify([{name:"ponytail",path:process.argv[2]}]));' "$state" "$4" ;;
  'plugin add ponytail@ponytail'|'plugin install ponytail@ponytail -s user')
    node -e '
      const fs=require("fs"), [state,host]=process.argv.slice(1);
      const m=JSON.parse(fs.readFileSync(state+"/marketplaces.json"))[0];
      const path=m.path+"/ponytail";
      const version=m.path.startsWith(process.env.HOME)?"4.9.0":"user-version";
      const item=host==="codex"?{pluginId:"ponytail@ponytail",installed:true,enabled:true,version,source:{source:"local",path}}:{id:"ponytail@ponytail",scope:"user",enabled:true,version};
      fs.writeFileSync(state+"/plugins.json",JSON.stringify(host==="codex"?{installed:[item]}:[item]));
    ' "$state" "$host" ;;
  'plugin enable ponytail@ponytail -s user')
    [ "$host" = claude ] || exit 1
    node -e 'const fs=require("fs"),p=process.argv[1]+"/plugins.json",x=JSON.parse(fs.readFileSync(p));x[0].enabled=true;fs.writeFileSync(p,JSON.stringify(x));' "$state" ;;
  *) exec "${0}-base" "$@" ;;
esac
MOCK
  chmod +x "$MOCK_BIN/$host"
done
cat > "$MOCK_BIN/git" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
revision=0a4dd63ad4541f4f655c4108a295916f3c1d8fda
case "$*" in *https://github.com/blader/humanizer*) echo 'Humanizer test must use its local fixture.' >&2; exit 99 ;; esac
case "$*" in *humanizer*) exec "$KIT_TEST_REAL_GIT" "$@" ;; esac
if [ "$1" = ls-remote ]; then printf '%s\tHEAD\n' "$revision"; exit; fi
[ "$1" = -C ] || exit 1
directory="$2"; shift 2
case "$*" in
  'init -q') mkdir -p "$directory/.git" ;;
  'remote add '*|'fetch '*) : ;;
  'checkout '*) mkdir -p "$directory/.claude-plugin"; printf '%s\n' '{"name":"ponytail","version":"4.9.0"}' > "$directory/.claude-plugin/plugin.json" ;;
  'rev-parse HEAD') echo "$revision" ;;
  'status --porcelain'*) : ;;
  'archive HEAD') tar -C "$directory" -cf - .claude-plugin ;;
  *) exit 1 ;;
esac
MOCK
chmod +x "$MOCK_BIN/git"

expect_failure() {
  if "$@" > "$WORK/expected-failure.log" 2>&1; then
    echo "Unexpected success: $*" >&2; exit 1
  fi
}
assert_defaults() {
  [ -s "$HOME/.codex/AGENTS.md" ] && [ -s "$HOME/.claude/CLAUDE.md" ]
  [ -s "$HOME/.config/opencode/AGENTS.md" ]
  [ -x "$HOME/.opencode/bin/opencode" ]
  [ "$("$HOME/.opencode/bin/opencode" --version)" = 2.2.5 ]
  [ "$(find "$HOME/.config/opencode/agents" -name '*.md' | wc -l | tr -d ' ')" = 2 ]
  [ "$(find "$HOME/.codex/agents" -name '*.toml' | wc -l | tr -d ' ')" = 16 ]
  [ "$(find "$HOME/.claude/agents" -name '*.md' | wc -l | tr -d ' ')" = 15 ]
  for target in "$HOME/.agents/skills" "$HOME/.claude/skills"; do
    for skill in "$ROOT/skills"/*; do [ ! -d "$skill" ] || diff -qr "$skill" "$target/${skill##*/}"; done
    cmp "$KIT_TEST_HUMANIZER_REPOSITORY/SKILL.md" "$target/humanizer/SKILL.md"
    cmp "$KIT_TEST_HUMANIZER_REPOSITORY/LICENSE" "$target/humanizer/LICENSE"
    diff -qr "$HOME/.universal-research-agent-kit/sources/humanizer/skill" "$target/humanizer"
    [ ! -e "$target/research-repo-design" ]
  done
  expected_skills=$(($(find "$ROOT/skills" -mindepth 1 -maxdepth 1 -type d | wc -l) + 1))
  [ "$(wc -l < "$HOME/.universal-research-agent-kit/manifests/codex-skills" | tr -d ' ')" -eq "$expected_skills" ]
  [ "$(wc -l < "$HOME/.universal-research-agent-kit/manifests/claude-skills" | tr -d ' ')" -eq "$expected_skills" ]
  grep -Fq '@modelcontextprotocol/server-sequential-thinking@2.0.0' "$CODEX_MOCK_STATE/mcp_sequential"
  grep -Fq '@modelcontextprotocol/server-sequential-thinking@2.0.0' "$CLAUDE_MOCK_STATE/mcp_sequential"
  "$KIT_TEST_PYTHON" -I -B "$ROOT/scripts/context_defaults.py" check "$ROOT/codex/context.toml" "$HOME/.codex/config.toml"
  [ -s "$HOME/.config/opencode/cli.json" ] && [ -s "$HOME/.config/opencode/opencode.jsonc" ]
  [ -s "$HOME/.config/opencode/research-agent-kit/context/index.js" ]
  node -e 'const fs=require("fs"),p=require(process.env.KIT_TEST_JSONC_PARSER);if(!p.parse(fs.readFileSync(process.argv[1],"utf8")).plugins.includes("opencode-latex@0.2.0"))process.exit(1)' "$HOME/.config/opencode/opencode.jsonc"
  [ -s "$HOME/.claude/skills/graphify/SKILL.md" ] && [ -s "$HOME/.codex/skills/graphify/SKILL.md" ]
  [ -x "$UV_TOOL_BIN_DIR/graphify" ] && [ -x "$UV_TOOL_BIN_DIR/headroom" ]
  cmp "$ROOT/headroom/auto-wrap.sh" "$HOME/.config/headroom/auto-wrap.sh"
  grep -Fq 'auto-wrap.sh' "$HOME/.bashrc"; grep -Fq 'auto-wrap.sh' "$HOME/.zshrc"
  node -e 'const fs=require("fs"),c=JSON.parse(fs.readFileSync(process.argv[1])).installed.find(x=>x.pluginId==="ponytail@ponytail"),a=JSON.parse(fs.readFileSync(process.argv[2])).find(x=>x.id==="ponytail@ponytail");if(!c?.installed||!c.enabled||!a?.enabled)process.exit(1);' "$CODEX_MOCK_STATE/plugins.json" "$CLAUDE_MOCK_STATE/plugins.json"
  bash "$ROOT/install.sh" --verify
}
# Bootstrap failures are explicit and roll back core changes; no real download.
cat > "$MOCK_BIN/curl" <<'MOCK'
#!/bin/sh
exit 22
MOCK
chmod +x "$MOCK_BIN/curl"
seed_native_clis "$HOME"
rm "$HOME/.local/bin/claude"
mv "$MOCK_BIN/claude" "$MOCK_BIN/claude-hidden"
expect_failure bash "$ROOT/install.sh"
grep -Eq 'Download failed: https://(releases.openai.com/codex/channels/latest|api.github.com/repos/openai/codex/releases/latest)' "$WORK/expected-failure.log"
[ ! -e "$HOME/.codex/AGENTS.md" ]
cp "$ROOT/tests/mock_latest_curl.sh" "$MOCK_BIN/curl"
mv "$MOCK_BIN/claude-hidden" "$MOCK_BIN/claude"
ln -s "$HOME/.local/share/claude/versions/2.1.0" "$HOME/.local/bin/claude"
echo 'Full default install from empty HOME'
sh "$ROOT/install.sh"
assert_defaults
first_humanizer_revision="$(node -p 'require(process.argv[1]).revision' "$HOME/.universal-research-agent-kit/sources/humanizer/source.json")"
cp "$MOCK_BIN/opencode" "$WORK/opencode-current"
sed 's/2.2.5/2.2.4/' "$WORK/opencode-current" > "$MOCK_BIN/opencode"
expect_failure bash "$ROOT/install.sh" --verify
cp "$WORK/opencode-current" "$MOCK_BIN/opencode"
cp "$HOME/.agents/skills/humanizer/SKILL.md" "$WORK/humanizer-original"
printf '\nUntracked modification.\n' >> "$HOME/.agents/skills/humanizer/SKILL.md"
expect_failure bash "$ROOT/install.sh" --verify
cp "$WORK/humanizer-original" "$HOME/.agents/skills/humanizer/SKILL.md"
mkdir -p "$KIT_TEST_HUMANIZER_REPOSITORY/references"
printf 'A new upstream reference.\n' > "$KIT_TEST_HUMANIZER_REPOSITORY/references/revision.md"
"$KIT_TEST_REAL_GIT" -C "$KIT_TEST_HUMANIZER_REPOSITORY" add .
"$KIT_TEST_REAL_GIT" -C "$KIT_TEST_HUMANIZER_REPOSITORY" -c user.name=Fixture \
  -c user.email=fixture@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null \
  commit --quiet -m "Update installer Humanizer fixture"
# A failed install keeps superseded Ponytail revisions; a verified install removes them.
for root in marketplaces sources; do mkdir -p "$HOME/.universal-research-agent-kit/$root/ponytail-old"; done
expect_failure env TOOLING_TEST_GRAPHIFY_FAIL=codex bash "$ROOT/install.sh"
[ "$(node -p 'require(process.argv[1]).revision' "$HOME/.universal-research-agent-kit/sources/humanizer/source.json")" = "$first_humanizer_revision" ]
[ ! -e "$HOME/.agents/skills/humanizer/references/revision.md" ]
for root in marketplaces sources; do [ -d "$HOME/.universal-research-agent-kit/$root/ponytail-old" ]; done
bash "$ROOT/install.sh"
[ "$(node -p 'require(process.argv[1]).revision' "$HOME/.universal-research-agent-kit/sources/humanizer/source.json")" != "$first_humanizer_revision" ]
cmp "$KIT_TEST_HUMANIZER_REPOSITORY/references/revision.md" "$HOME/.agents/skills/humanizer/references/revision.md"
for root in marketplaces sources; do [ ! -e "$HOME/.universal-research-agent-kit/$root/ponytail-old" ]; done
# Kit-owned plugins require an on-disk manifest with a nonempty version.
kit_manifests=("$HOME"/.universal-research-agent-kit/marketplaces/ponytail-*/ponytail/.claude-plugin/plugin.json)
mv "${kit_manifests[0]}" "$WORK/kit-plugin.json"
expect_failure bash "$ROOT/install.sh" --verify
grep -Fq 'Missing Codex integration: Ponytail' "$WORK/expected-failure.log"
grep -Fq 'Missing Claude integration: Ponytail' "$WORK/expected-failure.log"
printf '%s\n' '{"name":"ponytail","version":""}' > "${kit_manifests[0]}"
expect_failure bash "$ROOT/install.sh" --verify
grep -Fq 'Missing Codex integration: Ponytail' "$WORK/expected-failure.log"
grep -Fq 'Missing Claude integration: Ponytail' "$WORK/expected-failure.log"
mv "$WORK/kit-plugin.json" "${kit_manifests[0]}"
# A stale external manifest must not delete a just-installed current core role.
mkdir -p "$HOME/.codex/plugins/data/omo-sisyphuslabs/bootstrap/agents-stage"
printf '{"agents":["%s/.codex/agents/implementation_engineer.toml"]}\n' "$HOME" > "$HOME/.codex/plugins/data/omo-sisyphuslabs/bootstrap/agents-stage/.installed-agents.json"
readonly_before="$(find "$HOME" -type f -exec cksum {} + | sort)"
bash "$ROOT/install.sh" --verify > "$WORK/readonly-verify.log"
[ "$readonly_before" = "$(find "$HOME" -type f -exec cksum {} + | sort)" ]
echo 'Full default repeat with stale legacy metadata'
bash "$ROOT/install.sh"
assert_defaults
for state in integrations tooling; do
  mv "$HOME/.universal-research-agent-kit/$state.state" "$WORK/$state.state"
  expect_failure bash "$ROOT/install.sh" --verify
  grep -Fq "Missing $state state" "$WORK/expected-failure.log"
  expect_failure env UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS=1 UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_TOOLING=1 bash "$ROOT/install.sh" --verify
  mv "$WORK/$state.state" "$HOME/.universal-research-agent-kit/$state.state"
done
# Replacing an MCP with another package fails read-only verification.
cp "$CODEX_MOCK_STATE/mcp_sequential" "$WORK/mcp-before"
printf '%s\n' '@modelcontextprotocol/server-sequential-thinking@latest-other' > "$CODEX_MOCK_STATE/mcp_sequential"
expect_failure bash "$ROOT/install.sh" --verify
cp "$WORK/mcp-before" "$CODEX_MOCK_STATE/mcp_sequential"
mv "$MOCK_BIN/claude" "$MOCK_BIN/claude-hidden"
expect_failure bash "$ROOT/install.sh" --verify
mv "$MOCK_BIN/claude-hidden" "$MOCK_BIN/claude"
# User marketplace with absent plugins: install from the same source, no repinning.
for state in "$CODEX_MOCK_STATE" "$CLAUDE_MOCK_STATE"; do
  printf '%s\n' '[{"name":"ponytail","path":"/opt/user-marketplace"}]' > "$state/marketplaces.json"
done
printf '%s\n' '{"installed":[]}' > "$CODEX_MOCK_STATE/plugins.json"
printf '%s\n' '[]' > "$CLAUDE_MOCK_STATE/plugins.json"
bash "$ROOT/install.sh"
assert_defaults
for state in "$CODEX_MOCK_STATE" "$CLAUDE_MOCK_STATE"; do grep -Fq /opt/user-marketplace "$state/marketplaces.json"; done
# Claude provides a documented enable command; Codex does not.
node -e 'const fs=require("fs"),p=process.argv[1],x=JSON.parse(fs.readFileSync(p));x[0].enabled=false;fs.writeFileSync(p,JSON.stringify(x));' "$CLAUDE_MOCK_STATE/plugins.json"
expect_failure bash "$ROOT/install.sh" --verify
bash "$ROOT/install.sh"
assert_defaults
node -e 'const fs=require("fs"),p=process.argv[1],x=JSON.parse(fs.readFileSync(p));x.installed[0].enabled=false;fs.writeFileSync(p,JSON.stringify(x));' "$CODEX_MOCK_STATE/plugins.json"
expect_failure bash "$ROOT/install.sh" --verify
expect_failure bash "$ROOT/install.sh"
grep -Fq 'Enable ponytail@ponytail in Codex plugin settings' "$WORK/expected-failure.log"
grep -Fq /opt/user-marketplace "$CODEX_MOCK_STATE/marketplaces.json"
# Explicit none keeps the disabled user-owned plugin choice.
bash "$ROOT/install.sh" --integrations none
node -e 'const fs=require("fs"),x=JSON.parse(fs.readFileSync(process.argv[1]));if(x.installed[0].enabled!==false)process.exit(1);' "$CODEX_MOCK_STATE/plugins.json"
printf '%s\n' '{malformed-json' > "$CODEX_MOCK_STATE/plugins.json"
expect_failure bash "$ROOT/install.sh" --verify
grep -Fq SyntaxError "$WORK/expected-failure.log"
grep -Fqx '{malformed-json' "$CODEX_MOCK_STATE/plugins.json"
echo 'Full default installation regression passed.'
