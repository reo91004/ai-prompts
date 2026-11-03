"""Local stdio server for installer orchestration tests; never executes a tool."""

import asyncio

from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool


server = Server("installer-sequential-thinking-fixture", version="2.0.0")


@server.list_tools()
async def tools():
    return [Tool(name="sequentialthinking", inputSchema={
        "type": "object", "properties": {"thought": {"type": "string"}},
    })]


async def main():
    async with stdio_server() as (reader, writer):
        await server.run(reader, writer, server.create_initialization_options())


if __name__ == "__main__":
    asyncio.run(main())
