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

[ "$(count_files "$ROOT/codex/agents" '*.toml')" -eq 15 ] || fail "Codex agent count must be 15"
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
adversarial_reviewer.toml|adversarial_reviewer|gpt-5.6-sol|xhigh|read-only
code_comment_hygiene_reviewer.toml|code_comment_hygiene_reviewer|gpt-5.6-luna|low|read-only
context_explorer.toml|context_explorer|gpt-5.6-terra|medium|read-only
data_ml_experiment_reviewer.toml|data_ml_experiment_reviewer|gpt-5.6-terra|high|read-only
hardware_vivado_reviewer.toml|hardware_vivado_reviewer|gpt-5.6-terra|high|read-only
implementation_engineer.toml|implementation_engineer|gpt-5.6-terra|medium|workspace-write
literature_method_reviewer.toml|literature_method_reviewer|gpt-5.6-terra|high|read-only
quality_gate_runner.toml|quality_gate_runner|gpt-5.6-luna|low|workspace-write
report_writer.toml|report_writer|gpt-5.6-luna|low|workspace-write
research_repo_architect.toml|research_repo_architect|gpt-5.6-sol|high|read-only
sequential_reasoning_coordinator.toml|sequential_reasoning_coordinator|gpt-5.6-sol|high|read-only
side_channel_security_reviewer.toml|side_channel_security_reviewer|gpt-5.6-sol|high|read-only
software_architect.toml|software_architect|gpt-5.6-sol|high|read-only
statistics_reviewer.toml|statistics_reviewer|gpt-5.6-sol|high|read-only
test_debug_engineer.toml|test_debug_engineer|gpt-5.6-terra|high|workspace-write
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
done <<'CLAUDE_AGENTS'
adversarial-reviewer.md|adversarial-reviewer|opus|high|[Read, Grep, Glob, Bash]|[Write, Edit, Agent]|plan|12
code-comment-hygiene-reviewer.md|code-comment-hygiene-reviewer|sonnet|low|[Read, Grep, Glob]|[Write, Edit, Bash, Agent]|plan|8
context-explorer.md|context-explorer|sonnet|medium|[Read, Grep, Glob, Bash]|[Write, Edit, Agent]|plan|10
data-ml-experiment-reviewer.md|data-ml-experiment-reviewer|sonnet|high|[Read, Grep, Glob, Bash]|[Write, Edit, Agent]|plan|14
hardware-vivado-reviewer.md|hardware-vivado-reviewer|sonnet|high|[Read, Grep, Glob, Bash]|[Write, Edit, Agent]|plan|14
implementation-engineer.md|implementation-engineer|opus|high|[Read, Grep, Glob, Bash, Write, Edit]|[Agent]|acceptEdits|24
literature-method-reviewer.md|literature-method-reviewer|sonnet|high|[Read, Grep, Glob, WebSearch, WebFetch]|[Write, Edit, Bash, Agent]|plan|12
quality-gate-runner.md|quality-gate-runner|sonnet|low|[Read, Grep, Glob, Bash]|[Write, Edit, Agent]|plan|8
report-writer.md|report-writer|sonnet|low|[Read, Grep, Glob, Write, Edit]|[Bash, Agent]|acceptEdits|12
research-repo-architect.md|research-repo-architect|opus|high|[Read, Grep, Glob, Bash]|[Write, Edit, Agent]|plan|14
sequential-reasoning-coordinator.md|sequential-reasoning-coordinator|opus|high|[Read, Grep, Glob, Bash]|[Write, Edit, Agent]|plan|12
side-channel-security-reviewer.md|side-channel-security-reviewer|opus|high|[Read, Grep, Glob, Bash]|[Write, Edit, Agent]|plan|14
software-architect.md|software-architect|opus|high|[Read, Grep, Glob, Bash]|[Write, Edit, Agent]|plan|12
statistics-reviewer.md|statistics-reviewer|opus|high|[Read, Grep, Glob, Bash]|[Write, Edit, Agent]|plan|12
test-debug-engineer.md|test-debug-engineer|opus|high|[Read, Grep, Glob, Bash, Write, Edit]|[Agent]|acceptEdits|24
CLAUDE_AGENTS

claude_writers="$(grep -lE '^tools: \[[^]]*(Write|Edit)' "$ROOT"/claude-code/agents/*.md | sed 's#.*/##' | sort | tr '\n' ' ')"
[ "$claude_writers" = "implementation-engineer.md report-writer.md test-debug-engineer.md " ] || fail "unauthorized Claude writer set: $claude_writers"

codex_names="$(sed -n 's/^name = "\([^"]*\)"/\1/p' "$ROOT"/codex/agents/*.toml)"
claude_names="$(sed -n 's/^name: \(.*\)$/\1/p' "$ROOT"/claude-code/agents/*.md)"
[ -z "$(printf '%s\n' "$codex_names" | sort | uniq -d)" ] || fail "duplicate Codex agent name"
[ -z "$(printf '%s\n' "$claude_names" | sort | uniq -d)" ] || fail "duplicate Claude agent name"

diff -qr "$ROOT/codex/skills" "$ROOT/claude-code/skills" >/dev/null || fail "Codex and Claude skill trees are not byte mirrors"
for skill in resource-aware-orchestration review-budget hardware-capture-integrity; do
  [ -f "$ROOT/codex/skills/$skill/SKILL.md" ] || fail "missing skill: $skill"
done
[ -f "$ROOT/codex/skills/evidence-gate/references/evidence_contract.md" ] || fail "missing evidence contract"

for tree in "$ROOT/codex/skills" "$ROOT/claude-code/skills"; do
  skill_names=""
  for skill_dir in "$tree"/*; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(sed -n 's/^name: //p' "$skill_dir/SKILL.md" | sed -n '1p')"
    [ "$skill_name" = "${skill_dir##*/}" ] || fail "skill name mismatch: $skill_dir"
    skill_names="${skill_names}${skill_name}\n"
  done
  [ -z "$(printf '%b' "$skill_names" | sort | uniq -d)" ] || fail "duplicate skill name in $tree"
done

for detector in \
  "$ROOT/codex/skills/resource-aware-orchestration/scripts/detect_resources.sh" \
  "$ROOT/claude-code/skills/resource-aware-orchestration/scripts/detect_resources.sh"; do
  [ -x "$detector" ] || fail "resource detector is not executable: $detector"
done

[ "$(wc -l < "$ROOT/claude-code/CLAUDE.md" | awk '{ print $1 }')" -lt 200 ] || fail "CLAUDE.md must stay below 200 lines"
if grep -Eiq '\.omo|(^|[^[:alnum:]_])HWT([^[:alnum:]_]|$)|stage[_ -]?[0-9]+|device_id|attempt_limit|bitstream_path|trigger_voltage|capture_count' "$ROOT/codex/AGENTS.md" "$ROOT/claude-code/CLAUDE.md"; then
  fail "project-specific stage or equipment constants leaked into a global prompt"
fi
for prompt in "$ROOT/codex/AGENTS.md" "$ROOT/claude-code/CLAUDE.md"; do
  grep -Fq 'a one-child delegation is invalid' "$prompt" || fail "$prompt does not reject one-child delegation"
  grep -Fq 'use at least two child agents' "$prompt" || fail "$prompt does not require two children"
  grep -Fq 'A concurrency result of one means run the required children sequentially' "$prompt" || fail "$prompt does not require sequential children at concurrency one"
  grep -Fq 'one writing child and one heavy command at a time' "$prompt" || fail "$prompt does not serialize writers and heavy commands"
done
check_exact_line "$ROOT/codex/skills/resource-aware-orchestration/SKILL.md" 'Keep small local work in the main agent. Delegate only when at least two non-overlapping child deliverables exist. Once delegation is selected, run at least two children. A detected concurrency of one requires sequential child execution; it does not permit a one-child delegation. Child agents must not delegate.'

check_exact_line "$ROOT/codex/config.toml.example" 'max_threads = 6'
check_exact_line "$ROOT/codex/config.toml.example" 'max_depth = 1'

while IFS= read -r shell_file; do
  bash -n "$shell_file" || fail "shell syntax failed: $shell_file"
done <<EOF
$(find "$ROOT" -type f -name '*.sh' -not -path "$ROOT/.git/*" | sort)
EOF

marker_pattern='TO''DO|FIX''ME|HA''CK|place''holder|du''mmy|st''ub|tempo''rary'
while IFS= read -r shell_file; do
  if grep -Ein "$marker_pattern" "$shell_file" >/dev/null; then
    fail "unfinished-work marker in shell source: $shell_file"
  fi
done <<EOF
$(find "$ROOT" -type f -name '*.sh' -not -path "$ROOT/.git/*" | sort)
EOF

manifest_entries="$(mktemp "${TMPDIR:-/tmp}/harness-manifest.XXXXXX")"
repository_files="$(mktemp "${TMPDIR:-/tmp}/harness-files.XXXXXX")"
sed -n 's/^- `\(.*\)`/\1/p' "$ROOT/MANIFEST.md" | sort > "$manifest_entries"
find "$ROOT" -type f \
  -not -path "$ROOT/.git/*" \
  -not -name '.DS_Store' \
  | sed "s#^$ROOT/##" | sort > "$repository_files"
missing_manifest_entries="$(comm -13 "$manifest_entries" "$repository_files")"
stale_manifest_entries="$(comm -23 "$manifest_entries" "$repository_files")"
[ -z "$missing_manifest_entries" ] || fail "files missing from MANIFEST.md: $missing_manifest_entries"
[ -z "$stale_manifest_entries" ] || fail "stale MANIFEST.md entries: $stale_manifest_entries"
rm -f "$manifest_entries" "$repository_files"

if [ "$failures" -ne 0 ]; then
  echo "Harness validation failed with $failures finding(s)." >&2
  exit 1
fi

echo "Harness validation passed."
