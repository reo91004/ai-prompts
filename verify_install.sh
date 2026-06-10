#!/usr/bin/env bash
set -euo pipefail

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
check_exact_dir_entries() {
  local dir="$1"
  shift
  local path name expected found

  if [ ! -d "$dir" ]; then
    return
  fi

  for path in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
    if [ ! -e "$path" ]; then
      continue
    fi

    name="$(basename "$path")"
    if [ "$name" = ".DS_Store" ]; then
      continue
    fi

    found=0
    for expected in "$@"; do
      if [ "$name" = "$expected" ]; then
        found=1
        break
      fi
    done

    if [ "$found" -ne 1 ]; then
      echo "Unexpected managed entry: $path"
      missing=1
    fi
  done
}

check_file "$HOME/.claude/CLAUDE.md"
check_dir "$HOME/.claude/agents"
check_dir "$HOME/.claude/skills"

check_file "$HOME/.codex/AGENTS.md"
check_dir "$HOME/.codex/agents"
check_dir "$HOME/.agents/skills"

claude_agents=(
  adversarial-reviewer
  code-comment-hygiene-reviewer
  context-explorer
  data-ml-experiment-reviewer
  hardware-vivado-reviewer
  implementation-engineer
  literature-method-reviewer
  quality-gate-runner
  research-repo-architect
  report-writer
  sequential-reasoning-coordinator
  side-channel-security-reviewer
  software-architect
  statistics-reviewer
  test-debug-engineer
)

codex_agents=(
  adversarial_reviewer
  code_comment_hygiene_reviewer
  context_explorer
  data_ml_experiment_reviewer
  hardware_vivado_reviewer
  implementation_engineer
  literature_method_reviewer
  quality_gate_runner
  research_repo_architect
  report_writer
  sequential_reasoning_coordinator
  side_channel_security_reviewer
  software_architect
  statistics_reviewer
  test_debug_engineer
)

skills=(
  adversarial-review
  ai-ml-experiment
  code-comment-hygiene
  evidence-gate
  hardware-vivado
  no-placeholder-development
  report-writer
  research-domain-router
  research-repo-design
  sequential-thinking-mcp
  side-channel-analysis
)

claude_agent_files=()
for agent in "${claude_agents[@]}"; do
  claude_agent_files+=("$agent.md")
done

codex_agent_files=()
for agent in "${codex_agents[@]}"; do
  codex_agent_files+=("$agent.toml")
done

for agent in "${claude_agents[@]}"; do
  check_file "$HOME/.claude/agents/$agent.md"
done

for agent in "${codex_agents[@]}"; do
  check_file "$HOME/.codex/agents/$agent.toml"
done

for skill in "${skills[@]}"; do
  check_file "$HOME/.claude/skills/$skill/SKILL.md"
  check_file "$HOME/.agents/skills/$skill/SKILL.md"
done

check_file "$HOME/.claude/skills/research-repo-design/references/research_experiment_repo.md"
check_file "$HOME/.agents/skills/research-repo-design/references/research_experiment_repo.md"
check_file "$HOME/.claude/skills/research-domain-router/references/domain_gates.md"
check_file "$HOME/.agents/skills/research-domain-router/references/domain_gates.md"

check_exact_dir_entries "$HOME/.claude/agents" "${claude_agent_files[@]}"
check_exact_dir_entries "$HOME/.codex/agents" "${codex_agent_files[@]}"
check_exact_dir_entries "$HOME/.claude/skills" "${skills[@]}"
check_exact_dir_entries "$HOME/.agents/skills" "${skills[@]}"

check_file "$HOME/.config/git/ignore"
check_contains "$HOME/.config/git/ignore" "BEGIN UNIVERSAL RESEARCH AGENT KIT"
check_contains "$HOME/.config/git/ignore" "END UNIVERSAL RESEARCH AGENT KIT"

if [ "$missing" -ne 0 ]; then
  echo "Install verification failed."
  exit 1
fi

echo "Install verification passed. Restart Claude Code and Codex sessions."
