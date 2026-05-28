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

check_file "$HOME/.claude/CLAUDE.md"
check_dir "$HOME/.claude/agents"
check_dir "$HOME/.claude/skills"
check_file "$HOME/.claude/skills/code-comment-hygiene/SKILL.md"

check_file "$HOME/.codex/AGENTS.md"
check_dir "$HOME/.codex/agents"
check_dir "$HOME/.agents/skills"
check_file "$HOME/.agents/skills/code-comment-hygiene/SKILL.md"

if [ "$missing" -ne 0 ]; then
  echo "Install verification failed."
  exit 1
fi

echo "Install verification passed. Restart Claude Code and Codex sessions."
