"""Local stdio server for installer orchestration tests; never executes a tool."""

import asyncio

from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import ListToolsResult, PaginatedRequestParams, Tool


server = Server("installer-sequential-thinking-fixture", version="2.0.0")


async def tools():
    return [Tool(name="sequentialthinking", inputSchema={
        "type": "object", "properties": {"thought": {"type": "string"}},
    })]


if hasattr(server, "list_tools"):
    server.list_tools()(tools)
else:
    async def list_tools(context, params):
        return ListToolsResult(tools=await tools())

    server.add_request_handler("tools/list", PaginatedRequestParams, list_tools)


async def main():
    async with stdio_server() as (reader, writer):
        await server.run(reader, writer, server.create_initialization_options())


if __name__ == "__main__":
    asyncio.run(main())
