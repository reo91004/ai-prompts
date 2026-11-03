#!/usr/bin/env bash
# Sourced after the kit Node launcher and managed Headroom Python are ready.

check_sequential_thinking() {
  local package="$1" timeout="${2:-120}" python
  python="${KIT_HEADROOM_PYTHON:-$HOME/.universal-research-agent-kit/tooling/uv-tools/headroom-ai/bin/python}"
  [[ "$package" =~ ^@modelcontextprotocol/server-sequential-thinking@[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "Sequential Thinking verification requires an exact stable package version." >&2
    return 1
  }
  [ -x "${KIT_NPX:-}" ] && [ -x "$python" ] || {
    echo "Sequential Thinking verification requires the kit npx launcher and managed Python." >&2
    return 1
  }
  "$python" -I -B - "$KIT_NPX" "$package" "$timeout" "$KIT_BACKUP_DIR/sequential-thinking-server.log" <<'PY'
import asyncio
import json
import sys

import anyio
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

launcher, package, timeout_value, log_path = sys.argv[1:]
timeout = float(timeout_value)
if not 0 < timeout <= 300:
    raise ValueError("Sequential Thinking timeout must be between 0 and 300 seconds")


async def check():
    parameters = StdioServerParameters(command=launcher, args=["-y", package])
    with open(log_path, "a", encoding="utf-8") as errlog:
        async with stdio_client(parameters, errlog=errlog) as (reader, writer):
            async with ClientSession(reader, writer) as session:
                # Keep the deadline inside the transport contexts so normal
                # EOF/terminate process-tree cleanup runs after a timeout.
                with anyio.fail_after(timeout):
                    initialized = await session.initialize()
                    result = await session.list_tools()
                    tool = next((item for item in result.tools if item.name == "sequentialthinking"), None)
                    if tool is None or "thought" not in tool.inputSchema.get("properties", {}):
                        raise ValueError("The server did not expose the sequentialthinking tool schema")
                    print(json.dumps({
                        "package": package,
                        "server_name": initialized.serverInfo.name,
                        "server_version": initialized.serverInfo.version,
                        "tool": tool.name,
                    }))


asyncio.run(check())
PY
}

prepare_sequential_thinking() {
  [ "${SEQUENTIAL_THINKING_PREPARED:-0}" -eq 0 ] || return 0
  if [ "${SEQUENTIAL_THINKING_RESOLVED:-0}" -eq 0 ]; then
    SEQUENTIAL_THINKING_SOURCE=https://registry.npmjs.org/@modelcontextprotocol%2fserver-sequential-thinking/latest
    local metadata="$KIT_BACKUP_DIR/sequential-thinking-release.json" values
    download_file "$SEQUENTIAL_THINKING_SOURCE" "$metadata" || kit_die "Could not resolve Sequential Thinking from npm."
    values="$(node - "$metadata" <<'NODE'
const fs = require('fs'), data = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (data.name !== '@modelcontextprotocol/server-sequential-thinking' ||
    !/^\d+\.\d+\.\d+$/.test(data.version) || !/^sha512-[A-Za-z0-9+/]+={0,2}$/.test(data.dist?.integrity || '')) {
  process.exit(1);
}
const engine = data.engines?.node || '';
const minimum = /^>=(\d+)(?:\.(\d+))?(?:\.(\d+))?$/.exec(engine);
if (!minimum) {
  console.error('Unsupported Sequential Thinking Node engine requirement.');
  process.exit(1);
}
const needed = minimum.slice(1).map(value => Number(value || 0));
const current = process.versions.node.split('.').map(Number);
for (let i = 0; i < 3; i++) {
  if (current[i] > needed[i]) break;
  if (current[i] < needed[i]) {
    console.error(`Sequential Thinking requires Node ${engine}; current Node is ${process.versions.node}.`);
    process.exit(1);
  }
}
console.log(data.version);
console.log(data.dist.integrity);
console.log(engine);
NODE
    )" || kit_die "Invalid or unsupported stable Sequential Thinking npm metadata."
    SEQUENTIAL_THINKING_VERSION="$(printf '%s\n' "$values" | sed -n '1p')"
    SEQUENTIAL_THINKING_INTEGRITY="$(printf '%s\n' "$values" | sed -n '2p')"
    SEQUENTIAL_THINKING_NODE_REQUIREMENT="$(printf '%s\n' "$values" | sed -n '3p')"
    SEQUENTIAL_THINKING_PACKAGE="@modelcontextprotocol/server-sequential-thinking@$SEQUENTIAL_THINKING_VERSION"
    SEQUENTIAL_THINKING_RESOLVED=1
  fi
  SEQUENTIAL_THINKING_STATE=checking
  check_sequential_thinking "$SEQUENTIAL_THINKING_PACKAGE" > "$KIT_BACKUP_DIR/sequential-thinking-check.json" || {
    SEQUENTIAL_THINKING_STATE=failed
    kit_die "Sequential Thinking did not initialize and expose its tool; registration was not verified."
  }
  SEQUENTIAL_THINKING_PREPARED=1
  SEQUENTIAL_THINKING_STATE=verified
}
