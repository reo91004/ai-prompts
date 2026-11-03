#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_MCP_PYTHON="${KIT_TEST_MCP_PYTHON:-$HOME/.universal-research-agent-kit/tooling/uv-tools/headroom-ai/bin/python}"
if [ ! -x "$TEST_MCP_PYTHON" ] || ! "$TEST_MCP_PYTHON" -I -B -c 'import anyio, mcp' >/dev/null 2>&1; then
  echo 'SKIP: Sequential Thinking transport tests require a Python environment with the MCP SDK.'
  exit 77
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
source "$ROOT/install.sh"
source "$ROOT/scripts/sequential_thinking.sh"
KIT_BACKUP_DIR="$WORK/evidence"
KIT_HEADROOM_PYTHON="$TEST_MCP_PYTHON"
KIT_NPX="$WORK/fixture-npx"
mkdir -p "$KIT_BACKUP_DIR"
printf 'ok\n' > "$WORK/mode"
cat > "$WORK/server.py" <<'PY'
import asyncio
import json
import os
from pathlib import Path
import subprocess
import sys
import time

from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool

mode = Path(sys.argv[1]).read_text().strip()
if mode == "timeout":
    child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(15)"])
    Path(sys.argv[2]).write_text(json.dumps([os.getpid(), child.pid]))
    time.sleep(15)

server = Server("fixture-sequential-thinking", version="fixture-server")


@server.list_tools()
async def tools():
    return [Tool(name="missing" if mode == "missing" else "sequentialthinking", inputSchema={
        "type": "object", "properties": {"thought": {"type": "string"}}
    })]


async def main():
    async with stdio_server() as (reader, writer):
        await server.run(reader, writer, server.create_initialization_options())


asyncio.run(main())
PY
{
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> %q\n' "$WORK/server-calls"
  printf 'exec %q -I -B %q %q %q\n' "$TEST_MCP_PYTHON" "$WORK/server.py" "$WORK/mode" "$WORK/pids.json"
} > "$KIT_NPX"
chmod +x "$KIT_NPX"
MOCK_SEQ_VERSION=2.0.0
MOCK_SEQ_NAME=@modelcontextprotocol/server-sequential-thinking
MOCK_SEQ_ENGINE='>=24'
download_file() {
  [ "$1" = https://registry.npmjs.org/@modelcontextprotocol%2fserver-sequential-thinking/latest ]
  printf '%s\n' "$1" >> "$WORK/downloads"
  node -e 'console.log(JSON.stringify({name:process.argv[1],version:process.argv[2],engines:{node:process.argv[3]},dist:{integrity:"sha512-"+Buffer.alloc(64).toString("base64")}}))' \
    "$MOCK_SEQ_NAME" "$MOCK_SEQ_VERSION" "$MOCK_SEQ_ENGINE" > "$2"
}
prepare_sequential_thinking
[ "$SEQUENTIAL_THINKING_STATE" = verified ]
[ "$SEQUENTIAL_THINKING_PACKAGE" = @modelcontextprotocol/server-sequential-thinking@2.0.0 ]
[ "$SEQUENTIAL_THINKING_NODE_REQUIREMENT" = '>=24' ]
grep -Fqx -- '-y @modelcontextprotocol/server-sequential-thinking@2.0.0' "$WORK/server-calls"
node -e 'const d=require(process.argv[1]);if(d.server_name!=="fixture-sequential-thinking"||d.tool!=="sequentialthinking")process.exit(1);' \
  "$KIT_BACKUP_DIR/sequential-thinking-check.json"
MOCK_SEQ_VERSION=2.0.1
prepare_sequential_thinking
[ "$(wc -l < "$WORK/downloads")" -eq 1 ]
[ "$(wc -l < "$WORK/server-calls")" -eq 1 ]
unset SEQUENTIAL_THINKING_PREPARED SEQUENTIAL_THINKING_RESOLVED
prepare_sequential_thinking
[ "$SEQUENTIAL_THINKING_PACKAGE" = @modelcontextprotocol/server-sequential-thinking@2.0.1 ]
[ "$(wc -l < "$WORK/downloads")" -eq 2 ]
[ "$(wc -l < "$WORK/server-calls")" -eq 2 ]

if (MOCK_SEQ_NAME=another-package SEQUENTIAL_THINKING_PREPARED=0 SEQUENTIAL_THINKING_RESOLVED=0 prepare_sequential_thinking) > "$WORK/bad-name.log" 2>&1; then exit 1; fi
grep -Fq 'Invalid or unsupported stable Sequential Thinking npm metadata' "$WORK/bad-name.log"
if (MOCK_SEQ_ENGINE='>=999' SEQUENTIAL_THINKING_PREPARED=0 SEQUENTIAL_THINKING_RESOLVED=0 prepare_sequential_thinking) > "$WORK/engine.log" 2>&1; then exit 1; fi
grep -Fq 'Sequential Thinking requires Node >=999' "$WORK/engine.log"
if (MOCK_SEQ_ENGINE='^24' SEQUENTIAL_THINKING_PREPARED=0 SEQUENTIAL_THINKING_RESOLVED=0 prepare_sequential_thinking) > "$WORK/engine-range.log" 2>&1; then exit 1; fi
grep -Fq 'Unsupported Sequential Thinking Node engine requirement' "$WORK/engine-range.log"
[ "$(wc -l < "$WORK/server-calls")" -eq 2 ]
printf 'missing\n' > "$WORK/mode"
if (SEQUENTIAL_THINKING_PREPARED=0 prepare_sequential_thinking) > "$WORK/missing-tool.log" 2>&1; then exit 1; fi
grep -Fq 'did not initialize and expose its tool' "$WORK/missing-tool.log"
if check_sequential_thinking @modelcontextprotocol/server-sequential-thinking@latest > "$WORK/unpinned.log" 2>&1; then exit 1; fi
grep -Fq 'requires an exact stable package version' "$WORK/unpinned.log"
printf 'timeout\n' > "$WORK/mode"
if check_sequential_thinking @modelcontextprotocol/server-sequential-thinking@2.0.1 1 > "$WORK/timeout.log" 2>&1; then exit 1; fi
"$TEST_MCP_PYTHON" -I -B - "$WORK/pids.json" <<'PY'
import json
import subprocess
import sys
import time

pids = json.load(open(sys.argv[1]))
deadline = time.monotonic() + 3
while time.monotonic() < deadline:
    live = [pid for pid in pids if (state := subprocess.run(
        ["ps", "-p", str(pid), "-o", "stat="], capture_output=True, text=True
    ).stdout.strip()) and not state.startswith("Z")]
    if not live:
        break
    time.sleep(0.05)
else:
    raise AssertionError(f"Fixture process tree survived the verification timeout: {live}")
PY
echo 'Sequential Thinking version resolution, initialization, and timeout cleanup tests passed.'
