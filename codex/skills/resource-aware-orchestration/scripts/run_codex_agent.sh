#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: run_codex_agent.sh <agent-name> [task]" >&2
  echo "       printf '%s' <task> | run_codex_agent.sh <agent-name>" >&2
  exit 2
}

[ "$#" -ge 1 ] || usage
agent_name="$1"
shift

case "$agent_name" in
  ''|*[!A-Za-z0-9_-]*)
    echo "Invalid Codex agent name: $agent_name" >&2
    exit 2
    ;;
esac

codex_home_dir="${CODEX_HOME:-$HOME/.codex}"
agent_file="$codex_home_dir/agents/$agent_name.toml"
[ -f "$agent_file" ] || {
  echo "Codex agent definition not found: $agent_file" >&2
  exit 1
}
command -v codex >/dev/null 2>&1 || {
  echo "Codex CLI is not available" >&2
  exit 1
}

read_single_field() {
  local field="$1"
  local values
  values="$(sed -n "s/^${field} = \"\([^\"]*\)\"$/\1/p" "$agent_file")"
  [ -n "$values" ] && [ "$(printf '%s\n' "$values" | wc -l | awk '{ print $1 }')" -eq 1 ] || {
    echo "Agent definition must contain exactly one $field field: $agent_file" >&2
    exit 1
  }
  printf '%s' "$values"
}

declared_name="$(read_single_field name)"
[ "$declared_name" = "$agent_name" ] || {
  echo "Agent name does not match its filename: $declared_name != $agent_name" >&2
  exit 1
}
model="$(read_single_field model)"
reasoning_effort="$(read_single_field model_reasoning_effort)"
sandbox_mode="$(read_single_field sandbox_mode)"
developer_instructions="$(awk '
  /^developer_instructions = """$/ { inside = 1; next }
  inside && /^"""$/ { found = 1; exit }
  inside { print }
  END { if (!inside || !found) exit 1 }
' "$agent_file")" || {
  echo "Agent definition has invalid developer_instructions: $agent_file" >&2
  exit 1
}
[ -n "$developer_instructions" ] || {
  echo "Agent developer_instructions must not be empty: $agent_file" >&2
  exit 1
}

case "$reasoning_effort" in
  none|minimal|low|medium|high|xhigh|max|ultra) ;;
  *)
    echo "Unsupported reasoning effort in $agent_file: $reasoning_effort" >&2
    exit 1
    ;;
esac
case "$sandbox_mode" in
  read-only|workspace-write|danger-full-access) ;;
  *)
    echo "Unsupported sandbox mode in $agent_file: $sandbox_mode" >&2
    exit 1
    ;;
esac

if [ "$#" -gt 0 ]; then
  task="$*"
elif [ ! -t 0 ]; then
  task="$(</dev/stdin)"
else
  usage
fi
[ -n "$task" ] || {
  echo "Agent task must not be empty" >&2
  exit 2
}

echo "requested_agent=$agent_name"
echo "declared_model=$model"
echo "declared_reasoning_effort=$reasoning_effort"
echo "spawn_transport=isolated_codex_cli"

exec codex exec \
  --ephemeral \
  --model "$model" \
  --sandbox "$sandbox_mode" \
  --config "model_reasoning_effort=\"$reasoning_effort\"" \
  --config "developer_instructions='''$developer_instructions'''" \
  -- "$task"
