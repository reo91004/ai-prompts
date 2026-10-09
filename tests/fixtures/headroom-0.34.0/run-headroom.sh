#!/usr/bin/env bash
set -euo pipefail
export HEADROOM_PORT=8787
export HEADROOM_HOST=127.0.0.1
export HEADROOM_MODE=cache
export HEADROOM_BACKEND=anthropic
export HEADROOM_TELEMETRY=off
exec @HOME@/.universal-research-agent-kit/tooling/bin/headroom install agent run --profile research-agent-kit
