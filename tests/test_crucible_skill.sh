#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/engine/bin"
cat > "$scratch/engine/bin/crucible" <<'CLI'
#!/usr/bin/env bash
printf '%s\n' "$@"
CLI
chmod +x "$scratch/engine/bin/crucible"
actual="$(CRUCIBLE_ROOT="$scratch/engine" "$root/skills/crucible/scripts/crucible.sh" --project 'a b' status)"
expected="$(printf '%s\n' --project 'a b' status)"
[ "$actual" = "$expected" ]
if CRUCIBLE_ROOT="$scratch/missing" "$root/skills/crucible/scripts/crucible.sh" status > /dev/null 2>&1; then
  printf '%s\n' 'Missing engine unexpectedly succeeded' >&2
  exit 1
fi
printf '%s\n' 'PASS: Crucible launcher preserves argv and fails for a missing engine'
