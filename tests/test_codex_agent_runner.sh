#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/codex-agent-runner.XXXXXX")"
trap 'rm -rf "$fixture_root"' EXIT

mkdir -p "$fixture_root/home/agents" "$fixture_root/bin"
cat > "$fixture_root/home/agents/test_agent.toml" <<'AGENT'
name = "test_agent"
description = "Test agent"
model = "gpt-test-model"
model_reasoning_effort = "high"
sandbox_mode = "read-only"
developer_instructions = """
Follow the test task exactly. Do not delegate or spawn child agents.
"""
AGENT
cat > "$fixture_root/bin/codex" <<'CODEX'
#!/usr/bin/env bash
printf '<%s>\n' "$@"
CODEX
chmod +x "$fixture_root/bin/codex"

runner="$ROOT/codex/skills/resource-aware-orchestration/scripts/run_codex_agent.sh"
output="$(
  CODEX_HOME="$fixture_root/home" \
    PATH="$fixture_root/bin:$PATH" \
    "$runner" test_agent "inspect the repository"
)"

for expected in \
  'requested_agent=test_agent' \
  'declared_model=gpt-test-model' \
  'declared_reasoning_effort=high' \
  'spawn_transport=isolated_codex_cli' \
  '<--ephemeral>' \
  '<--model>' \
  '<gpt-test-model>' \
  '<--sandbox>' \
  '<read-only>' \
  '<model_reasoning_effort="high">' \
  '<-->' \
  '<inspect the repository>'; do
  grep -Fq "$expected" <<< "$output" || {
    echo "Missing runner output: $expected" >&2
    exit 1
  }
done
grep -Fq "developer_instructions='''Follow the test task exactly." <<< "$output" || {
  echo "Runner did not forward developer instructions" >&2
  exit 1
}

option_task_output="$(
  CODEX_HOME="$fixture_root/home" \
    PATH="$fixture_root/bin:$PATH" \
    "$runner" test_agent --help
)"
printf '%s\n' "$option_task_output" | awk '
  $0 == "<-->" { delimiter = NR }
  $0 == "<--help>" { task = NR }
  END { exit !(delimiter && task == delimiter + 1) }
' || {
  echo "Runner did not protect an option-like task with --" >&2
  exit 1
}

if CODEX_HOME="$fixture_root/home" PATH="$fixture_root/bin:$PATH" \
  "$runner" '../test_agent' task >/dev/null 2>&1; then
  echo "Runner accepted an unsafe agent name" >&2
  exit 1
fi

echo "Codex agent runner tests passed."
