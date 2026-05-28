#!/usr/bin/env bash
set -euo pipefail

missing=0
check_path() {
  if [ -e "$1" ]; then
    echo "[OK] $1"
  else
    echo "[MISSING] $1"
    missing=1
  fi
}

check_path "$HOME/.claude/CLAUDE.md"
check_path "$HOME/.claude/agents"
check_path "$HOME/.claude/skills"
check_path "$HOME/.codex/AGENTS.md"
check_path "$HOME/.codex/agents"
check_path "$HOME/.agents/skills"
check_path "$HOME/.config/git/ignore"

python3 - <<'PYVERIFY'
from pathlib import Path
try:
    import tomllib
except Exception:
    print('[WARN] Python tomllib unavailable; skipping TOML validation')
    raise SystemExit(0)
agent_dir = Path.home()/'.codex'/'agents'
if agent_dir.exists():
    for p in sorted(agent_dir.glob('*.toml')):
        try:
            data = tomllib.loads(p.read_text(encoding='utf-8'))
            for key in ['name','description','developer_instructions']:
                if key not in data:
                    raise ValueError(f'missing {key}')
            print(f'[OK] TOML {p.name}')
        except Exception as e:
            print(f'[BAD TOML] {p}: {e}')
            raise
PYVERIFY

if [ "$missing" -ne 0 ]; then
  echo "Some expected files are missing."
  exit 1
fi

echo "Install verification completed."
