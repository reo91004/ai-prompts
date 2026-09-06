#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

check_exact_line() {
  local path="$1"
  local line="$2"
  local count
  count="$(grep -Fxc "$line" "$path" || true)"
  [ "$count" -eq 1 ] || fail "$path must contain exactly once: $line"
}

count_files() {
  find "$1" -maxdepth 1 -type f -name "$2" | wc -l | awk '{ print $1 }'
}

[ "$(count_files "$ROOT/codex/agents" '*.toml')" -eq 16 ] || fail "Codex agent count must be 16"
[ "$(count_files "$ROOT/claude-code/agents" '*.md')" -eq 15 ] || fail "Claude agent count must be 15"

while IFS='|' read -r file name model effort sandbox; do
  path="$ROOT/codex/agents/$file"
  [ -f "$path" ] || { fail "missing Codex agent: $file"; continue; }
  check_exact_line "$path" "name = \"$name\""
  check_exact_line "$path" "model = \"$model\""
  check_exact_line "$path" "model_reasoning_effort = \"$effort\""
  check_exact_line "$path" "sandbox_mode = \"$sandbox\""
  [ "$(grep -c '^model = ' "$path")" -eq 1 ] || fail "$file has multiple model fields"
  [ "$(grep -c '^model_reasoning_effort = ' "$path")" -eq 1 ] || fail "$file has multiple reasoning fields"
  [ "$(grep -c '^sandbox_mode = ' "$path")" -eq 1 ] || fail "$file has multiple sandbox fields"
  grep -Fq 'Do not delegate or spawn child agents.' "$path" || fail "$file permits nested delegation"
done <<'CODEX_AGENTS'
adversarial_reviewer.toml|adversarial_reviewer|gpt-6-astra|high|read-only
code_comment_hygiene_reviewer.toml|code_comment_hygiene_reviewer|gpt-6-astra|low|read-only
context_explorer.toml|context_explorer|gpt-6-astra|medium|read-only
data_ml_experiment_reviewer.toml|data_ml_experiment_reviewer|gpt-6-astra|high|read-only
experiment_monitor.toml|experiment_monitor|gpt-6-astra|low|danger-full-access
hardware_vivado_reviewer.toml|hardware_vivado_reviewer|gpt-6-astra|high|read-only
implementation_engineer.toml|implementation_engineer|gpt-6-astra|medium|workspace-write
literature_method_reviewer.toml|literature_method_reviewer|gpt-6-astra|high|read-only
quality_gate_runner.toml|quality_gate_runner|gpt-6-astra|low|workspace-write
report_writer.toml|report_writer|gpt-6-astra|low|workspace-write
research_repo_architect.toml|research_repo_architect|gpt-6-astra|high|read-only
sequential_reasoning_coordinator.toml|sequential_reasoning_coordinator|gpt-6-astra|high|read-only
side_channel_security_reviewer.toml|side_channel_security_reviewer|gpt-6-astra|high|read-only
software_architect.toml|software_architect|gpt-6-astra|high|read-only
statistics_reviewer.toml|statistics_reviewer|gpt-6-astra|high|read-only
test_debug_engineer.toml|test_debug_engineer|gpt-6-astra|high|workspace-write
CODEX_AGENTS

while IFS='|' read -r file name model effort tools denied permission turns; do
  path="$ROOT/claude-code/agents/$file"
  [ -f "$path" ] || { fail "missing Claude agent: $file"; continue; }
  check_exact_line "$path" "name: $name"
  check_exact_line "$path" "model: $model"
  check_exact_line "$path" "effort: $effort"
  check_exact_line "$path" "tools: $tools"
  check_exact_line "$path" "disallowedTools: $denied"
  check_exact_line "$path" "permissionMode: $permission"
  check_exact_line "$path" "maxTurns: $turns"
  for field in model effort tools disallowedTools permissionMode maxTurns; do
    [ "$(grep -c "^$field:" "$path")" -eq 1 ] || fail "$file must define $field exactly once"
  done
  grep -Eq '^disallowedTools: \[[^]]*Agent[^]]*\]$' "$path" || fail "$file does not deny Agent"
  if grep -q '^memory:' "$path"; then
    fail "$file must not enable agent memory; cross-project memory is opt-in only"
  fi
done <<'CLAUDE_AGENTS'
adversarial-reviewer.md|adversarial-reviewer|opus|high|[Read, Grep, Glob, Bash]|[Write, Edit, Agent]|plan|12
code-comment-hygiene-reviewer.md|code-comment-hygiene-reviewer|sonnet|low|[Read, Grep, Glob]|[Write, Edit, Bash, Agent]|plan|8
context-explorer.md|context-explorer|sonnet|medium|[Read, Grep, Glob, Bash]|[Write, Edit, Agent]|plan|10
data-ml-experiment-reviewer.md|data-ml-experiment-reviewer|sonnet|high|[Read, Grep, Glob, Bash]|[Write, Edit, Agent]|plan|14
hardware-vivado-reviewer.md|hardware-vivado-reviewer|sonnet|high|[Read, Grep, Glob, Bash]|[Write, Edit, Agent]|plan|14
implementation-engineer.md|implementation-engineer|sonnet|medium|[Read, Grep, Glob, Bash, Write, Edit]|[Agent]|acceptEdits|24
literature-method-reviewer.md|literature-method-reviewer|sonnet|high|[Read, Grep, Glob, WebSearch, WebFetch]|[Write, Edit, Bash, Agent]|plan|12
quality-gate-runner.md|quality-gate-runner|sonnet|low|[Read, Grep, Glob, Bash]|[Write, Edit, Agent]|plan|8
report-writer.md|report-writer|sonnet|low|[Read, Grep, Glob, Write, Edit]|[Bash, Agent]|acceptEdits|12
research-repo-architect.md|research-repo-architect|opus|high|[Read, Grep, Glob, Bash]|[Write, Edit, Agent]|plan|14
sequential-reasoning-coordinator.md|sequential-reasoning-coordinator|opus|high|[Read, Grep, Glob, Bash]|[Write, Edit, Agent]|plan|12
side-channel-security-reviewer.md|side-channel-security-reviewer|opus|high|[Read, Grep, Glob, Bash]|[Write, Edit, Agent]|plan|14
software-architect.md|software-architect|sonnet|high|[Read, Grep, Glob, Bash]|[Write, Edit, Agent]|plan|12
statistics-reviewer.md|statistics-reviewer|opus|high|[Read, Grep, Glob, Bash]|[Write, Edit, Agent]|plan|12
test-debug-engineer.md|test-debug-engineer|sonnet|high|[Read, Grep, Glob, Bash, Write, Edit]|[Agent]|acceptEdits|24
CLAUDE_AGENTS

claude_writers="$(grep -lE '^tools: \[[^]]*(Write|Edit)' "$ROOT"/claude-code/agents/*.md | sed 's#.*/##' | sort | tr '\n' ' ')"
[ "$claude_writers" = "implementation-engineer.md report-writer.md test-debug-engineer.md " ] || fail "unauthorized Claude writer set: $claude_writers"

codex_names="$(sed -n 's/^name = "\([^"]*\)"/\1/p' "$ROOT"/codex/agents/*.toml)"
claude_names="$(sed -n 's/^name: \(.*\)$/\1/p' "$ROOT"/claude-code/agents/*.md)"
[ -z "$(printf '%s\n' "$codex_names" | sort | uniq -d)" ] || fail "duplicate Codex agent name"
[ -z "$(printf '%s\n' "$claude_names" | sort | uniq -d)" ] || fail "duplicate Claude agent name"


[ -f "$ROOT/codex/AGENTS.md" ] || fail "missing Codex global instructions"
[ -f "$ROOT/claude-code/CLAUDE.md" ] || fail "missing Claude global instructions"
[ ! -e "$ROOT/codex/skills" ] && [ ! -e "$ROOT/claude-code/skills" ] || fail "duplicate skill trees"
skill_count=0
for skill in "$ROOT/skills"/*; do
  [ -d "$skill" ] || continue
  skill_count=$((skill_count + 1))
  [ -s "$skill/SKILL.md" ] || { fail "missing skill instructions: $skill"; continue; }
  name="$(sed -n 's/^name: //p' "$skill/SKILL.md" | head -n 1)"
  [ "$name" = "${skill##*/}" ] || fail "skill name mismatch: $skill"
done
[ "$skill_count" -eq 15 ] || fail "shared skill count must be 15"
for command in install.sh skills/resource-aware-orchestration/scripts/detect_resources.sh skills/resource-aware-orchestration/scripts/run_codex_agent.sh; do
  [ -x "$ROOT/$command" ] || fail "missing executable: $command"
  bash -n "$ROOT/$command" || fail "shell syntax: $command"
done
[ -f "$ROOT/headroom/auto-wrap.sh" ] || fail "missing Headroom wrapper"
bash -n "$ROOT/headroom/auto-wrap.sh" || fail "Headroom wrapper syntax"
for obsolete in install_all.sh install_integrations.sh install_tooling.sh verify_install.sh cleanup_backups.sh codex/install.sh claude-code/install.sh lib/install_common.sh; do
  [ ! -e "$ROOT/$obsolete" ] || fail "obsolete installer: $obsolete"
done
check_exact_line "$ROOT/codex/config.toml.example" 'max_threads = 6'
check_exact_line "$ROOT/codex/config.toml.example" 'max_depth = 1'
check_exact_line "$ROOT/codex/config.toml.example" '[features.context_management]'
check_exact_line "$ROOT/codex/config.toml.example" 'experimental_mode = true'
[ "$failures" -eq 0 ] || { echo "Harness validation failed with $failures finding(s)." >&2; exit 1; }
echo "Harness structural validation passed (not an agent behavior test)."
